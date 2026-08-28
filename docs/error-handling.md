# Error handling

[← Back to docs index](README.md)

## Exception types this package defines

```dart
class ActiveLookConnectionException implements Exception {
  final String message;
}

class ActiveLookUnsupportedOnPlatformException implements Exception {
  final String method;
  final String platform;
}
```

### `ActiveLookConnectionException`

Thrown when `connect()` fails — a scan/connect timeout, a GATT-level BLE error, or the native
SDK's own connection-error callback firing. The `message` is passed through from the native side
and is not a stable, matchable string — treat it as human-readable diagnostic text, not a code to
branch on.

### `ActiveLookUnsupportedOnPlatformException`

Thrown when you call a method that ActiveLook's own native SDK for the *current* platform simply
does not expose — this is not a bug in this package, it's a real capability gap between Android and
iOS in ActiveLook's own SDKs, confirmed by reading both SDKs' source directly (see
[Known issues](known-issues.md)). Concretely, this fires for:

- Any [`widgetXxx()`](widgets.md) method on Android (iOS-only feature).
- `tdbg()` on iOS (Android-only legacy diagnostic command).

```dart
try {
  await sdk.widgetOpenGauge(/* ... */);
} on ActiveLookUnsupportedOnPlatformException catch (e) {
  // e.method == 'widgetOpenGauge', e.platform == 'Android'
  // fall back to composing the equivalent from drawing.md primitives
}
```

If your app needs to support both platforms and calls any of these methods, check
`defaultTargetPlatform` (or catch this exception) and branch to an equivalent built from
[raw drawing](drawing.md)/[gauges](layouts-gauges-pages-animations.md#gauges) on the unsupported
platform, rather than letting the exception surface to users.

## `PlatformException` codes

Everything else — a command sent with no connected glasses, a bad image payload, a native-side
error — surfaces as Flutter's own `PlatformException`, not a type from this package. Codes you may
see:

| Code | When | 
|---|---|
| `NOT_CONNECTED` | Any draw/query command called while `connectionState != connected`. |
| `NOT_FOUND` | `connect(id)` called with an `id` that wasn't returned by a `startScan()` result in the current scan session. |
| `BAD_IMAGE` | `imgSave`/`imgStream` called with bytes that don't decode as a valid image (must be PNG-encoded — see [Images & fonts](images-and-fonts.md)). |
| `SCAN_ERROR` | A scan-time error from the native SDK (e.g. Bluetooth powered off) — delivered as an error event on the `startScan()` stream, not a thrown exception; handle it in your `StreamSubscription`'s `onError`. |

```dart
try {
  await sdk.clear();
} on PlatformException catch (e) {
  if (e.code == 'NOT_CONNECTED') {
    // reconnect or prompt the user
  }
}
```

## What this package does *not* validate

Parameter ranges (grey levels 0-15, gauge angle segments 1-16, coordinate bounds against the
304×256 display, etc.) are **not validated on the Dart side** — out-of-range values are passed
through to the native SDK, whose own behavior for invalid input is not something this package's
own testing has characterized (see the main plan doc's real-hardware test as the gating step for
that kind of validation work). Stay within each parameter's documented range as described on the
relevant reference page ([Drawing](drawing.md),
[Layouts, gauges, pages & animations](layouts-gauges-pages-animations.md)) until that's been
verified.
