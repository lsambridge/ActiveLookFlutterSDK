# Widgets (iOS-only)

[← Back to docs index](README.md)

⚠️ **This entire page describes iOS-only functionality.** Confirmed by searching ActiveLook's full
Android SDK source (not just its public `Glasses` interface) for any widget-related code: there is
**zero equivalent anywhere in `android-sdk`**. Calling any method on this page from a Flutter app
running on Android throws `ActiveLookUnsupportedOnPlatformException` — see
[Error handling](error-handling.md). If you need this functionality cross-platform, you'll need to
compose it yourself from [drawing primitives](drawing.md)/[gauges](layouts-gauges-pages-animations.md#gauges)
for the Android side.

## What widgets are

Pre-composed gauge/chart display components combining an icon, a formatted value string, and a
visual indicator (gauge arc, bar chart, target marker) in one command — a shortcut for a common
composite display pattern that would otherwise take several raw draw calls to build by hand.

```dart
enum ActiveLookWidgetSize { large, thin, half }  // 244×122, 244×61, 122×61 px respectively

enum ActiveLookWidgetValueType {
  text,          // shownValue used as-is
  number,        // adds thousands separator, splits on "." or ","
  durationHms,   // splits on ":" into 3 parts: "0:55:35" → "0:" + "55:" + "35"
  durationHm,    // splits on ":" into 2 parts: "0:55" → "0:" + "55"
  durationMs,    // splits on ":" into 2 parts: "55:35" → "55:" + "35"
}
```

## The seven widget commands

```dart
Future<void> widgetOpenGauge({required size, required x, required y, required value, required imageId,
    required valueType, required unit, required shownValue})

Future<void> widgetRangeGauge({..., required String min, required String max})

Future<void> widgetGaugeZone({..., required int chosenZone, required int zoneCount})

Future<void> widgetTarget({..., required String goal})

Future<void> widgetTargetLeft({..., required String goal})
// same as widgetTarget, but the native SDK clamps `value` to [16, 237] before sending —
// confirmed in ios-sdk's own Glasses.swift source, not documented behavior you'd otherwise expect.

Future<void> widgetBarChart({required size, required x, required y, required imageId, required valueType,
    required unit, required shownValue, required int chosenZone, required int zoneCount,
    required List<int> zoneValues})
// note: no `value` parameter, unlike the gauge variants — the bar chart's visual state comes
// entirely from zoneValues.

Future<void> widgetData({required size, required x, required y, required imageId, required valueType,
    required unit, required shownValue})
// the simplest variant: icon + formatted value, no gauge/chart visual at all.
```

All seven share the same first block of parameters (`size`, `x`, `y`, `imageId`, `valueType`,
`unit`, `shownValue`) representing the widget's position, an icon reference, and how to format the
display value — then each adds its own visual-specific parameters (`value` for a gauge cursor
position, `min`/`max` for a range, `chosenZone`/`zoneCount` for zone-based displays, `goal` for a
target marker).

`x`/`y` position the widget's **bottom-right corner**, not its top-left — this matches the native
SDK's own documented behavior, and is worth calling out since it's the opposite convention from
every other position parameter in this package (drawing primitives, layouts, images all use
top-left).

## Example

```dart
await sdk.widgetOpenGauge(
  size: ActiveLookWidgetSize.large,
  x: 244, y: 122,   // bottom-right corner of the widget
  value: 65,        // gauge cursor at 65%
  imageId: 3,        // a pre-saved icon
  valueType: ActiveLookWidgetValueType.number,
  unit: 'bpm',
  shownValue: '142',
);
```
