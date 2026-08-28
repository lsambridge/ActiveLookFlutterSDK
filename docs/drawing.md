# Drawing

[← Back to docs index](README.md)

Everything here requires an active connection (`connectionState == connected`) — see
[Error handling](error-handling.md) for what happens otherwise.

## Display coordinate system

The ActiveLook display is 304×256 px. All `x`/`y` coordinates in this API are plain `int` pixel
values; the native SDKs' own signed/unsigned integer width constraints (`Int16`/`UInt8`/etc.) are
handled internally by the platform bridge — you don't need to think about byte widths from Dart.

## General device commands

```dart
Future<void> power(bool on)
Future<void> clear()
Future<void> grey(int level)          // 0-15, whole-display grey level
Future<void> led(ActiveLookLedState state)   // off | on | toggle | blink
Future<void> luma(int level)          // 0-15, display luminance/brightness
Future<void> sensor(bool enable)      // auto-brightness + gesture detection together
Future<void> gesture(bool enable)     // gesture detection only
Future<void> als(bool enable)         // ambient-light auto-brightness only
Future<void> shift(int x, int y)      // offsets all subsequent draws by (x, y), each -128..127
Future<void> holdFlush(ActiveLookHoldFlushAction action)  // hold | flush
```

`power()` toggles the display power state — distinct from `shutdown()` (see
[Firmware configuration](firmware-configuration.md)), which powers the glasses fully off.

`holdFlush(ActiveLookHoldFlushAction.hold)` batches subsequent draw commands in the device's
graphic engine without rendering them; `holdFlush(ActiveLookHoldFlushAction.flush)` renders
everything queued since the last hold, in one go. Use this to compose multiple draw calls into a
single flicker-free screen update instead of rendering each one as it arrives. **`clear()` is not
affected by hold** — it always executes immediately, per ActiveLook's own protocol documentation.

## Vector drawing primitives

```dart
Future<void> color(int level)     // 0-15 grey level used by subsequent draws
Future<void> point(int x, int y)
Future<void> line(int x1, int y1, int x2, int y2)
Future<void> rect(int x1, int y1, int x2, int y2)          // outline
Future<void> rectFilled(int x1, int y1, int x2, int y2)    // filled
Future<void> circle(int x, int y, int radius)              // outline
Future<void> circleFilled(int x, int y, int radius)        // filled
Future<void> text(int x, int y, ActiveLookTextRotation rotation, int fontSize, int color, String text)
Future<void> polyline(List<int> xyPairs, {int thickness = 1})
```

`polyline`'s `xyPairs` is a flat list: `[x0, y0, x1, y1, x2, y2, ...]`, drawing connected line
segments through each point in order.

`ActiveLookTextRotation` has eight values describing both direction and axis:

```dart
enum ActiveLookTextRotation {
  bottomRightToLeft, bottomLeftToRight,
  leftBottomToTop, leftTopToBottom,
  topLeftToRight, topRightToLeft,
  rightTopToBottom, rightBottomToTop,
}
```

`bottomLeftToRight` is the normal, upright reading direction most UI text should use.

`fontSize` and `color` in `text()` are raw values matching the on-device font ID and 0-15 grey
level, not point sizes — see [Images & fonts](images-and-fonts.md#fonts) for managing custom fonts,
or use whatever built-in font IDs the glasses' active configuration ships with (the default
`ALooK` configuration bundles one font, "Source Sans Pro Semibold," at several pre-baked sizes).

## Why this matters more than it looks

The single biggest technical reason ActiveLook was chosen as a glasses partner (see the main plan
doc's comparison against alternatives) is that these are **real vector draw opcodes**, not a
bitmap-only protocol — a moving element (say, a live pace number or a gap-to-target marker) is a
few bytes per update via `text()`/`line()`, not a full-screen image re-push. Prefer composing
screens from these primitives (or the higher-level [layouts/gauges](layouts-gauges-pages-animations.md)
built on top of them) over falling back to [image commands](images-and-fonts.md) for anything that
changes frequently.
