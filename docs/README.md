# ActiveLookSDK developer documentation

A Flutter plugin wrapping ActiveLook's official native SDKs
([`android-sdk`](https://github.com/ActiveLook/android-sdk),
[`ios-sdk`](https://github.com/ActiveLook/ios-sdk)) for ActiveLook/ENGO Eyewear smart glasses.
ActiveLook does not publish an official Flutter/Dart SDK — this package exists to fill that gap.

This is the developer-facing documentation: how to install it, how the API is shaped, and what to
watch out for. For the *why* behind design decisions (why ActiveLook was chosen over other glasses,
why v1 was scoped the way it was, why full API parity was later pursued), see
`docs/plan-race-mode-activelook-glasses.md` in the main Engyne repo — that document is the design
history; these pages are the reference.

## Start here

- **[Getting started](getting-started.md)** — install, connect, draw your first thing on-screen.
- **[Full session example](full-session-example.md)** — a complete, copy-pasteable walkthrough
  (scan → connect → build a screen → live updates → teardown) tying multiple subsystems together.
- **[Connection & device events](connection-and-events.md)** — scanning, connecting, the three
  event streams (battery, flow control, sensor tap), and the confirmed Android/iOS flow-control
  divergence.
- **[Error handling](error-handling.md)** — the exception types this package throws and when.
- **[Troubleshooting](troubleshooting.md)** — practical first-response steps for common problems
  ("scan finds nothing," "draw commands do nothing," build failures), as opposed to confirmed SDK
  bugs (see Known issues below).

> **Generated API reference (dartdoc)**: don't run plain `dart doc .` — the dartdoc 9.0.6 bundled
> with this Flutter SDK crashes (`DocumentationComment._stripDocImports`, a `RangeError`) when
> combined with this Flutter SDK's `sky_engine` docs. This is an upstream dartdoc bug, already
> fixed as of dartdoc 9.0.9 — confirmed by reproducing the crash with a minimal package and
> re-running it against a newer standalone dartdoc. Use a standalone, newer dartdoc instead:
> ```
> dart pub global activate dartdoc
> dart pub global run dartdoc .
> ```
> This generates a full class-by-class HTML reference into `doc/api/` (gitignored — regenerate
> locally or wire into a docs-hosting pipeline rather than committing it). The hand-written pages
> below remain the primary reference regardless — they cover *why*/*when* to use something, which
> generated API docs don't.

## API reference by subsystem

- **[Drawing](drawing.md)** — vector primitives (point/line/rect/circle/text/polyline), display
  state (color/shift/hold-flush), general device commands (power/led/luma/sensors).
- **[Layouts, gauges, pages & animations](layouts-gauges-pages-animations.md)** — the higher-level
  composition commands built on top of raw drawing.
- **[Images & fonts](images-and-fonts.md)** — saving/streaming bitmaps, font management.
- **[Firmware configuration](firmware-configuration.md)** — `cfgSet`/`cfgWrite`/`cfgRead`/etc.,
  the legacy firmware-1.7-only config command family, and statistics queries.
- **[Widgets (iOS-only)](widgets.md)** — the gauge/chart widget family that exists only in
  ActiveLook's iOS SDK.

## Platform notes

- **[Platform setup](platform-setup.md)** — Android Gradle/permissions, iOS CocoaPods/SPM setup,
  `Info.plist` requirements.
- **[Known issues & platform divergences](known-issues.md)** — bugs confirmed in ActiveLook's own
  native SDKs, and places where Android and iOS genuinely behave differently. Read this before
  writing code that assumes identical behavior on both platforms.
- **[Changelog](../CHANGELOG.md)** — what shipped in each release.

## Package layout, for contributors

```
lib/
  activelook_sdk.dart                    — public ActivelookSdk class (what you import)
  activelook_sdk_platform_interface.dart — the platform contract (federated plugin pattern)
  src/
    activelook_types.dart                — all public model/enum/exception types
    activelook_sdk_method_channel.dart   — MethodChannel/EventChannel implementation
android/  — Kotlin bridge to com.github.activelook:android-sdk
ios/      — Swift bridge to ActiveLookSDK
example/  — a minimal Flutter app exercising scan/connect
test/     — Dart unit tests (mocked platform + method channel)
```

This is a standard [federated Flutter plugin](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins):
one Dart-facing API, one platform-interface contract, two native implementations behind it.
