import '../activelook_sdk.dart';

/// Draws relative to the display's documented "safe area" instead of the
/// raw 304x256 buffer, and optionally corrects for a physical unit whose
/// coordinates render flipped 180deg from what `ActiveLook_API.md`
/// documents.
///
/// ActiveLook's own `ActiveLook_API.md` §6.4 "Useful display area"
/// recommends a 30px horizontal / 25px vertical margin so content stays
/// clear of the optics' peripheral eye-box falloff - their own reference
/// app uses this exact "protection area", leaving an effective 244x206px
/// usable region. Passing `x: 10` to this class's [text]/[rect]/etc. means
/// "10 pixels in from the left edge of that safe area", not 10 pixels from
/// the raw buffer's edge - callers never need to add the margin themselves
/// or reason about where the safe area sits inside the full buffer.
///
/// **The 180deg flip is a real-hardware finding, not documented ActiveLook
/// behavior** - one physical unit (Engyne repo, 2026-09-02) was found to
/// render raw (0,0) at the display's visual bottom-right instead of
/// top-left, contradicting both `ActiveLook_API.md`'s coordinate diagram and
/// its own demo app/README examples. It is not yet confirmed whether this
/// is universal to all ActiveLook units, a firmware-version-specific
/// quirk, or specific to that one physical pair - see
/// `ActiveLook_API.md`'s `rdDevInfo` id 10 ("display orientation"), a
/// per-device-readable field this package does not currently expose, as a
/// plausible root cause worth investigating on a second unit. Pass
/// [flipped] explicitly rather than assuming; default it to whatever your
/// own hardware testing has confirmed for the units you support.
///
/// Usage:
/// ```dart
/// final canvas = ActiveLookSafeCanvas(sdk, flipped: true);
/// // "10 pixels in from the safe area's left edge, 20 down from its top"
/// await canvas.text(10, 20, ActiveLookTextRotation.topLeftToRight, 3, 15, 'Hello');
/// // Centered horizontally in the safe area, given the string's own pixel width.
/// await canvas.textCentered(y: 20, rotation: ActiveLookTextRotation.topLeftToRight,
///     fontSize: 3, color: 15, text: 'Hello', textWidthPx: 90);
/// ```
class ActiveLookSafeCanvas {
  ActiveLookSafeCanvas(this._sdk, {this.flipped = false});

  final ActivelookSdk _sdk;

  /// Whether this physical unit needs the 180deg coordinate flip - see class
  /// doc. `false` (identity/no flip) matches ActiveLook's own documented
  /// behavior; set `true` only for hardware confirmed to need it.
  final bool flipped;

  static const int screenWidth = 304;
  static const int screenHeight = 256;

  /// ActiveLook's own recommended safe-area margins (`ActiveLook_API.md`
  /// §6.4) - not configurable per-instance, since these are the vendor's own
  /// documented recommendation, not something this hardware quirk affects.
  static const int marginLeft = 30;
  static const int marginTop = 25;
  static const int marginRight = 30;
  static const int marginBottom = 25;

  static const int safeWidth = screenWidth - marginLeft - marginRight;
  static const int safeHeight = screenHeight - marginTop - marginBottom;

  /// Translates safe-area-relative ([x], [y]) - origin at the safe area's
  /// own top-left, growing right/down exactly as you'd expect regardless of
  /// [flipped] - into the raw device coordinates this unit actually needs.
  (int, int) _toDevice(num x, num y) {
    final safeX = marginLeft + x;
    final safeY = marginTop + y;
    if (!flipped) return (safeX.round(), safeY.round());
    return ((screenWidth - 1) - safeX.round(), (screenHeight - 1) - safeY.round());
  }

  Future<void> point(int x, int y) {
    final (dx, dy) = _toDevice(x, y);
    return _sdk.point(dx, dy);
  }

  Future<void> line(int x1, int y1, int x2, int y2) {
    final (dx1, dy1) = _toDevice(x1, y1);
    final (dx2, dy2) = _toDevice(x2, y2);
    return _sdk.line(dx1, dy1, dx2, dy2);
  }

  Future<void> rect(int x1, int y1, int x2, int y2) {
    final (dx1, dy1) = _toDevice(x1, y1);
    final (dx2, dy2) = _toDevice(x2, y2);
    return _sdk.rect(dx1, dy1, dx2, dy2);
  }

  Future<void> rectFilled(int x1, int y1, int x2, int y2) {
    final (dx1, dy1) = _toDevice(x1, y1);
    final (dx2, dy2) = _toDevice(x2, y2);
    return _sdk.rectFilled(dx1, dy1, dx2, dy2);
  }

  Future<void> circle(int x, int y, int radius) {
    final (dx, dy) = _toDevice(x, y);
    return _sdk.circle(dx, dy, radius);
  }

  Future<void> circleFilled(int x, int y, int radius) {
    final (dx, dy) = _toDevice(x, y);
    return _sdk.circleFilled(dx, dy, radius);
  }

