# activelook_sdk

A Flutter plugin wrapping ActiveLook's official native SDKs
([`ActiveLook/android-sdk`](https://github.com/ActiveLook/android-sdk),
[`ActiveLook/ios-sdk`](https://github.com/ActiveLook/ios-sdk)) for ActiveLook/ENGO Eyewear
smart glasses. There is no official Flutter/Dart SDK from ActiveLook — this package exists to
fill that gap.

**📚 Full developer documentation: [`docs/README.md`](docs/README.md)** — getting started, the
complete API reference by subsystem, platform setup, and a page of confirmed upstream bugs/platform
divergences worth reading before you write backpressure or cross-platform code.

See `docs/plan-race-mode-activelook-glasses.md` in the main Engyne repo (§3, §7, §13) for the
design history and rationale behind this package, if you want the *why* behind decisions rather
than the *how*.

## Status

This package aims for **full API parity with both native SDKs** — a complete Flutter SDK, not just
a slice of one app's needs — see [`docs/README.md`](docs/README.md) for what's covered.

- **Android**: compiles and unit-tests clean against the real `android-sdk` dependency
  (`./gradlew :activelook_sdk:compileDebugKotlin testDebugUnitTest` from `example/android`).
- **iOS**: not yet compiled in this environment (no macOS/Xcode toolchain available while building
  it) — every signature was cross-checked against source instead. **Compiling on a real Mac is the
  top remaining gap**, ahead of real-hardware testing. See
  [`docs/known-issues.md`](docs/known-issues.md#verification-depth-by-platform).
- **Not yet tested against real hardware** on either platform.

## Quickstart

```yaml
dependencies:
  activelook_sdk:
    path: ../ActiveLookSdk
```

```dart
import 'package:activelook_sdk/activelook_sdk.dart';

final sdk = ActivelookSdk();
sdk.startScan().listen((glasses) async {
  await sdk.stopScan();
  await sdk.connect(glasses.id);
});

sdk.connectionState.listen((state) async {
  if (state == ActiveLookConnectionState.connected) {
    await sdk.text(10, 40, ActiveLookTextRotation.bottomLeftToRight, 2, 15, 'Hello');
  }
});
```

Platform setup (Android permissions, iOS CocoaPods/SPM + `Info.plist`) is required before this
builds — see [`docs/platform-setup.md`](docs/platform-setup.md). Full walkthrough:
[`docs/getting-started.md`](docs/getting-started.md).

## Development

```
flutter test                                              # this package's Dart tests
cd example/android && ./gradlew :activelook_sdk:testDebugUnitTest   # Android, real SDK, no device needed
```

There is no CI wired up for this repo yet and no hardware-in-the-loop test harness.
