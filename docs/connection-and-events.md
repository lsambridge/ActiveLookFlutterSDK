# Connection & device events

[← Back to docs index](README.md)

## Scanning

```dart
Stream<ActiveLookDiscoveredGlasses> startScan()
Future<void> stopScan()
```

`startScan()` returns a broadcast stream of every glasses device discovered — it does not
deduplicate for you (though both native SDKs generally do not re-report the same device twice in
one scan session). Scanning keeps running until you call `stopScan()`; there is no timeout built
in, so if your UI needs one, implement it at the call site (e.g.
`sdk.startScan().timeout(...)` or a manual `Timer` calling `stopScan()`).

`ActiveLookDiscoveredGlasses` has three fields: `id`, `name`, `manufacturer`. `id` is the value you
pass to `connect()` — see the note on its platform-specific shape in
[Getting started](getting-started.md#2-scan-for-glasses).

## Connecting

```dart
Future<void> connect(String id)
Future<void> disconnect()
Stream<ActiveLookConnectionState> connectionState
```

`ActiveLookConnectionState` is `disconnected | connecting | connected`. Both intentional
disconnects (`disconnect()`) and unsolicited ones (glasses power off, go out of range) surface
through the same `connectionState` stream, so one listener is enough for the whole connection
lifecycle. On failure, the returned `Future` from `connect()` completes with an
`ActiveLookConnectionException` — see [Error handling](error-handling.md).

This package supports **one connected pair of glasses at a time**. Calling `connect()` while
already connected to a different device disconnects the first (this mirrors how the underlying
native SDKs track a single active `Glasses` instance internally).

## Device info & one-shot battery query

```dart
Future<ActiveLookDeviceInformation> getDeviceInformation()
Future<int> getBatteryLevel()
```

`getDeviceInformation()` returns manufacturer/model/serial/hardware/firmware/software version
strings as published over standard BLE Device Information Service characteristics — any field may
be `null` if the glasses don't populate it.

`getBatteryLevel()` is a one-shot query (the `battery` command) — distinct from the ongoing
`batteryLevelNotifications` stream below.

## Device event streams

```dart
Stream<int> batteryLevelNotifications
Stream<ActiveLookFlowControlStatus> flowControlNotifications
Stream<void> sensorTapNotifications
```

### Battery notifications

The glasses push a battery-level update roughly every 30 seconds while connected. Subscribe once
per connection; there's no need to poll `getBatteryLevel()` if you're already listening here.

### Sensor tap

Fires on a double-tap of the glasses' capacitive touch button. This is a `Stream<void>` — no
payload. **This is the only sensor event ActiveLook's API exposes today.** The glasses do have a
true 9-DoF IMU (accelerometer/gyroscope/magnetometer) on-device, but it is not exposed via either
native SDK's public API as of this writing — don't design a heading/orientation feature around
glasses-side sensor data; use your own phone-side sensors instead.

### Flow control {#flow-control}

```dart
enum ActiveLookFlowControlStatus { bufferFull, bufferOk, cmdError, overflow, missingConfigId, reserved }
```

This is the device's backpressure signal for its own command buffer — a real, finite BLE receive
queue on the glasses. **You are expected to pause sending draw commands when the buffer reports
full.** This package does not queue, throttle, or drop commands on your behalf; if you send faster
than the glasses can drain the buffer, that's on your call site to manage.

**⚠️ Confirmed platform divergence — read this before writing backpressure logic:**

Reading both native SDKs' source directly shows they do not behave the same way here:

- **iOS** forwards every flow-control state to your listener, including `bufferOk`/`bufferFull`.
  You can build real backpressure handling against this stream on iOS today.
- **Android's SDK handles `bufferOk`/`bufferFull` purely internally**, to gate its own internal
  send queue — it **never forwards these two states** to the public callback this package
  subscribes to. Only the four error states (`cmdError`, `overflow`, `missingConfigId`, `reserved`)
  ever reach `flowControlNotifications` on Android.

**Practical consequence**: code like `if (status == ActiveLookFlowControlStatus.bufferFull) { pause(); }`
will simply never fire on Android. If you need real backpressure handling cross-platform today,
either:

1. Gate sends on a client-side rate limit tuned to real-hardware testing (see the "before any build
   commitment" hardware test in the main plan doc), rather than relying on this signal on Android, or
2. Treat Android's flow control as error-detection only (a `cmdError`/`overflow` means you sent too
   fast and should back off), not as a pre-emptive "stop before you overflow" signal.

This is a real gap in ActiveLook's own Android SDK, not a limitation of this Flutter bridge — see
[Known issues](known-issues.md) for the full list of confirmed upstream SDK bugs/divergences.
