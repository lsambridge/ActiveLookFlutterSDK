# Platform setup

[← Back to docs index](README.md)

Do this before running anything from [Getting started](getting-started.md) — skipping it produces
build failures, not runtime errors.

## Android

No app-side Gradle changes needed. This plugin's own `android/build.gradle.kts` declares the
dependency on ActiveLook's official SDK via JitPack:

```kotlin
implementation("com.github.activelook:android-sdk:4.5.9")
```

and its own `AndroidManifest.xml` declares the required Bluetooth permissions, which merge into
your app's manifest automatically:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

**Your app is still responsible for requesting the runtime permission prompts** (API 31+
`BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`, or `ACCESS_FINE_LOCATION` on API ≤30) before calling
`startScan()` — this package declares the permissions but does not request them on your behalf, the
same pattern most BLE-pairing Flutter packages follow (e.g. `flutter_reactive_ble`,
`permission_handler`-based flows).

`minSdk = 24` is set by this plugin; your app's own `minSdk` must be ≥ 24.

## iOS

ActiveLook's iOS SDK is **not published to the public CocoaPods trunk** and is not on the Swift
Package Index — confirmed by reading `ios-sdk`'s own podspec directly: it's a git-tag-sourced pod,
never `pod push`ed. Whichever dependency manager your app uses, you must point at the ActiveLook
GitHub repo directly.

### If your app uses CocoaPods

Add to your app's `ios/Podfile`:

```ruby
pod 'ActiveLookSDK', :git => 'https://github.com/ActiveLook/ios-sdk.git', :tag => '4.5.5'
```

Then `pod install` from `ios/`.

### If your app uses Swift Package Manager

This plugin's own `ios/activelook_sdk/Package.swift` already declares the SPM dependency directly:

```swift
.package(url: "https://github.com/ActiveLook/ios-sdk.git", exact: "4.5.5")
```

No extra app-side step should be needed when your app resolves this plugin via SPM — Flutter's SPM
plugin support pulls this transitively.

### `Info.plist`

Add `NSBluetoothAlwaysUsageDescription` to your app's `Info.plist` — this is mandatory for any
CoreBluetooth use in iOS and **cannot be declared by a plugin on your app's behalf**:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to connect to your ActiveLook glasses.</string>
```

If you need the glasses connection to survive the app being backgrounded mid-session, also add the
`bluetooth-central` background mode under `UIBackgroundModes`.

### iOS SDK currency

`ios-sdk`'s last commit at time of writing is 2024-06-03 (v4.5.5) — noticeably staler than
Android's actively-maintained v4.5.9 (commits through 2026-05-05). Spot-check this against
ActiveLook's current firmware/protocol version before assuming iOS support is equally solid.

## Verifying your setup compiles

Neither platform needs a physical pair of glasses to verify the build wiring itself:

**Android** — compile and unit-test the plugin directly, no device/emulator required:

```
cd example/android
./gradlew :activelook_sdk:compileDebugKotlin
./gradlew :activelook_sdk:testDebugUnitTest
```

**iOS** — open `example/ios/Runner.xcworkspace` in Xcode and build for a simulator or device; there
is currently no command-line-only verification step documented for this repo (see
[Known issues](known-issues.md) for the verification-depth gap this leaves on iOS).
