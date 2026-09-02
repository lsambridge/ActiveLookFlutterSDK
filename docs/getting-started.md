# Getting started

[← Back to docs index](README.md)

## 1. Install

Add as a dependency in your app's `pubspec.yaml`. During development against this repo directly,
use a `path:` dependency:

```yaml
dependencies:
  activelook_sdk:
    path: ../ActiveLookSdk
```

Then platform setup is required on both Android and iOS before it will build — see
**[Platform setup](platform-setup.md)** for the exact Gradle/CocoaPods/`Info.plist` steps. Do this
before running the example below; skipping it produces build errors, not runtime errors.

## 2. Scan for glasses

```dart
import 'package:activelook_sdk/activelook_sdk.dart';

final sdk = ActivelookSdk();

final subscription = sdk.startScan().listen((glasses) {
  print('Found: ${glasses.name} (${glasses.id})');
});

// later
await sdk.stopScan();
await subscription.cancel();
```

`glasses.id` is a MAC address on Android, a CoreBluetooth peripheral UUID string on iOS — treat it
as an opaque identifier, not a portable one. It is **not guaranteed stable across scans on iOS**.

## 3. Connect

```dart
await sdk.connect(glasses.id);

sdk.connectionState.listen((state) {
  switch (state) {
    case ActiveLookConnectionState.connecting:
      print('Connecting…');
    case ActiveLookConnectionState.connected:
      print('Connected!');
    case ActiveLookConnectionState.disconnected:
      print('Disconnected (or lost connection).');
  }
});
```

`connectionState` is the single stream for both intentional and unsolicited disconnects — the
native SDKs deliver connection loss via a callback on the connected-glasses object, not a separate
channel, and this package normalizes both into one stream so you don't need two listeners.

Connection failures throw `ActiveLookConnectionException` — see
**[Error handling](error-handling.md)**.

## 4. Draw something

Once `connectionState` reports `connected`, every draw/query method becomes valid. Before that,
they throw a `PlatformException` with code `NOT_CONNECTED` (see
**[Error handling](error-handling.md)**).

```dart
await sdk.text(10, 40, ActiveLookTextRotation.topLeftToRight, 2, 15, 'Hello, ActiveLook');
await sdk.rect(0, 0, 100, 50);
await sdk.circleFilled(150, 128, 20);
```

See **[Drawing](drawing.md)** for the full vector-drawing API, or
**[Layouts, gauges, pages & animations](layouts-gauges-pages-animations.md)** for higher-level
composition (e.g. a reusable "pace" tile you update by text alone, without re-issuing raw draws
each frame).

## 5. Respect flow control

The glasses have a real, finite command buffer. Before sending draw commands at any sustained
rate, read **[Connection & device events](connection-and-events.md#flow-control)** — there is a
confirmed, load-bearing difference in how Android and iOS report buffer-full state.

## 6. Disconnect

```dart
await sdk.disconnect();
```

## Full example app

`example/lib/main.dart` in this repo is a minimal runnable app that scans, lists discovered
glasses, and connects on tap — a good starting skeleton to copy into a real app.
