/// A pair of glasses discovered during a scan, not yet connected.
class ActiveLookDiscoveredGlasses {
  const ActiveLookDiscoveredGlasses({
    required this.id,
    required this.name,
    required this.manufacturer,
  });

  /// Platform-specific identifier: a MAC address on Android, a CoreBluetooth
  /// peripheral UUID (string form) on iOS. Not guaranteed stable across scans
  /// on iOS.
  final String id;
  final String name;
  final String manufacturer;

  factory ActiveLookDiscoveredGlasses.fromMap(Map<Object?, Object?> map) {
    return ActiveLookDiscoveredGlasses(
      id: map['id'] as String,
      name: map['name'] as String,
      manufacturer: map['manufacturer'] as String? ?? '',
    );
  }
}

enum ActiveLookConnectionState { disconnected, connecting, connected }

/// The device's flow-control ("Control server") signal — see
/// `ActiveLook_API.md` §3.5.
///
/// **Platform divergence, confirmed by reading both native SDKs' source
/// (see `docs/plan-race-mode-activelook-glasses.md` §13 in the Engyne
/// repo):** iOS's `Glasses.subscribeToFlowControlNotifications` forwards
/// every state including buffer-ok/buffer-full ("on"/"off" in its own
/// `FlowControlState` enum); Android's SDK handles buffer-ok/buffer-full
/// purely internally to gate its own send queue and only forwards the
/// error states below to `subscribeToFlowControlNotifications`. Concretely:
/// [bufferFull]/[bufferOk] are iOS-only today. Do not build Race Mode
/// backpressure handling that assumes [bufferFull] arrives on Android —
/// gate sends on write-call latency/errors there instead, or treat this as
/// an open item for the Android bridge to close before relying on it.
enum ActiveLookFlowControlStatus { bufferFull, bufferOk, cmdError, overflow, missingConfigId, reserved }

/// Text rotation for `txt()`, as defined in `ActiveLook_API.md` §4.6.
enum ActiveLookTextRotation {
  bottomRightToLeft,
  bottomLeftToRight,
  leftBottomToTop,
  leftTopToBottom,
  topLeftToRight,
  topRightToLeft,
  rightTopToBottom,
  rightBottomToTop,
}

enum ActiveLookLedState { off, on, toggle, blink }

/// The device's persisted per-unit settings (`ActiveLook_API.md` §4.3's
/// `settings` command, `0x0A`) — read them via `ActivelookSdk.settings()`.
///
/// [xShift]/[yShift] are the same values `shift(x, y)` sets, persisted on
/// the device across power cycles and firmware/factory calibration for that
/// physical unit's mechanical/optical mounting (`ActiveLook_API.md` §5.8) —
/// **not necessarily (0, 0)** on a real pair of glasses. Read this before
/// ever calling `shift()` yourself, rather than assuming/overwriting a
/// value you haven't seen: real-hardware testing (Engyne repo, 2026-09-02)
/// found a `shift(0, 0)` call visibly pushed content off-screen on a unit
/// whose actual calibration was non-zero.
class ActiveLookGlassesSettings {
  const ActiveLookGlassesSettings({
    required this.xShift,
    required this.yShift,
    required this.luma,
    required this.alsEnabled,
    required this.gestureEnabled,
  });

  final int xShift;
  final int yShift;

  /// Display luminance, 0-15.
  final int luma;

  /// Whether ambient-light-sensor auto-brightness is currently enabled.
  final bool alsEnabled;

  /// Whether gesture detection is currently enabled.
  final bool gestureEnabled;

