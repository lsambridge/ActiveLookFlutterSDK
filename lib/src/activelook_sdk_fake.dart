import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../activelook_sdk_platform_interface.dart';
import 'activelook_types.dart';

/// A pure-Dart [ActivelookSdkPlatform] with no native/BLE dependency, for
/// local development against the HTML/Canvas "sandbox glasses" viewer
/// (`tool/glasses_simulator/viewer.html`) instead of physical hardware.
///
/// Every draw/state call is serialized as `{"cmd": "...", ...args}` and sent
/// over a WebSocket to that viewer, which renders the raw 304x256 device
/// buffer live. This intentionally sits at the same seam the method-channel
/// implementation does ([ActivelookSdkPlatform]), so app code (including
/// [ActiveLookSafeCanvas]'s safe-area/flip math) is exercised unchanged -
/// only the transport underneath is swapped. It does not emulate BLE, the
/// binary wire protocol, flow control, or MTU chunking - none of that is
/// reachable from Dart anyway (it lives in the native Android/iOS SDKs).
///
/// Enable with:
/// ```dart
/// if (kDebugMode && useFakeGlasses) {
///   ActivelookSdkPlatform.instance = FakeActivelookSdk();
/// }
/// ```
///
/// The viewer must already be open and listening before [connect] is called
/// - this class does not launch a browser itself. Point it at the viewer's
/// WebSocket port with [uri] (defaults to `ws://localhost:8787`); on an
/// Android emulator use `ws://10.0.2.2:8787` instead, since `localhost`
/// there resolves to the emulator itself, not the host machine.
class FakeActivelookSdk extends ActivelookSdkPlatform {
  FakeActivelookSdk({Uri? uri}) : _uri = uri ?? Uri.parse('ws://localhost:8787');

  final Uri _uri;
  WebSocketChannel? _channel;

  final _connectionStateController = StreamController<ActiveLookConnectionState>.broadcast();
  final _batteryController = StreamController<int>.broadcast();
  final _flowControlController = StreamController<ActiveLookFlowControlStatus>.broadcast();
  final _sensorTapController = StreamController<void>.broadcast();

  final int _fakeBattery = 87;

