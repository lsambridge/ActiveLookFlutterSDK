# Layouts, gauges, pages & animations

[← Back to docs index](README.md)

These are higher-level composition commands built on top of the raw [drawing](drawing.md)
primitives — save a reusable element once, then cheaply re-display it by ID with new content,
instead of re-issuing raw draw calls every update.

## Layouts

A layout is a saved, reusable single-value display region — position, size, colors, font, and text
alignment baked in — that you then update just by sending new text.

```dart
Future<void> layoutSave(ActiveLookLayoutParameters layout)
Future<void> layoutDisplay(int id, String text)               // display at the layout's saved position
Future<void> layoutDisplayExtended(int id, int x, int y, String text)  // display at an explicit position (not saved)
Future<void> layoutClear(int id)
Future<void> layoutClearAndDisplay(int id, String text)
Future<void> layoutDelete(int id)
Future<List<int>> layoutList()   // ids of all layouts currently saved on the device
```

```dart
const layout = ActiveLookLayoutParameters(
  id: 1,
  x: 10, y: 10, width: 100, height: 30,
  foregroundColor: 15, backgroundColor: 0,
  font: 0,
  textValid: true,
  textX: 5, textY: 5,
  textRotation: ActiveLookTextRotation.topLeftToRight,
  textOpacity: true,
);
await sdk.layoutSave(layout);
await sdk.layoutDisplay(1, '142 bpm');
// later, cheaply:
await sdk.layoutDisplay(1, '145 bpm');
```

**Not wrapped, deliberately**: the native SDKs' `LayoutParameters` also supports an
`addSubCommandXxx(...)` builder for embedding extra draw primitives (bitmap, circle, line, rect,
text, gauge, animation, polyline) *inside* a saved layout definition. That's real native
functionality — it's excluded here because no concrete layout design existed yet to drive which
sub-commands would actually be needed; adding it is straightforward once a real design calls for
it. See `lib/src/activelook_types.dart`'s `ActiveLookLayoutParameters` doc comment for the same
note in-code.

### 186 pre-built layouts already on the device

ActiveLook's default `ALooK` firmware configuration (see
[Firmware configuration](firmware-configuration.md#configset)) ships with roughly 186 pre-built
layout IDs already flashed — single-metric tiles like a pace readout, heart-rate display, or
countdown timer, each with position/size/font/alignment already defined. You can call
`layoutDisplay()` against these IDs directly without ever calling `layoutSave()` yourself — check
ActiveLook's `Activelook-Visual-Assets` repo for the ID reference.

## Gauges

An arc-based radial progress indicator — a strong fit for a "gap to target" or "effort" readout.

```dart
Future<void> gaugeSave(ActiveLookGaugeInfo gauge)
Future<void> gaugeDisplay(int id, int valuePercent)   // 0-100
Future<void> gaugeDelete(int id)
```

```dart
const gauge = ActiveLookGaugeInfo(
  id: 1,
  x: 150, y: 128,           // center
  externalRadius: 100, internalRadius: 80,
  startAngle: 1, endAngle: 16,   // segments, 1-16 range per the native protocol
  clockwise: true,
);
await sdk.gaugeSave(gauge);
await sdk.gaugeDisplay(1, 42);  // 42%
```

## Pages

A page groups several layouts into one composite screen, positioned relative to each other.

```dart
Future<void> pageSave(int id, List<int> layoutIds, List<int> xs, List<int> ys)
Future<void> pageDisplay(int id, List<String> texts)   // one text value per layout in layoutIds, same order
Future<void> pageClear(int id)
Future<void> pageDelete(int id)
```

`layoutIds`, `xs`, and `ys` must be the same length — each index describes one layout's ID and its
position within the page. `pageDisplay`'s `texts` list must line up positionally with `layoutIds`.

## Animations

```dart
Future<void> animDisplay(int handlerId, int animId, int frameDelayMs, int repeatCount, int x, int y)
Future<void> animClear(int handlerId)
```

`animId` identifies a pre-saved animation sequence on the device (the default `ALooK` config ships
13 small ones: splash screen, countdown, low-battery overlay, "Bluetooth lost" overlay, pause
overlay). `handlerId` is a value **you choose** at call time to identify this particular playing
instance — pass the same `handlerId` to `animClear()` later to stop it. `repeatCount` of `0xFF`
(255) means infinite repetition.

There is currently no `animSave`/custom-animation-authoring command wrapped by either native SDK
(both mark it as a `// TODO` in their own source) — animations are limited to whatever IDs the
device's active firmware configuration already has flashed.
