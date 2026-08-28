# Troubleshooting

[← Back to docs index](README.md)

Practical first-response steps for problems you'll likely hit while integrating, as opposed to
[Known issues](known-issues.md), which lists confirmed bugs inside ActiveLook's own SDKs. Check
here first; if your symptom matches something in Known issues instead, that page has the deeper
technical detail.

## Scan finds nothing

1. **Check Bluetooth is actually on** — neither native SDK surfaces a clear "Bluetooth is off"
   state through this package's `startScan()` stream today; a scan that silently finds nothing is
   the most common symptom of Bluetooth being disabled. Check the OS-level Bluetooth toggle
   directly on the test device.
2. **Check runtime permissions were actually granted**, not just declared. This package's manifest
   declares the required Bluetooth permissions (see [Platform setup](platform-setup.md)), but your
   app is responsible for requesting the runtime prompt (API 31+ on Android) — a denied or
   never-requested permission produces a silent empty scan, not an error.
3. **Android specifically**: on API ≤30, scanning for BLE devices additionally requires location
   services to be turned on at the OS level (a long-standing Android BLE quirk, not specific to
   this package) — `ACCESS_FINE_LOCATION` being granted is not sufficient on its own if Location is
   toggled off in system settings.
4. **Glasses already connected to another device or app** (e.g. still paired to ActiveLook's own
   demo app, or another phone) may not appear in a scan, depending on the glasses' Bluetooth
   pairing state at the OS level. Check the OS-level Bluetooth device list (Settings → Bluetooth)
   for a stale pairing and forget it if present.
5. **Confirm you're near real ActiveLook hardware** — if you don't have glasses yet, this package
   cannot be exercised past this step; see the main plan doc's hardware-acquisition step. There is
   no simulator/mock mode built into this package (see [Known issues](known-issues.md)).

## `connect()` throws `ActiveLookConnectionException` or times out

- **Retry once** — a single connection attempt failing on the first try after discovery is common
  with BLE in general, not specific to ActiveLook hardware. Re-scan and reconnect rather than
  assuming a hard failure.
- **Check `glasses.id` came from the current scan session.** On iOS in particular, a peripheral UUID
  is "not guaranteed stable across scans" per ActiveLook's own SDK docs — an `id` cached from an
  earlier session may no longer resolve. Re-scan and use a fresh `id` if you're not seeing this
  work.
- **Only one connection at a time is supported** (see [Connection & device
  events](connection-and-events.md#connecting)) — if a previous `connect()` call is still pending
  or another app/session already holds the connection, a new `connect()` may fail or silently
  replace it depending on platform. Call `disconnect()` first if you're not sure of the current
  state.

## Draw commands silently do nothing (no error, nothing appears)

1. **Check `connectionState` is actually `connected`**, not just that `connect()` returned. If
   you're not seeing a `PlatformException` with code `NOT_CONNECTED` (see [Error
   handling](error-handling.md)), the SDK believes it's connected — so the issue is more likely
   coordinate/color values than connection state.
2. **Check your coordinates are within the 304×256 display** (see [Drawing § Display coordinate
   system](drawing.md#display-coordinate-system)) — an off-screen draw call is accepted without
   error by this package (parameter ranges are not validated on the Dart side, see [Error
   handling](error-handling.md#what-this-package-does-not-validate)) but produces no visible
   result.
3. **Check `color`/`grey` isn't set to 0** — a grey level of 0 is effectively invisible against a
   0-background. Call `color(15)` (or whatever value you expect) before drawing if you're not
   explicitly setting it per-call.
4. **If using a saved [layout](layouts-gauges-pages-animations.md#layouts) or
   [gauge](layouts-gauges-pages-animations.md#gauges)**, confirm `layoutSave`/`gaugeSave` actually
   completed (awaited, no thrown exception) before calling `layoutDisplay`/`gaugeDisplay` against
   that ID — a display call against an ID that was never successfully saved is a common source of
   "nothing happens."
5. **Check you're not mid-`holdFlush(hold)`** without a matching `flush` — see [Drawing § General
   device commands](drawing.md#general-device-commands). Commands sent while held are queued, not
   dropped, but they won't render until you call `holdFlush(flush)`.

## Draw commands feel sluggish, or updates seem to pile up/lag behind

This is very likely the flow-control backpressure signal (or its absence) — see [Connection &
device events § Flow control](connection-and-events.md#flow-control) and the same caveat in the
[full session example](full-session-example.md#notes-on-this-example). In short: don't send draw
commands faster than roughly 1-3 times per second for anything continuously updating (a live
number, a moving gauge) until you've done your own throughput testing against real hardware — see
the main plan doc's hardware-test section for why that range specifically.

## `imgSave`/`imgStream` throws `BAD_IMAGE`

The bytes you passed don't decode as an image on the native platform. Double-check:

- The bytes are genuinely **PNG-encoded** (see [Images & fonts](images-and-fonts.md#images)) — not
  raw pixel data, not a different image format with a `.png` extension.
- You're not accidentally passing an empty or truncated byte list (e.g. an unresolved
  `rootBundle.load()` future, or a partially-downloaded file).

## Widget methods throw `ActiveLookUnsupportedOnPlatformException` on Android

This is expected, not a bug — see [Widgets](widgets.md) and [Error
handling](error-handling.md#activelookunsupportedonplatformexception). Every `widgetXxx()` method
is iOS-only; there is no Android equivalent in ActiveLook's own SDK. Branch on platform or catch
this exception and fall back to composing the equivalent from [raw
drawing](drawing.md)/[gauges](layouts-gauges-pages-animations.md#gauges) on Android.

## Build fails after adding this package

Almost always a missed [platform setup](platform-setup.md) step:

- **Android**: check you haven't overridden this plugin's `minSdk = 24` requirement lower in your
  app's own `build.gradle`.
- **iOS**: confirm you actually added the `ActiveLookSDK` CocoaPods/SPM dependency to your **app's**
  Podfile/Package resolution (not just relying on this plugin's own podspec declaring it) — see
  [Platform setup § iOS](platform-setup.md#ios) for the exact snippet. A build error mentioning
  `ActiveLookSDK` module not found almost always means this step was skipped.
- Run `flutter clean` and re-fetch (`flutter pub get`, then `pod install` for iOS) after any
  Podfile/Gradle change — stale native build caches are a common false alarm here.

## Still stuck?

Check [Known issues](known-issues.md) for confirmed upstream ActiveLook SDK bugs that might explain
platform-specific behavior differences, and the main Engyne repo's
`docs/plan-race-mode-activelook-glasses.md` for the broader context this package was built against
(§9 in particular lists the real-hardware validation steps that haven't been done yet — some
symptoms may simply be unexplored territory rather than a bug in this package).