  void _send(String cmd, Map<String, Object?> args) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({'cmd': cmd, ...args}));
  }

  // --- Scanning & connection ---

  @override
  Stream<ActiveLookDiscoveredGlasses> startScan() {
    final controller = StreamController<ActiveLookDiscoveredGlasses>();
    Timer(const Duration(milliseconds: 300), () {
      if (controller.isClosed) return;
      controller.add(
        const ActiveLookDiscoveredGlasses(
          id: 'fake-glasses-1',
          name: 'A.LooK  SIM001',
          manufacturer: 'Microoled',
        ),
      );
    });
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String id) async {
    _connectionStateController.add(ActiveLookConnectionState.connecting);
    _channel = WebSocketChannel.connect(_uri);
    await _channel!.ready;
    // The viewer's "Double tap" button sends a `{"event": "sensorTap"}`
    // message back down this same socket - the only inbound message this
    // class currently expects. See viewer.html's tap button and
    // server.dart's relay (it forwards every viewer message to the app
    // unchanged, same as it does app-to-viewer).
    _channel!.stream.listen((message) {
      try {
        final decoded = jsonDecode(message as String);
        if (decoded is Map && decoded['event'] == 'sensorTap') {
          _sensorTapController.add(null);
        }
      } catch (_) {
        // Ignore anything that isn't the expected JSON event message.
      }
    });
    _connectionStateController.add(ActiveLookConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _connectionStateController.add(ActiveLookConnectionState.disconnected);
  }

  @override
  Stream<ActiveLookConnectionState> get connectionState => _connectionStateController.stream;

  @override
  Future<ActiveLookDeviceInformation> getDeviceInformation() async => const ActiveLookDeviceInformation(
        manufacturerName: 'Microoled',
        modelNumber: 'A.LooK',
        serialNumber: 'SIM0001',
        hardwareVersion: 'ALK03-MDP08ACRG',
        firmwareVersion: 'v4.11.2b-sim',
        softwareVersion: '1.0.0.1',
      );

  @override
  Future<int> getBatteryLevel() async => _fakeBattery;

  // --- Device event streams ---

  @override
  Stream<int> get batteryLevelNotifications => _batteryController.stream;

  @override
  Stream<ActiveLookFlowControlStatus> get flowControlNotifications => _flowControlController.stream;

  @override
  Stream<void> get sensorTapNotifications => _sensorTapController.stream;

  /// Not part of [ActivelookSdkPlatform] - lets a dev-tools debug panel
  /// simulate the glasses' capacitive-button double-tap without real
  /// hardware, e.g. to exercise [RaceModeGlassesHud]'s screen-toggle path.
  void simulateSensorTap() => _sensorTapController.add(null);

  // --- General device commands ---

  @override
  Future<void> power(bool on) async => _send('power', {'on': on});

  @override
  Future<void> clear() async => _send('clear', {});

  @override
  Future<void> grey(int level) async => _send('grey', {'level': level});

  @override
  Future<void> led(ActiveLookLedState state) async => _send('led', {'state': state.name});

  @override
  Future<void> luma(int level) async => _send('luma', {'level': level});

  @override
  Future<void> sensor(bool enable) async => _send('sensor', {'enable': enable});

  @override
  Future<void> gesture(bool enable) async => _send('gesture', {'enable': enable});

  @override
  Future<void> als(bool enable) async => _send('als', {'enable': enable});

  @override
  Future<void> shift(int x, int y) async => _send('shift', {'x': x, 'y': y});

  @override
  Future<ActiveLookGlassesSettings> settings() async => const ActiveLookGlassesSettings(
        xShift: 0,
        yShift: 0,
        luma: 15,
        alsEnabled: false,
        gestureEnabled: false,
      );

  @override
  Future<void> holdFlush(ActiveLookHoldFlushAction action) async =>
      _send('holdFlush', {'action': action.name});

  // --- Vector drawing ---

  @override
  Future<void> color(int level) async => _send('color', {'level': level});

  @override
  Future<void> point(int x, int y) async => _send('point', {'x': x, 'y': y});

  @override
  Future<void> line(int x1, int y1, int x2, int y2) async =>
      _send('line', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2});

  @override
  Future<void> rect(int x1, int y1, int x2, int y2) async =>
      _send('rect', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2});

  @override
  Future<void> rectFilled(int x1, int y1, int x2, int y2) async =>
      _send('rectFilled', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2});

  @override
  Future<void> circle(int x, int y, int radius) async => _send('circle', {'x': x, 'y': y, 'radius': radius});

  @override
  Future<void> circleFilled(int x, int y, int radius) async =>
      _send('circleFilled', {'x': x, 'y': y, 'radius': radius});

  @override
  Future<void> text(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int color,
    String text,
  ) async =>
      _send('text', {
        'x': x,
        'y': y,
        'rotation': rotation.name,
        'fontSize': fontSize,
        'color': color,
        'text': text,
      });

  @override
  Future<void> polyline(List<int> xyPairs, {int thickness = 1}) async =>
      _send('polyline', {'xyPairs': xyPairs, 'thickness': thickness});

  // --- Layouts ---

  @override
  Future<void> layoutSave(ActiveLookLayoutParameters layout) async =>
      _send('layoutSave', layout.toMap());

  @override
  Future<void> layoutSaveInColor(ActiveLookLayoutParameters layout) async =>
      _send('layoutSaveInColor', layout.toMap());

  @override
  Future<void> rawColor(int value) async => _send('rawColor', {'value': value});

  @override
  Future<void> rawTextColor(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int colorValue,
    String text,
  ) async =>
      _send('rawTextColor', {
        'x': x,
        'y': y,
        'rotation': rotation.name,
        'fontSize': fontSize,
        'colorValue': colorValue,
        'text': text,
      });

  @override
  Future<void> sendRawFrames(List<List<int>> frames) async {
    // Pre-encoded binary command frames (animSave) - not meaningfully
    // replayable by a JSON-command viewer, so this is a no-op here.
  }

  @override
  Future<void> layoutDisplay(int id, String text) async => _send('layoutDisplay', {'id': id, 'text': text});

  @override
  Future<void> layoutDisplayExtended(int id, int x, int y, String text) async =>
      _send('layoutDisplayExtended', {'id': id, 'x': x, 'y': y, 'text': text});

  @override
  Future<void> layoutClear(int id) async => _send('layoutClear', {'id': id});

  @override
  Future<void> layoutClearAndDisplay(int id, String text) async =>
      _send('layoutClearAndDisplay', {'id': id, 'text': text});

  @override
  Future<void> layoutDelete(int id) async => _send('layoutDelete', {'id': id});

  @override
  Future<List<int>> layoutList() async => const [];

  @override
  Future<ActiveLookLayoutParameters> layoutGet(int id) async => ActiveLookLayoutParameters.fromMap(id, const {});

  // --- Gauges ---

  @override
  Future<void> gaugeSave(ActiveLookGaugeInfo gauge) async => _send('gaugeSave', gauge.toMap());

  @override
  Future<void> gaugeDisplay(int id, int valuePercent) async =>
      _send('gaugeDisplay', {'id': id, 'value': valuePercent});

  @override
  Future<void> gaugeDelete(int id) async => _send('gaugeDelete', {'id': id});

  // --- Pages ---

  @override
  Future<void> pageSave(int id, List<int> layoutIds, List<int> xs, List<int> ys) async =>
      _send('pageSave', {'id': id, 'layoutIds': layoutIds, 'xs': xs, 'ys': ys});

  @override
  Future<void> pageDisplay(int id, List<String> texts) async =>
      _send('pageDisplay', {'id': id, 'texts': texts});

  @override
  Future<void> pageClear(int id) async => _send('pageClear', {'id': id});

  @override
  Future<void> pageDelete(int id) async => _send('pageDelete', {'id': id});

  // --- Animations ---

  @override
  Future<void> animDisplay(
    int handlerId,
    int animId,
    int frameDelayMs,
    int repeatCount,
    int x,
    int y,
  ) async =>
      _send('animDisplay', {
        'handlerId': handlerId,
        'animId': animId,
        'frameDelayMs': frameDelayMs,
        'repeatCount': repeatCount,
        'x': x,
        'y': y,
      });

  @override
  Future<void> animClear(int handlerId) async => _send('animClear', {'handlerId': handlerId});

  // --- Pre-flashed "ALooK" configuration ---

  @override
  Future<void> configSet(String name) async => _send('configSet', {'name': name});

  // --- Image/bitmap commands ---
  //
  // pngBytes are not forwarded to the viewer (a JSON/Canvas viewer has no PNG
  // decoder wired up) - these draw a labelled placeholder box instead, so an
  // image draw call is still visible on-screen even though its real pixels
  // aren't.

  @override
  Future<List<ActiveLookImageInfo>> imgList() async => const [];

  @override
  Future<void> imgSave(int id, List<int> pngBytes, ActiveLookImageFormat format) async {}

  @override
  Future<void> imgDisplay(int id, int x, int y) async => _send('imgDisplay', {'id': id, 'x': x, 'y': y});

  @override
  Future<void> imgDelete(int id) async {}

  @override
  Future<void> imgDeleteAll() async {}

  @override
  Future<void> imgStream(List<int> pngBytes, ActiveLookImageStreamFormat format, int x, int y) async =>
      _send('imgDisplay', {'id': -1, 'x': x, 'y': y});

  // --- Font commands ---

  @override
  Future<List<ActiveLookFontInfo>> fontList() async => const [];

  @override
  Future<void> fontSave(int id, List<int> fontBytes) async {}

  @override
  Future<void> fontSelect(int id) async {}

  @override
  Future<void> fontDelete(int id) async {}

  @override
  Future<void> fontDeleteAll() async {}

  // --- Firmware configuration management ---

  @override
  Future<void> cfgWrite(String name, int version, int password) async {}

  @override
  Future<ActiveLookConfigurationElementsInfo> cfgRead(String name) async =>
      ActiveLookConfigurationElementsInfo.fromMap(const {});

  @override
  Future<List<ActiveLookConfigurationDescription>> cfgList() async => const [];

  @override
  Future<void> cfgRename(String oldName, String newName, int password) async {}

  @override
  Future<void> cfgDelete(String name) async {}

  @override
  Future<void> cfgDeleteLessUsed() async {}

  @override
  Future<ActiveLookFreeSpace> cfgFreeSpace() async => ActiveLookFreeSpace.fromMap(const {});

  @override
  Future<int> cfgGetNb() async => 0;

  @override
  Future<void> shutdown() async => disconnect();

  // --- Legacy firmware 1.7-only configuration commands ---

  @override
  Future<void> legacyWriteConfig(ActiveLookLegacyConfiguration config) async {}

  @override
  Future<ActiveLookLegacyConfiguration> legacyReadConfig(int number) async =>
      ActiveLookLegacyConfiguration.fromMap(const {});

  @override
  Future<void> legacySetConfig(int number) async {}

  @override
  Future<void> tdbg() async {}

  // --- Statistics commands ---

  @override
  Future<int> pixelCount() async => 0;

  @override
  Future<int> getChargingCounter() async => 0;

  @override
  Future<int> getChargingTime() async => 0;

  @override
  Future<void> resetChargingParam() async {}

  // --- Widget commands ---
  //
  // Left unimplemented (throw UnimplementedError via the base class) - no
  // known caller in this app uses them yet; add a _send(...) forward here if
  // that changes.
}