  /// As `ActivelookSdk.imgDisplay`, but [x]/[y] are safe-area-relative,
  /// same as every other draw method on this class. **Not yet separately
  /// confirmed on real hardware** (2026-09-02) - every other primitive here
  /// (point/line/rect/circle/text) needed [flipped]'s 180deg correction on
  /// the one unit tested so far, so this applies the same correction on the
  /// assumption `imgDisplay` shares that unit's coordinate convention
  /// rather than having its own - check the image lands the same side as
  /// text/shapes the first time this runs on real hardware, and revisit if
  /// it doesn't.
  Future<void> image(int imageId, int x, int y) {
    final (dx, dy) = _toDevice(x, y);
    return _sdk.imgDisplay(imageId, dx, dy);
  }

  /// As [image], but draws the image in [colorValue] (an
  /// [ActiveLookColorPalette] byte) instead of its own saved pixel values -
  /// the image analogue of [rawTextColor], and like it, color-panel
  /// (`MDP08`) glasses only.
  ///
  /// **This is not a color-image command - there isn't one.** The protocol
  /// has no color equivalent of `0x41 imgDisplay` the way `0x3E txtColor`
  /// is the color equivalent of `0x37 txt`, and `imgSave` accepts only
  /// mono formats ([ActiveLookImageFormat] is `mono4bpp`/`mono1bpp`/the
  /// two heatshrink variants - no color format exists on either native
  /// SDK). So this composes the two commands that do exist: `0x3D color`
  /// (via [rawColor]) to set the draw color, then `imgDisplay`, which
  /// renders the saved image with it.
  ///
  /// That composition only reads as a recolor for an image saved as
  /// [ActiveLookImageFormat.mono1bpp] - a 1bpp image is a stencil (each
  /// pixel on/off), so its set pixels take the current color. A `mono4bpp`
  /// image carries its own 16 grey levels per pixel and will keep them,
  /// making this call a no-op on it: save the asset as 1bpp if you want to
  /// tint it here.
  ///
  /// Because [rawColor] sets device *state* rather than being a per-draw
  /// parameter, [colorValue] stays in effect for any later
  /// color-parameterless draw in the same frame - [point], [line],
  /// [rect]/[rectFilled], [circle]/[circleFilled] and further [image]
  /// calls. ([text]/[rawTextColor] each carry their own color argument and
  /// are unaffected.) Set the color you want before those draws rather
  /// than relying on whatever this call left behind.
  Future<void> imageInColor(int imageId, int x, int y, int colorValue) async {
    await rawColor(colorValue);
    await image(imageId, x, y);
  }

  /// Sets the color/grey value used to draw the next shape - passthrough to
  /// `ActivelookSdk.rawColor`, no coordinate translation needed since this
  /// sets state rather than drawing. See that method's doc comment: this is
  /// the real `0x3D color` command (an [ActiveLookColorPalette] byte on
  /// color-panel glasses), not `ActivelookSdk.color` (grey-level only
  /// despite the name).
  Future<void> rawColor(int value) => _sdk.rawColor(value);

  /// As `ActivelookSdk.text`, but [x]/[y] are safe-area-relative. Note that
  /// [x] still anchors the string's near edge in *reading* direction (per
  /// [rotation]), not necessarily its visual left edge once [flipped] is
  /// applied on hardware that needs it - use [textCentered] if you want
  /// true horizontal centering and don't want to reason about that
  /// yourself.
  Future<void> text(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int color,
    String text,
  ) {
    final (dx, dy) = _toDevice(x, y);
    return _sdk.text(dx, dy, rotation, fontSize, color, text);
  }

  /// Draws [text] horizontally centered within the safe area, at safe-area-
  /// relative [y]. Centering requires knowing the string's actual rendered
  /// pixel width, which this package cannot compute itself (font metrics
  /// live in ActiveLook's own on-device font data, never sent back to the
  /// host) - pass your own measurement/estimate as [textWidthPx]. Only
  /// supports [ActiveLookTextRotation.topLeftToRight]/[bottomLeftToRight]
  /// (left-to-right reading direction) - centering a right-to-left or
  /// vertical rotation needs different math this helper doesn't attempt.
  Future<void> textCentered({
    required int y,
    required ActiveLookTextRotation rotation,
    required int fontSize,
    required int color,
    required String text,
    required int textWidthPx,
  }) {
    assert(
      rotation == ActiveLookTextRotation.topLeftToRight ||
          rotation == ActiveLookTextRotation.bottomLeftToRight,
      'textCentered only supports left-to-right rotations',
    );
    final x = (safeWidth - textWidthPx) ~/ 2;
    return this.text(x, y, rotation, fontSize, color, text);
  }

  /// As [text], but [colorValue] is an [ActiveLookColorPalette] byte
  /// (the real `0x3E txtColor` command) instead of [text]'s grey-level-only
  /// parameter - see `ActivelookSdk.rawTextColor`'s doc comment. Color-panel
  /// glasses only.
  Future<void> rawTextColor(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int colorValue,
    String text,
  ) {
    final (dx, dy) = _toDevice(x, y);
    return _sdk.rawTextColor(dx, dy, rotation, fontSize, colorValue, text);
  }
}
