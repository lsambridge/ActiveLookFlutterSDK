import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../activelook_sdk_platform_interface.dart';
import 'activelook_types.dart';

/// [ActivelookSdkPlatform] implementation backed by a [MethodChannel] for
/// request/response calls and [EventChannel]s for the native SDKs' ongoing
/// callback-based notifications (scan results, connection state, battery,
/// flow control, sensor tap).
///
/// Both native SDKs are callback-based, not coroutine/async-await based, and
/// per this repo's plan doc §7.3/§13.3, neither guarantees callbacks land on
/// a Flutter-plugin-safe thread — Android's GATT callbacks arrive on a
/// Binder thread, iOS's CoreBluetooth callbacks on the main queue. Each
/// native implementation is responsible for marshalling to the platform
/// thread before invoking the channel; this class only needs the standard
/// Flutter guarantee that channel messages land on the platform thread.
class MethodChannelActivelookSdk extends ActivelookSdkPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('activelook_sdk');

  final EventChannel _scanChannel = const EventChannel('activelook_sdk/scan');
  final EventChannel _connectionStateChannel = const EventChannel('activelook_sdk/connection_state');
  final EventChannel _batteryChannel = const EventChannel('activelook_sdk/battery');
  final EventChannel _flowControlChannel = const EventChannel('activelook_sdk/flow_control');
  final EventChannel _sensorTapChannel = const EventChannel('activelook_sdk/sensor_tap');

  Stream<ActiveLookDiscoveredGlasses>? _scanStream;
  Stream<ActiveLookConnectionState>? _connectionStateStream;
  Stream<int>? _batteryStream;
  Stream<ActiveLookFlowControlStatus>? _flowControlStream;
  Stream<void>? _sensorTapStream;

  @override
  Stream<ActiveLookDiscoveredGlasses> startScan() {
    final controller = StreamController<ActiveLookDiscoveredGlasses>.broadcast();
    final events = _scanStream ??= _scanChannel.receiveBroadcastStream().map(
          (event) => ActiveLookDiscoveredGlasses.fromMap(event as Map<Object?, Object?>),
        );
    final eventsSub = events.listen(controller.add, onError: controller.addError);

    // The native 'startScan' call can throw synchronously into its Future
    // (e.g. a null Bluetooth adapter) - if left unawaited, that rejection
    // has no listener and becomes an unhandled async error that crashes the
    // app regardless of any try/catch around this call. Forward it into the
    // stream instead, the same path callers already listen to via onError.
    methodChannel.invokeMethod<void>('startScan').catchError((Object e) {
      controller.addError(e);
    });

    controller.onCancel = eventsSub.cancel;
    return controller.stream;
  }

  @override
  Future<void> stopScan() => methodChannel.invokeMethod<void>('stopScan');

  @override
  Future<void> connect(String id) => methodChannel.invokeMethod<void>('connect', {'id': id});

  @override
  Future<void> disconnect() => methodChannel.invokeMethod<void>('disconnect');

  @override
  Stream<ActiveLookConnectionState> get connectionState {
    return _connectionStateStream ??= _connectionStateChannel.receiveBroadcastStream().map((event) {
      switch (event as String) {
        case 'connecting':
          return ActiveLookConnectionState.connecting;
        case 'connected':
          return ActiveLookConnectionState.connected;
        default:
          return ActiveLookConnectionState.disconnected;
      }
    });
  }

  @override
  Future<ActiveLookDeviceInformation> getDeviceInformation() async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>('getDeviceInformation');
    return ActiveLookDeviceInformation.fromMap(result ?? const {});
  }

  @override
  Future<int> getBatteryLevel() async {
    final result = await methodChannel.invokeMethod<int>('getBatteryLevel');
    return result ?? -1;
  }

  @override
  Stream<int> get batteryLevelNotifications {
    return _batteryStream ??= _batteryChannel.receiveBroadcastStream().map((event) => event as int);
  }

  @override
  Stream<ActiveLookFlowControlStatus> get flowControlNotifications {
    return _flowControlStream ??= _flowControlChannel.receiveBroadcastStream().map((event) {
      switch (event as String) {
        case 'bufferFull':
          return ActiveLookFlowControlStatus.bufferFull;
        case 'cmdError':
          return ActiveLookFlowControlStatus.cmdError;
        case 'overflow':
          return ActiveLookFlowControlStatus.overflow;
        case 'missingConfigId':
          return ActiveLookFlowControlStatus.missingConfigId;
        case 'bufferOk':
          return ActiveLookFlowControlStatus.bufferOk;
        default:
          return ActiveLookFlowControlStatus.reserved;
      }
    });
  }

  @override
  Stream<void> get sensorTapNotifications {
    return _sensorTapStream ??= _sensorTapChannel.receiveBroadcastStream().map((_) {});
  }

  @override
  Future<void> power(bool on) => methodChannel.invokeMethod<void>('power', {'on': on});

  @override
  Future<void> clear() => methodChannel.invokeMethod<void>('clear');

  @override
  Future<void> grey(int level) => methodChannel.invokeMethod<void>('grey', {'level': level});

  @override
  Future<void> led(ActiveLookLedState state) =>
      methodChannel.invokeMethod<void>('led', {'state': state.name});

  @override
  Future<void> luma(int level) => methodChannel.invokeMethod<void>('luma', {'level': level});

  @override
  Future<void> sensor(bool enable) => methodChannel.invokeMethod<void>('sensor', {'enable': enable});

  @override
  Future<void> gesture(bool enable) => methodChannel.invokeMethod<void>('gesture', {'enable': enable});

  @override
  Future<void> als(bool enable) => methodChannel.invokeMethod<void>('als', {'enable': enable});

  @override
  Future<void> shift(int x, int y) => methodChannel.invokeMethod<void>('shift', {'x': x, 'y': y});

  @override
  Future<ActiveLookGlassesSettings> settings() async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>('settings');
    return ActiveLookGlassesSettings.fromMap(result ?? const {});
  }

  @override
  Future<void> holdFlush(ActiveLookHoldFlushAction action) =>
      methodChannel.invokeMethod<void>('holdFlush', {'action': action.name});

  @override
  Future<void> color(int level) => methodChannel.invokeMethod<void>('color', {'level': level});

  @override
  Future<void> point(int x, int y) => methodChannel.invokeMethod<void>('point', {'x': x, 'y': y});

  @override
  Future<void> line(int x1, int y1, int x2, int y2) =>
      methodChannel.invokeMethod<void>('line', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2});

  @override
  Future<void> rect(int x1, int y1, int x2, int y2) =>
      methodChannel.invokeMethod<void>('rect', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2});

  @override
  Future<void> rectFilled(int x1, int y1, int x2, int y2) =>
      methodChannel.invokeMethod<void>('rectFilled', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2});

  @override
  Future<void> circle(int x, int y, int radius) =>
      methodChannel.invokeMethod<void>('circle', {'x': x, 'y': y, 'radius': radius});

  @override
  Future<void> circleFilled(int x, int y, int radius) =>
      methodChannel.invokeMethod<void>('circleFilled', {'x': x, 'y': y, 'radius': radius});

  @override
  Future<void> text(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int color,
    String text,
  ) {
    return methodChannel.invokeMethod<void>('text', {
      'x': x,
      'y': y,
      'rotation': rotation.name,
      'fontSize': fontSize,
      'color': color,
      'text': text,
    });
  }

  @override
  Future<void> polyline(List<int> xyPairs, {int thickness = 1}) => methodChannel.invokeMethod<void>(
        'polyline',
        {'xyPairs': xyPairs, 'thickness': thickness},
      );

  @override
  Future<void> layoutSave(ActiveLookLayoutParameters layout) =>
      methodChannel.invokeMethod<void>('layoutSave', layout.toMap());

  @override
  Future<void> layoutSaveInColor(ActiveLookLayoutParameters layout) =>
      methodChannel.invokeMethod<void>('layoutSaveInColor', layout.toMap());

  @override
  Future<void> rawColor(int value) => methodChannel.invokeMethod<void>('rawColor', {'value': value});

  @override
  Future<void> rawTextColor(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int colorValue,
    String text,
  ) {
    return methodChannel.invokeMethod<void>('rawTextColor', {
      'x': x,
      'y': y,
      'rotation': rotation.name,
      'fontSize': fontSize,
      'colorValue': colorValue,
      'text': text,
    });
  }

  @override
  Future<void> sendRawFrames(List<List<int>> frames) =>
      methodChannel.invokeMethod<void>('sendRawFrames', {'frames': frames});

  @override
  Future<void> layoutDisplay(int id, String text) =>
      methodChannel.invokeMethod<void>('layoutDisplay', {'id': id, 'text': text});

  @override
  Future<void> layoutDisplayExtended(int id, int x, int y, String text) => methodChannel.invokeMethod<void>(
        'layoutDisplayExtended',
        {'id': id, 'x': x, 'y': y, 'text': text},
      );

  @override
  Future<void> layoutClear(int id) => methodChannel.invokeMethod<void>('layoutClear', {'id': id});

  @override
  Future<void> layoutClearAndDisplay(int id, String text) =>
      methodChannel.invokeMethod<void>('layoutClearAndDisplay', {'id': id, 'text': text});

  @override
  Future<void> layoutDelete(int id) => methodChannel.invokeMethod<void>('layoutDelete', {'id': id});

  @override
  Future<List<int>> layoutList() async {
    final result = await methodChannel.invokeMethod<List<Object?>>('layoutList');
    return (result ?? const []).cast<int>();
  }

  @override
  Future<ActiveLookLayoutParameters> layoutGet(int id) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>('layoutGet', {'id': id});
    return ActiveLookLayoutParameters.fromMap(id, result ?? const {});
  }

  @override
  Future<void> gaugeSave(ActiveLookGaugeInfo gauge) =>
      methodChannel.invokeMethod<void>('gaugeSave', gauge.toMap());

  @override
  Future<void> gaugeDisplay(int id, int valuePercent) =>
      methodChannel.invokeMethod<void>('gaugeDisplay', {'id': id, 'value': valuePercent});

  @override
  Future<void> gaugeDelete(int id) => methodChannel.invokeMethod<void>('gaugeDelete', {'id': id});

  @override
  Future<void> pageSave(int id, List<int> layoutIds, List<int> xs, List<int> ys) =>
      methodChannel.invokeMethod<void>('pageSave', {
        'id': id,
        'layoutIds': layoutIds,
        'xs': xs,
        'ys': ys,
      });

  @override
  Future<void> pageDisplay(int id, List<String> texts) =>
      methodChannel.invokeMethod<void>('pageDisplay', {'id': id, 'texts': texts});

  @override
  Future<void> pageClear(int id) => methodChannel.invokeMethod<void>('pageClear', {'id': id});

  @override
  Future<void> pageDelete(int id) => methodChannel.invokeMethod<void>('pageDelete', {'id': id});

  @override
  Future<void> animDisplay(
    int handlerId,
    int animId,
    int frameDelayMs,
    int repeatCount,
    int x,
    int y,
  ) {
    return methodChannel.invokeMethod<void>('animDisplay', {
      'handlerId': handlerId,
      'animId': animId,
      'frameDelayMs': frameDelayMs,
      'repeatCount': repeatCount,
      'x': x,
      'y': y,
    });
  }

  @override
  Future<void> animClear(int handlerId) =>
      methodChannel.invokeMethod<void>('animClear', {'handlerId': handlerId});

  @override
  Future<void> configSet(String name) => methodChannel.invokeMethod<void>('configSet', {'name': name});

  /// Runs [invoke], translating the native `UNSUPPORTED_ON_PLATFORM`
  /// `PlatformException` error code (thrown by native code for a method
  /// ActiveLook's own SDK doesn't expose on that platform — see
  /// [ActiveLookUnsupportedOnPlatformException]) into the typed exception.
  Future<T> _unsupportedAware<T>(String method, Future<T> Function() invoke) async {
    try {
      return await invoke();
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED_ON_PLATFORM') {
        throw ActiveLookUnsupportedOnPlatformException(method, e.message ?? 'this platform');
      }
      rethrow;
    }
  }

  // --- Image/bitmap commands ---

  @override
  Future<List<ActiveLookImageInfo>> imgList() async {
    final result = await methodChannel.invokeMethod<List<Object?>>('imgList');
    return (result ?? const [])
        .map((e) => ActiveLookImageInfo.fromMap(e as Map<Object?, Object?>))
        .toList();
  }

  @override
  Future<void> imgSave(int id, List<int> pngBytes, ActiveLookImageFormat format) =>
      methodChannel.invokeMethod<void>('imgSave', {
        'id': id,
        'pngBytes': pngBytes,
        'format': format.name,
      });

  @override
  Future<void> imgDisplay(int id, int x, int y) =>
      methodChannel.invokeMethod<void>('imgDisplay', {'id': id, 'x': x, 'y': y});

  @override
  Future<void> imgDelete(int id) => methodChannel.invokeMethod<void>('imgDelete', {'id': id});

  @override
  Future<void> imgDeleteAll() => methodChannel.invokeMethod<void>('imgDeleteAll');

  @override
  Future<void> imgStream(List<int> pngBytes, ActiveLookImageStreamFormat format, int x, int y) =>
      methodChannel.invokeMethod<void>('imgStream', {
        'pngBytes': pngBytes,
        'format': format.name,
        'x': x,
        'y': y,
      });

  // --- Font commands ---

  @override
  Future<List<ActiveLookFontInfo>> fontList() async {
    final result = await methodChannel.invokeMethod<List<Object?>>('fontList');
    return (result ?? const []).map((e) => ActiveLookFontInfo.fromMap(e as Map<Object?, Object?>)).toList();
  }

  @override
  Future<void> fontSave(int id, List<int> fontBytes) =>
      methodChannel.invokeMethod<void>('fontSave', {'id': id, 'fontBytes': fontBytes});

  @override
  Future<void> fontSelect(int id) => methodChannel.invokeMethod<void>('fontSelect', {'id': id});

  @override
  Future<void> fontDelete(int id) => methodChannel.invokeMethod<void>('fontDelete', {'id': id});

  @override
  Future<void> fontDeleteAll() => methodChannel.invokeMethod<void>('fontDeleteAll');

  // --- Firmware configuration management ---

  @override
  Future<void> cfgWrite(String name, int version, int password) =>
      methodChannel.invokeMethod<void>('cfgWrite', {
        'name': name,
        'version': version,
        'password': password,
      });

  @override
  Future<ActiveLookConfigurationElementsInfo> cfgRead(String name) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>('cfgRead', {'name': name});
    return ActiveLookConfigurationElementsInfo.fromMap(result ?? const {});
  }

  @override
  Future<List<ActiveLookConfigurationDescription>> cfgList() async {
    final result = await methodChannel.invokeMethod<List<Object?>>('cfgList');
    return (result ?? const [])
        .map((e) => ActiveLookConfigurationDescription.fromMap(e as Map<Object?, Object?>))
        .toList();
  }

  @override
  Future<void> cfgRename(String oldName, String newName, int password) =>
      methodChannel.invokeMethod<void>('cfgRename', {
        'oldName': oldName,
        'newName': newName,
        'password': password,
      });

  @override
  Future<void> cfgDelete(String name) => methodChannel.invokeMethod<void>('cfgDelete', {'name': name});

  @override
  Future<void> cfgDeleteLessUsed() => methodChannel.invokeMethod<void>('cfgDeleteLessUsed');

  @override
  Future<ActiveLookFreeSpace> cfgFreeSpace() async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>('cfgFreeSpace');
    return ActiveLookFreeSpace.fromMap(result ?? const {});
  }

  @override
  Future<int> cfgGetNb() async => (await methodChannel.invokeMethod<int>('cfgGetNb')) ?? 0;

  @override
  Future<void> shutdown() => methodChannel.invokeMethod<void>('shutdown');

  // --- Legacy firmware 1.7-only configuration commands ---

  @override
  Future<void> legacyWriteConfig(ActiveLookLegacyConfiguration config) =>
      methodChannel.invokeMethod<void>('legacyWriteConfig', config.toMap());

  @override
  Future<ActiveLookLegacyConfiguration> legacyReadConfig(int number) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'legacyReadConfig',
      {'number': number},
    );
    return ActiveLookLegacyConfiguration.fromMap(result ?? const {});
  }

  @override
  Future<void> legacySetConfig(int number) =>
      methodChannel.invokeMethod<void>('legacySetConfig', {'number': number});

  @override
  Future<void> tdbg() => _unsupportedAware('tdbg', () => methodChannel.invokeMethod<void>('tdbg'));

  // --- Statistics commands ---

  @override
  Future<int> pixelCount() async => (await methodChannel.invokeMethod<int>('pixelCount')) ?? 0;

  @override
  Future<int> getChargingCounter() async =>
      (await methodChannel.invokeMethod<int>('getChargingCounter')) ?? 0;

  @override
  Future<int> getChargingTime() async => (await methodChannel.invokeMethod<int>('getChargingTime')) ?? 0;

  @override
  Future<void> resetChargingParam() => methodChannel.invokeMethod<void>('resetChargingParam');

  // --- Widget commands (iOS-only) ---

  @override
  Future<void> widgetOpenGauge({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int value,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
  }) =>
      _unsupportedAware(
        'widgetOpenGauge',
        () => methodChannel.invokeMethod<void>('widgetOpenGauge', {
          'size': size.name,
          'x': x,
          'y': y,
          'value': value,
          'imageId': imageId,
          'valueType': valueType.name,
          'unit': unit,
          'shownValue': shownValue,
        }),
      );

  @override
  Future<void> widgetRangeGauge({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int value,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
    required String min,
    required String max,
  }) =>
      _unsupportedAware(
        'widgetRangeGauge',
        () => methodChannel.invokeMethod<void>('widgetRangeGauge', {
          'size': size.name,
          'x': x,
          'y': y,
          'value': value,
          'imageId': imageId,
          'valueType': valueType.name,
          'unit': unit,
          'shownValue': shownValue,
          'min': min,
          'max': max,
        }),
      );

  @override
  Future<void> widgetGaugeZone({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int value,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
    required int chosenZone,
    required int zoneCount,
  }) =>
      _unsupportedAware(
        'widgetGaugeZone',
        () => methodChannel.invokeMethod<void>('widgetGaugeZone', {
          'size': size.name,
          'x': x,
          'y': y,
          'value': value,
          'imageId': imageId,
          'valueType': valueType.name,
          'unit': unit,
          'shownValue': shownValue,
          'chosenZone': chosenZone,
          'zoneCount': zoneCount,
        }),
      );

  @override
  Future<void> widgetTarget({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int value,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
    required String goal,
  }) =>
      _unsupportedAware(
        'widgetTarget',
        () => methodChannel.invokeMethod<void>('widgetTarget', {
          'size': size.name,
          'x': x,
          'y': y,
          'value': value,
          'imageId': imageId,
          'valueType': valueType.name,
          'unit': unit,
          'shownValue': shownValue,
          'goal': goal,
        }),
      );

  @override
  Future<void> widgetTargetLeft({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int value,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
    required String goal,
  }) =>
      _unsupportedAware(
        'widgetTargetLeft',
        () => methodChannel.invokeMethod<void>('widgetTargetLeft', {
          'size': size.name,
          'x': x,
          'y': y,
          'value': value,
          'imageId': imageId,
          'valueType': valueType.name,
          'unit': unit,
          'shownValue': shownValue,
          'goal': goal,
        }),
      );

  @override
  Future<void> widgetBarChart({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
    required int chosenZone,
    required int zoneCount,
    required List<int> zoneValues,
  }) =>
      _unsupportedAware(
        'widgetBarChart',
        () => methodChannel.invokeMethod<void>('widgetBarChart', {
          'size': size.name,
          'x': x,
          'y': y,
          'imageId': imageId,
          'valueType': valueType.name,
          'unit': unit,
          'shownValue': shownValue,
          'chosenZone': chosenZone,
          'zoneCount': zoneCount,
          'zoneValues': zoneValues,
        }),
      );

  @override
  Future<void> widgetData({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
  }) =>
      _unsupportedAware(
        'widgetData',
        () => methodChannel.invokeMethod<void>('widgetData', {
          'size': size.name,
          'x': x,
          'y': y,
          'imageId': imageId,
          'valueType': valueType.name,
          'unit': unit,
          'shownValue': shownValue,
        }),
      );
}
