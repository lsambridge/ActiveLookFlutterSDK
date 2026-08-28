# Known issues & platform divergences

[← Back to docs index](README.md)

Everything on this page was confirmed by reading ActiveLook's own native SDK source directly
(`android-sdk`/`ios-sdk`), not inferred or guessed. Where a bug is in ActiveLook's own SDK rather
than this Flutter bridge, this package calls the native SDK's public API as-is rather than working
around the bug internally — reverse-engineering a fix for a vendor's own bug was judged out of
scope for a wrapper intended to eventually be handed back to that vendor (see the main Engyne
plan doc §7.5/§12).

## Confirmed upstream bugs

### Android: `cfgGetNb()` sends the wrong command ID

Android's `AbstractGlasses.cfgGetNb()` implementation internally reuses the *charging-time query*
command ID instead of its own dedicated command ID. This means the value `cfgGetNb()` returns on
Android is unreliable until ActiveLook fixes this in their own SDK. **iOS's `cfgGetNb()` is
implemented correctly** — the bug is Android-specific.

**Where this matters**: [Firmware configuration](firmware-configuration.md#managing-configurations-firmware-18-and-later).

### iOS: `imgStream()`'s 1bpp dispatcher passes the wrong coordinate

iOS's `imgStream(image:x:y:imgStreamFmt:)` dispatcher, for the `.MONO_1BPP` case, calls through to
`imgStream1bpp(image:x:y:)` passing `x` for *both* the x and y coordinate arguments — a
copy-paste-style bug in ActiveLook's own source (`Glasses.swift`, in the `imgStream` dispatcher
function). Streaming a 1bpp image via the generic `imgStream()` entry point on iOS will therefore
place it at the wrong y-coordinate. This is Android-unaffected (Android has no equivalent
dispatcher bug for this format).

**Where this matters**: [Images & fonts](images-and-fonts.md#images).

### iOS: `fontlist()` callback confirmed broken by ActiveLook's own code comments

iOS's font-listing method (note: named `fontlist()`, lowercase "l" — inconsistent with every other
`xxxList()` method in the same SDK, which are capitalized) carries this source comment directly
from ActiveLook: `WARNING: CALLBACK NOT WORKING as of 3.7.4b`. Do not rely on this returning real
data on iOS until ActiveLook fixes it upstream. Android's `fontList()` has no equivalent flag.

**Where this matters**: [Images & fonts](images-and-fonts.md#fonts).

## Confirmed platform divergences (not bugs — genuinely different SDK design)

### Flow control: Android never reports buffer-full/buffer-ok

iOS's flow-control callback forwards every device state, including buffer-ok/buffer-full. Android's
SDK handles buffer-ok/buffer-full purely internally (to gate its own send queue) and only forwards
the four error states to the public callback. **This is the single most load-bearing divergence in
this package** if you're building real backpressure handling — see
[Connection & device events § Flow control](connection-and-events.md#flow-control) for the full
detail and what to do about it.

### Widget commands: iOS-only, with zero Android equivalent

Confirmed by searching ActiveLook's *entire* Android SDK repository (not just the public `Glasses`
interface) — there is no widget-related code anywhere in `android-sdk`. See
[Widgets](widgets.md).

### `tdbg()`: Android-only, with zero iOS equivalent

The reverse of the above — a legacy diagnostic command that exists only on Android. See
[Firmware configuration § Legacy configuration commands](firmware-configuration.md#legacy-configuration-commands-firmware-17-only).

### The legacy `Configuration` type means different things per platform

Android's native `Configuration` type (used by the legacy `WConfigID`/`RConfigID`/`SetConfigID`
command family) has 5 fields; iOS's type of the same name has only 2. These are genuinely
different wire shapes for a shared command family, not a naming coincidence this bridge failed to
reconcile. See
[Firmware configuration § Legacy configuration commands](firmware-configuration.md#legacy-configuration-commands-firmware-17-only)
for exactly how this package models the union.

### 9-DoF IMU exists on-device but isn't API-accessible on either platform

ActiveLook's glasses have a real accelerometer/gyroscope/magnetometer, but neither native SDK
exposes it via any public API today — the only sensor event either SDK surfaces is a double-tap on
the capacitive touch button ([`sensorTapNotifications`](connection-and-events.md#sensor-tap)).
This is a hardware/firmware limitation shared identically by both platforms, not a divergence
between them — listed here because it's a common point of confusion (the hardware genuinely has
the sensor; the software just doesn't expose it yet).

## Verification depth by platform

The Android (Kotlin) implementation has been **compiled directly** against the real
`com.github.activelook:android-sdk:4.5.9` dependency, and its unit tests run under Robolectric —
both pass (`./gradlew :activelook_sdk:compileDebugKotlin testDebugUnitTest` from
`example/android`). Every Kotlin method call, type, and enum name in the plugin is confirmed
correct by an actual compiler.

The iOS (Swift) implementation has **not been compiled** in the environment this package was
originally built in (no macOS/Xcode toolchain was available). Every method signature and type
field name was instead cross-checked directly against `ios-sdk`'s real source files as a substitute
— a materially weaker guarantee than a real compile. **If you're picking up this package, compiling
`example/ios` on an actual Mac and fixing whatever the compiler finds is the single highest-value
next step**, ahead of even real-hardware testing.

Neither platform has been exercised against a physical pair of glasses yet.
