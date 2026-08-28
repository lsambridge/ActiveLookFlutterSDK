# Full session example

[← Back to docs index](README.md)

A complete, copy-pasteable walkthrough — scan through disconnect — showing how the pieces from the
other reference pages fit together in one real screen (a simple "workout stats" HUD: heart rate as
a layout, effort as a gauge, a low-battery warning). Each step links back to the page that covers
it in depth; this page's job is showing the *shape* of a real integration, not re-explaining any
one command.

```dart
import 'dart:async';

import 'package:activelook_sdk/activelook_sdk.dart';

class GlassesHudController {
  final _sdk = ActivelookSdk();

  StreamSubscription<ActiveLookDiscoveredGlasses>? _scanSub;
  StreamSubscription<ActiveLookConnectionState>? _connectionSub;
  StreamSubscription<int>? _batterySub;
  StreamSubscription<ActiveLookFlowControlStatus>? _flowControlSub;

  bool _bufferPaused = false; // iOS only — see the flow-control note below

  // --- 1. Scan & connect ---
  // See: getting-started.md, connection-and-events.md

  Future<void> connectToFirstGlassesFound() async {
    final completer = Completer<void>();

    _scanSub = _sdk.startScan().listen((glasses) async {
      await _scanSub?.cancel();
      await _sdk.stopScan();

      try {
        await _sdk.connect(glasses.id);
        completer.complete();
      } on ActiveLookConnectionException catch (e) {
        completer.completeError(e);
      }
    });

    _connectionSub = _sdk.connectionState.listen(_onConnectionStateChanged);
    _batterySub = _sdk.batteryLevelNotifications.listen(_onBatteryUpdate);

    // See connection-and-events.md#flow-control — this only fires reliably on iOS today.
    _flowControlSub = _sdk.flowControlNotifications.listen((status) {
      _bufferPaused = status == ActiveLookFlowControlStatus.bufferFull;
    });

    return completer.future;
  }

  void _onConnectionStateChanged(ActiveLookConnectionState state) {
    if (state == ActiveLookConnectionState.connected) {
      _setUpScreen();
    }
  }

  void _onBatteryUpdate(int percent) {
    if (percent <= 10) _showLowBatteryWarning();
  }

  // --- 2. One-time screen setup after connecting ---
  // See: firmware-configuration.md#configset, layouts-gauges-pages-animations.md

  Future<void> _setUpScreen() async {
    // Activate ActiveLook's default pre-flashed configuration first (§4 of the main plan doc) —
    // gives you a known baseline of fonts/icons/layout IDs to build on or reference directly.
    await _sdk.configSet('ALooK');

    // Batch the initial layout composition into one flicker-free update.
    // See drawing.md#general-device-commands for holdFlush.
    await _sdk.holdFlush(ActiveLookHoldFlushAction.hold);

    await _sdk.layoutSave(const ActiveLookLayoutParameters(
      id: 1,
      x: 10, y: 10, width: 120, height: 30,
      font: 0, foregroundColor: 15, backgroundColor: 0,
      textValid: true, textX: 5, textY: 5,
    ));

    await _sdk.gaugeSave(const ActiveLookGaugeInfo(
      id: 1,
      x: 220, y: 128,
      externalRadius: 60, internalRadius: 48,
      startAngle: 1, endAngle: 16,
    ));

    await _sdk.holdFlush(ActiveLookHoldFlushAction.flush);
  }

  // --- 3. Live updates during a session ---
  // See: drawing.md, layouts-gauges-pages-animations.md

  Future<void> updateHeartRate(int bpm) async {
    if (_bufferPaused) return; // see the flow-control caveat below
    await _sdk.layoutDisplay(1, '$bpm bpm');
  }

  Future<void> updateEffort(int percent) async {
    if (_bufferPaused) return;
    await _sdk.gaugeDisplay(1, percent.clamp(0, 100));
  }

  // --- 4. Ad-hoc feedback ---
  // See: layouts-gauges-pages-animations.md#animations

  Future<void> _showLowBatteryWarning() {
    // Assumes the ALooK config's built-in low-battery animation ID — see
    // Activelook-Visual-Assets for the real ID reference before using this in production.
    return _sdk.animDisplay(1, 5, 200, 3, 0, 0);
  }

  // --- 5. Teardown ---

  Future<void> dispose() async {
    await _scanSub?.cancel();
    await _connectionSub?.cancel();
    await _batterySub?.cancel();
    await _flowControlSub?.cancel();
    await _sdk.disconnect();
  }
}
```

## Notes on this example

- **Error handling is deliberately minimal here** — see [Error handling](error-handling.md) for
  the real `PlatformException` codes (`NOT_CONNECTED`, `NOT_FOUND`, etc.) a production integration
  should catch around every call in steps 2–4, not just the `connect()` call shown in step 1.
- **The `_bufferPaused` guard is iOS-only in practice today.** Android's SDK never reports
  `bufferFull` to this package (see [Connection & device events § Flow
  control](connection-and-events.md#flow-control)), so this guard is a no-op on Android — it's
  included here to show the *pattern* you'd want once/if Android closes that gap, not because it
  does anything useful there right now. For real Android backpressure protection today, rate-limit
  your own update frequency instead (e.g. don't call `updateHeartRate`/`updateEffort` more than
  once or twice a second).
- **This assumes one screen for the whole session.** A real HUD with multiple screens (e.g. a
  "live race" view and a "post-workout summary" view) would likely use
  [pages](layouts-gauges-pages-animations.md#pages) to group multiple layouts, and call
  `pageDisplay` instead of individual `layoutDisplay` calls per screen.
- **Nothing here has been run against real hardware** — see [Known
  issues](known-issues.md#verification-depth-by-platform) for the current verification state of
  this package as a whole.
