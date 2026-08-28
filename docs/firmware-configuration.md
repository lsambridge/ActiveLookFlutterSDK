# Firmware configuration

[← Back to docs index](README.md)

ActiveLook glasses store one or more named "configurations" in flash — a bundle of layouts, fonts,
images, gauges, and pages that together define a firmware personality. `cfgSet` switches which
configuration is active; the rest of this page manages configurations themselves (writing new
ones, listing what's installed, checking free space).

## Activating a configuration {#configset}

```dart
Future<void> configSet(String name)
```

```dart
await sdk.configSet('ALooK');
```

`'ALooK'` is ActiveLook's own default pre-flashed configuration, bundling ~186 layout templates,
60+ status icons, one font, and 13 small animations — see
[Layouts, gauges, pages & animations](layouts-gauges-pages-animations.md#186-pre-built-layouts-already-on-the-device).
Most integrations should call `configSet('ALooK')` once after connecting, before drawing anything,
unless you've written and activated a custom configuration.

## Managing configurations (firmware 1.8 and later)

```dart
Future<void> cfgWrite(String name, int version, int password)
Future<ActiveLookConfigurationElementsInfo> cfgRead(String name)
Future<List<ActiveLookConfigurationDescription>> cfgList()
Future<void> cfgRename(String oldName, String newName, int password)
Future<void> cfgDelete(String name)
Future<void> cfgDeleteLessUsed()
Future<ActiveLookFreeSpace> cfgFreeSpace()
Future<int> cfgGetNb()
```

`cfgList()` returns one `ActiveLookConfigurationDescription` per installed configuration —
`name`, `size` (bytes), `version`, `usageCount`, `installCount`, and `isSystem` (true for
factory-installed configs like `ALooK`).

`cfgRead(name)` returns element counts for a named configuration (`imageCount`, `layoutCount`,
`fontCount`, `pageCount`, `gaugeCount`, `version`) — useful for checking what a configuration
actually contains before activating it.

`cfgFreeSpace()` returns `totalSize`/`freeSpace` in bytes — check before `cfgWrite`-ing a large new
configuration.

`cfgDeleteLessUsed()` lets the device itself evict its least-used non-system configuration when
storage is tight, rather than you tracking usage yourself.

⚠️ **Known upstream bug**: `cfgGetNb()` on **Android only** has a confirmed bug in ActiveLook's own
SDK — its internal implementation sends the wrong command byte (reusing the charging-time query
instead of its own), so the value it returns on Android should not be trusted until ActiveLook
fixes this upstream. iOS's `cfgGetNb()` is implemented correctly. See
[Known issues](known-issues.md).

`cfgWrite`/`cfgRename`/`cfgDelete` typically require a password matching whatever was set when the
configuration was created — pass `0` if no password was set.

Most of this command family is a power-user/tooling surface (building a configuration-management
UI, or writing your own configuration-authoring pipeline) — a typical Race Mode-style integration
will only ever call `configSet('ALooK')` and never touch the rest of this page.

## Legacy configuration commands (firmware 1.7 only)

```dart
Future<void> legacyWriteConfig(ActiveLookLegacyConfiguration config)
Future<ActiveLookLegacyConfiguration> legacyReadConfig(int number)
Future<void> legacySetConfig(int number)
Future<void> tdbg()   // Android-only diagnostic command
```

This is an older command family (`WConfigID`/`RConfigID`/`SetConfigID` in the native SDKs),
superseded by the `cfgXxx` family above on firmware 1.8+. Only use this if you're specifically
targeting older glasses firmware.

**⚠️ `ActiveLookLegacyConfiguration` has a genuine platform divergence** — this is not a bridge
inconsistency, it reflects the native SDKs' own types being shaped differently:

- Android's native `Configuration` type carries 5 fields: `id`, `version`, `imageCount`,
  `layoutCount`, `fontCount`.
- iOS's native `Configuration` type of the same name carries only 2: `number`, `id`.

This package's `ActiveLookLegacyConfiguration` models the union: `id` and `version` are common to
both; `number` is populated only on iOS (`null` on Android); `androidElementCounts` (a nested
`ActiveLookLegacyConfigurationAndroidDetails` with `imageCount`/`layoutCount`/`fontCount`) is
populated only on Android, and only on values *returned* from `legacyReadConfig` — **it is silently
ignored if you set it on a value passed to `legacyWriteConfig`**, because Android's own
`Configuration.toBytes()` (what actually gets sent over the wire) never encodes those fields either,
even though the type carries them. This mirrors an asymmetry in Android's own SDK, not something
this bridge introduced.

`tdbg()` is a task-debugging command that exists **only on Android** — calling it on iOS throws
`ActiveLookUnsupportedOnPlatformException` (confirmed: no equivalent exists anywhere in
`ActiveLook/ios-sdk`). See [Error handling](error-handling.md).

## Statistics

```dart
Future<int> pixelCount()
Future<int> getChargingCounter()
Future<int> getChargingTime()
Future<void> resetChargingParam()
```

`pixelCount()` returns the number of currently-lit pixels on the display. `getChargingCounter()`
and `getChargingTime()` return lifetime charge-cycle count and cumulative charging minutes;
`resetChargingParam()` zeroes both.

## Shutdown

```dart
Future<void> shutdown()
```

Powers the glasses fully off — distinct from [`power(false)`](drawing.md), which only turns off
the display while keeping the glasses' BLE connection and other subsystems active.