  factory ActiveLookGlassesSettings.fromMap(Map<Object?, Object?> map) {
    return ActiveLookGlassesSettings(
      xShift: map['xShift'] as int? ?? 0,
      yShift: map['yShift'] as int? ?? 0,
      luma: map['luma'] as int? ?? 0,
      alsEnabled: map['alsEnabled'] as bool? ?? false,
      gestureEnabled: map['gestureEnabled'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'ActiveLookGlassesSettings(xShift: $xShift, yShift: $yShift, luma: $luma, '
      'alsEnabled: $alsEnabled, gestureEnabled: $gestureEnabled)';
}

/// Whether the on-device graphic engine should batch subsequent draw
/// commands (`hold`) or render them immediately (`flush`) — see
/// `ActiveLook_API.md` §4.9 / this repo's plan doc §10a "two draw models."
enum ActiveLookHoldFlushAction { hold, flush }

class ActiveLookDeviceInformation {
  const ActiveLookDeviceInformation({
    this.manufacturerName,
    this.modelNumber,
    this.serialNumber,
    this.hardwareVersion,
    this.firmwareVersion,
    this.softwareVersion,
  });

  final String? manufacturerName;
  final String? modelNumber;
  final String? serialNumber;
  final String? hardwareVersion;
  final String? firmwareVersion;
  final String? softwareVersion;

  factory ActiveLookDeviceInformation.fromMap(Map<Object?, Object?> map) {
    return ActiveLookDeviceInformation(
      manufacturerName: map['manufacturerName'] as String?,
      modelNumber: map['modelNumber'] as String?,
      serialNumber: map['serialNumber'] as String?,
      hardwareVersion: map['hardwareVersion'] as String?,
      firmwareVersion: map['firmwareVersion'] as String?,
      softwareVersion: map['softwareVersion'] as String?,
    );
  }
}

/// Parameters for a saved layout — mirrors the native SDKs' `LayoutParameters`
/// constructor (confirmed by reading `LayoutParameters.java`/`.swift`
/// directly): id, position/size, foreground/background/font, a text
/// sub-position + rotation + text-opacity flag.
///
/// The native `LayoutParameters` also supports an `addSubCommandXxx(...)`
/// builder for embedding extra draw primitives (bitmap/circle/line/rect/
/// text/gauge/anim/polyline) directly inside a saved layout - only the
/// bitmap sub-command ([imageId]/[imageX]/[imageY]) is wrapped here so far,
/// needed for Engyne's own glasses config (icon + text per stat row, see
/// `RaceModeGlassesHud`). The rest are still deliberately unwrapped until a
/// real layout design needs them.
class ActiveLookLayoutParameters {
  const ActiveLookLayoutParameters({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.foregroundColor = 15,
    this.backgroundColor = 0,
    this.font = 0,
    this.textValid = true,
    this.textX = 0,
    this.textY = 0,
    this.textRotation = ActiveLookTextRotation.topLeftToRight,
    this.textOpacity = true,
    this.imageId,
    this.imageX = 0,
    this.imageY = 0,
  });

  final int id;
  final int x;
  final int y;
  final int width;
  final int height;
  final int foregroundColor;
  final int backgroundColor;
  final int font;
  final bool textValid;
  final int textX;
  final int textY;
  final ActiveLookTextRotation textRotation;
  final bool textOpacity;

  /// Embeds a saved image (`imgSave`'d separately) as a fixed sub-element of
  /// this layout, at ([imageX], [imageY]) relative to this layout's own
  /// (x, y) clipping region — matches the native SDKs'
  /// `LayoutParameters.addSubCommandBitmap(id, x, y)` builder
  /// (`ActiveLook_API.md` §5.10's "additional graphical commands" table,
  /// command id 0 "image"). Null (the default) saves a layout with no
  /// embedded image, same as before this field existed. Only the single
  /// bitmap sub-command is supported — the native builder also supports
  /// circ/circf/color/font/line/point/rect/rectf/text/gauge/anim/polyline
  /// sub-commands, deliberately left out until a real layout design needs
  /// them (see this class's original doc comment on why sub-commands were
  /// scoped out entirely at first).
  final int? imageId;
  final int imageX;
  final int imageY;

  Map<String, Object?> toMap() => {
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'foregroundColor': foregroundColor,
        'backgroundColor': backgroundColor,
        'font': font,
        'textValid': textValid,
        'textX': textX,
        'textY': textY,
        'textRotation': textRotation.name,
        'textOpacity': textOpacity,
        if (imageId != null) 'imageId': imageId,
        'imageX': imageX,
        'imageY': imageY,
      };

  /// Deserializes `layoutGet`'s response — note the response has no `id`
  /// field (`ActiveLook_API.md` §4.9: "Layouts parameters without `id`"),
  /// so [id] must be supplied by the caller (the id it asked `layoutGet`
  /// for), not read from [map].
  factory ActiveLookLayoutParameters.fromMap(int id, Map<Object?, Object?> map) {
    return ActiveLookLayoutParameters(
      id: id,
      x: map['x'] as int? ?? 0,
      y: map['y'] as int? ?? 0,
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      foregroundColor: map['foregroundColor'] as int? ?? 15,
      backgroundColor: map['backgroundColor'] as int? ?? 0,
      font: map['font'] as int? ?? 0,
      textValid: map['textValid'] as bool? ?? false,
      textX: map['textX'] as int? ?? 0,
      textY: map['textY'] as int? ?? 0,
      textRotation: _rotationFromName(map['textRotation'] as String?),
      textOpacity: map['textOpacity'] as bool? ?? true,
    );
  }

  static ActiveLookTextRotation _rotationFromName(String? name) {
    for (final r in ActiveLookTextRotation.values) {
      if (r.name == name) return r;
    }
    return ActiveLookTextRotation.topLeftToRight;
  }
}

/// Parameters for a saved gauge — mirrors `gaugeSave` in both native SDKs
/// (`ActiveLook_API.md` §4.10).
class ActiveLookGaugeInfo {
  const ActiveLookGaugeInfo({
    required this.id,
    required this.x,
    required this.y,
    required this.externalRadius,
    required this.internalRadius,
    required this.startAngle,
    required this.endAngle,
    this.clockwise = true,
  });

  final int id;
  final int x;
  final int y;
  final int externalRadius;
  final int internalRadius;
  final int startAngle;
  final int endAngle;
  final bool clockwise;

  Map<String, Object?> toMap() => {
        'id': id,
        'x': x,
        'y': y,
        'externalRadius': externalRadius,
        'internalRadius': internalRadius,
        'startAngle': startAngle,
        'endAngle': endAngle,
        'clockwise': clockwise,
      };
}

/// Thrown for connection failures reported by the native SDK — a discovery
/// timeout, GATT error, or `onConnectionFail`/`connectionErrorCallback` from
/// the underlying `Sdk`/`ActiveLookSDK` singleton.
class ActiveLookConnectionException implements Exception {
  ActiveLookConnectionException(this.message);
  final String message;

  @override
  String toString() => 'ActiveLookConnectionException: $message';
}

/// Thrown when a method is called on a platform whose native ActiveLook SDK
/// does not expose it at all — confirmed by reading both SDKs' source, not a
/// bridge omission. Concretely: [ActiveLookWidgetSize]/`widgetXxx()` methods
/// are iOS-only (zero widget commands exist anywhere in `android-sdk`);
/// `tdbg()` is Android-only (no iOS equivalent).
class ActiveLookUnsupportedOnPlatformException implements Exception {
  ActiveLookUnsupportedOnPlatformException(this.method, this.platform);
  final String method;
  final String platform;

  @override
  String toString() =>
      'ActiveLookUnsupportedOnPlatformException: $method is not available on $platform '
      "(ActiveLook's own native SDK for $platform does not expose it)";
}

/// On-device image storage format for `imgSave*`/`imgStream*` — mirrors
/// `ImgSaveFormat`/`ImgSaveFmt` in both native SDKs (case names and wire
/// values confirmed identical on both platforms).
enum ActiveLookImageFormat { mono4bpp, mono1bpp, mono4bppHeatshrink, mono4bppHeatshrinkSaveComp }

/// Streaming-only image format for `imgStream()` — a strict subset of
/// [ActiveLookImageFormat]: only these two variants support streaming
/// (drawing without saving to device memory) on either native SDK.
enum ActiveLookImageStreamFormat { mono1bpp, mono4bppHeatshrink }

class ActiveLookImageInfo {
  const ActiveLookImageInfo({required this.id, required this.width, required this.height});

  final int id;
  final int width;
  final int height;

  factory ActiveLookImageInfo.fromMap(Map<Object?, Object?> map) => ActiveLookImageInfo(
        id: map['id'] as int,
        width: map['width'] as int,
        height: map['height'] as int,
      );
}

class ActiveLookFontInfo {
  const ActiveLookFontInfo({required this.id, required this.height});

  final int id;
  final int height;

  factory ActiveLookFontInfo.fromMap(Map<Object?, Object?> map) =>
      ActiveLookFontInfo(id: map['id'] as int, height: map['height'] as int);
}

/// Metadata for one on-device firmware configuration, as listed by
/// `cfgList` — mirrors `ConfigurationDescription` (fields align 1:1 by name
/// on both native SDKs, confirmed by reading both).
class ActiveLookConfigurationDescription {
  const ActiveLookConfigurationDescription({
    required this.name,
    required this.size,
    required this.version,
    required this.usageCount,
    required this.installCount,
    required this.isSystem,
  });

  final String name;
  final int size;
  final int version;
  final int usageCount;
  final int installCount;
  final bool isSystem;

  factory ActiveLookConfigurationDescription.fromMap(Map<Object?, Object?> map) {
    return ActiveLookConfigurationDescription(
      name: map['name'] as String,
      size: map['size'] as int,
      version: map['version'] as int,
      usageCount: map['usageCount'] as int,
      installCount: map['installCount'] as int,
      isSystem: map['isSystem'] as bool,
    );
  }
}

/// The response shape of `cfgRead` — element counts for the active/named
/// configuration. Fields align 1:1 by name on both native SDKs.
class ActiveLookConfigurationElementsInfo {
  const ActiveLookConfigurationElementsInfo({
    required this.version,
    required this.imageCount,
    required this.layoutCount,
    required this.fontCount,
    required this.pageCount,
    required this.gaugeCount,
  });

  final int version;
  final int imageCount;
  final int layoutCount;
  final int fontCount;
  final int pageCount;
  final int gaugeCount;

  factory ActiveLookConfigurationElementsInfo.fromMap(Map<Object?, Object?> map) {
    return ActiveLookConfigurationElementsInfo(
      version: map['version'] as int,
      imageCount: map['imageCount'] as int,
      layoutCount: map['layoutCount'] as int,
      fontCount: map['fontCount'] as int,
      pageCount: map['pageCount'] as int,
      gaugeCount: map['gaugeCount'] as int,
    );
  }
}

class ActiveLookFreeSpace {
  const ActiveLookFreeSpace({required this.totalSize, required this.freeSpace});

  final int totalSize;
  final int freeSpace;

  factory ActiveLookFreeSpace.fromMap(Map<Object?, Object?> map) =>
      ActiveLookFreeSpace(totalSize: map['totalSize'] as int, freeSpace: map['freeSpace'] as int);
}

/// The legacy (firmware 1.7-only) `WConfigID`/`RConfigID`/`SetConfigID`
/// command family's config identifier.
///
/// **Confirmed platform divergence, not a bridge limitation**: Android's
/// native `Configuration` type (used by this same legacy command family) has
/// 5 fields (`id`, `version`, `nbImg`, `nbLayout`, `nbFont`); iOS's type of
/// the same name has only 2 (`number`, `id`) plus 3 always-zero deprecated
/// bytes. These are genuinely different wire shapes for the same command
/// family, not an inconsistent reading of one shape — reading both SDKs'
/// source directly confirms iOS's `RConfigID` response is 5 bytes total
/// (`number` + 4-byte `id`), while Android's models a different, larger
/// payload. This type intentionally only carries the fields common to both
/// (`id`, `version`); use [ActiveLookLegacyConfiguration.androidElementCounts]
/// for the Android-only element-count fields when running on Android.
///
/// **Important asymmetry confirmed by reading `Configuration.java` directly**:
/// Android's `Configuration.toBytes()` (what `WConfigID`/`legacyWriteConfig`
/// actually sends over the wire) only encodes `id` + `version` + 3 zero
/// bytes — it does **not** send `nbImg`/`nbLayout`/`nbFont` at all, even
/// though the type carries those fields. [androidElementCounts] is therefore
/// populated on a value returned from [ActivelookSdk.legacyReadConfig] but is
/// silently ignored if set on a value passed to
/// [ActivelookSdk.legacyWriteConfig] — this mirrors Android's own SDK
/// behavior exactly, not a bridge limitation.
class ActiveLookLegacyConfiguration {
  const ActiveLookLegacyConfiguration({
    required this.id,
    this.version = 0,
    this.number,
    this.androidElementCounts,
  });

  final int id;

  /// The 4-byte version field both platforms' wire formats carry.
  final int version;

  /// iOS-only: the config slot number. Null on Android.
  final int? number;

  /// Android-only, read-only: element-count fields present in a
  /// `legacyReadConfig` response. Never sent by `legacyWriteConfig` — see
  /// this class's doc comment. Null on iOS, and null on a value you
  /// construct yourself to pass to `legacyWriteConfig`.
  final ActiveLookLegacyConfigurationAndroidDetails? androidElementCounts;

  Map<String, Object?> toMap() => {'id': id, 'version': version, 'number': number};

  factory ActiveLookLegacyConfiguration.fromMap(Map<Object?, Object?> map) {
    return ActiveLookLegacyConfiguration(
      id: map['id'] as int,
      version: map['version'] as int? ?? 0,
      number: map['number'] as int?,
      androidElementCounts: map['androidElementCounts'] == null
          ? null
          : ActiveLookLegacyConfigurationAndroidDetails.fromMap(
              map['androidElementCounts'] as Map<Object?, Object?>,
            ),
    );
  }
}

class ActiveLookLegacyConfigurationAndroidDetails {
  const ActiveLookLegacyConfigurationAndroidDetails({
    required this.version,
    required this.imageCount,
    required this.layoutCount,
    required this.fontCount,
  });

  final int version;
  final int imageCount;
  final int layoutCount;
  final int fontCount;

  factory ActiveLookLegacyConfigurationAndroidDetails.fromMap(Map<Object?, Object?> map) {
    return ActiveLookLegacyConfigurationAndroidDetails(
      version: map['version'] as int,
      imageCount: map['imageCount'] as int,
      layoutCount: map['layoutCount'] as int,
      fontCount: map['fontCount'] as int,
    );
  }
}

/// Widget size for `widgetXxx()` commands — iOS-only (see
/// [ActiveLookUnsupportedOnPlatformException]; confirmed zero widget
/// commands exist in ActiveLook's Android SDK).
enum ActiveLookWidgetSize {
  /// 244 x 122 px.
  large,

  /// 244 x 61 px.
  thin,

  /// 122 x 61 px.
  half,
}

/// How a widget's `shownValue` string is formatted/split for display —
/// iOS-only, see [ActiveLookWidgetSize].
enum ActiveLookWidgetValueType {
  text,
  number,

  /// Splits on ":" into 3 parts, e.g. "0:55:35".
  durationHms,

  /// Splits on ":" into 2 parts, e.g. "0:55".
  durationHm,

  /// Splits on ":" into 2 parts, e.g. "55:35".
  durationMs,
}
