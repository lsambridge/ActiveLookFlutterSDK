import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/activelook_sdk_method_channel.dart';
import 'src/activelook_types.dart';

/// The platform-agnostic contract implemented by each platform (Android,
/// iOS) that bridges to ActiveLook's native `Sdk`/`Glasses`
/// (`ActiveLookSDK`/`Glasses`) SDKs.
///
/// See `docs` in the Engyne repo,
/// `docs/plan-race-mode-activelook-glasses.md` §13, for the design this
/// mirrors: one shared Dart-facing surface, two native implementations.
abstract class ActivelookSdkPlatform extends PlatformInterface {
  ActivelookSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static ActivelookSdkPlatform _instance = MethodChannelActivelookSdk();

  static ActivelookSdkPlatform get instance => _instance;

  static set instance(ActivelookSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // --- Scanning & connection ---

  Stream<ActiveLookDiscoveredGlasses> startScan() {
    throw UnimplementedError('startScan() has not been implemented.');
  }

  Future<void> stopScan() {
    throw UnimplementedError('stopScan() has not been implemented.');
  }

  Future<void> connect(String id) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  Stream<ActiveLookConnectionState> get connectionState {
    throw UnimplementedError('connectionState has not been implemented.');
  }

  Future<ActiveLookDeviceInformation> getDeviceInformation() {
    throw UnimplementedError('getDeviceInformation() has not been implemented.');
  }

  Future<int> getBatteryLevel() {
    throw UnimplementedError('getBatteryLevel() has not been implemented.');
  }

  // --- Device event streams ---

  Stream<int> get batteryLevelNotifications {
    throw UnimplementedError('batteryLevelNotifications has not been implemented.');
  }

  Stream<ActiveLookFlowControlStatus> get flowControlNotifications {
    throw UnimplementedError('flowControlNotifications has not been implemented.');
  }

  /// The only sensor event ActiveLook's API exposes today: a double-tap on
  /// the capacitive touch button. See this repo's plan doc §10a — the
  /// on-device 9DoF IMU exists but is not API-accessible.
  Stream<void> get sensorTapNotifications {
    throw UnimplementedError('sensorTapNotifications has not been implemented.');
  }

  // --- General device commands ---

  Future<void> power(bool on) {
    throw UnimplementedError('power() has not been implemented.');
  }

  Future<void> clear() {
    throw UnimplementedError('clear() has not been implemented.');
  }

  Future<void> grey(int level) {
    throw UnimplementedError('grey() has not been implemented.');
  }

  Future<void> led(ActiveLookLedState state) {
    throw UnimplementedError('led() has not been implemented.');
  }

  Future<void> luma(int level) {
    throw UnimplementedError('luma() has not been implemented.');
  }

  Future<void> sensor(bool enable) {
    throw UnimplementedError('sensor() has not been implemented.');
  }

  Future<void> gesture(bool enable) {
    throw UnimplementedError('gesture() has not been implemented.');
  }

  Future<void> als(bool enable) {
    throw UnimplementedError('als() has not been implemented.');
  }

  Future<void> shift(int x, int y) {
    throw UnimplementedError('shift() has not been implemented.');
  }

  /// Reads back the device's current persisted settings (shift, luma, ALS,
  /// gesture) — see [ActiveLookGlassesSettings]'s doc comment.
  Future<ActiveLookGlassesSettings> settings() {
    throw UnimplementedError('settings() has not been implemented.');
  }

  Future<void> holdFlush(ActiveLookHoldFlushAction action) {
    throw UnimplementedError('holdFlush() has not been implemented.');
  }

  // --- Vector drawing commands (ActiveLook_API.md §4.6) ---

  Future<void> color(int level) {
    throw UnimplementedError('color() has not been implemented.');
  }

  Future<void> point(int x, int y) {
    throw UnimplementedError('point() has not been implemented.');
  }

  Future<void> line(int x1, int y1, int x2, int y2) {
    throw UnimplementedError('line() has not been implemented.');
  }

  Future<void> rect(int x1, int y1, int x2, int y2) {
    throw UnimplementedError('rect() has not been implemented.');
  }

  Future<void> rectFilled(int x1, int y1, int x2, int y2) {
    throw UnimplementedError('rectFilled() has not been implemented.');
  }

  Future<void> circle(int x, int y, int radius) {
    throw UnimplementedError('circle() has not been implemented.');
  }

  Future<void> circleFilled(int x, int y, int radius) {
    throw UnimplementedError('circleFilled() has not been implemented.');
  }

  Future<void> text(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int color,
    String text,
  ) {
    throw UnimplementedError('text() has not been implemented.');
  }

  Future<void> polyline(List<int> xyPairs, {int thickness = 1}) {
    throw UnimplementedError('polyline() has not been implemented.');
  }

  // --- Layout commands (ActiveLook_API.md §4.11) ---

  Future<void> layoutSave(ActiveLookLayoutParameters layout) {
    throw UnimplementedError('layoutSave() has not been implemented.');
  }

  Future<void> layoutDisplay(int id, String text) {
    throw UnimplementedError('layoutDisplay() has not been implemented.');
  }

  Future<void> layoutDisplayExtended(int id, int x, int y, String text) {
    throw UnimplementedError('layoutDisplayExtended() has not been implemented.');
  }

  Future<void> layoutClear(int id) {
    throw UnimplementedError('layoutClear() has not been implemented.');
  }

  Future<void> layoutClearAndDisplay(int id, String text) {
    throw UnimplementedError('layoutClearAndDisplay() has not been implemented.');
  }

  Future<void> layoutDelete(int id) {
    throw UnimplementedError('layoutDelete() has not been implemented.');
  }

  Future<List<int>> layoutList() {
    throw UnimplementedError('layoutList() has not been implemented.');
  }

  /// Reads back a saved layout's real parameters — position, size, font,
  /// text position/rotation/opacity — see [ActiveLookLayoutParameters
  /// .fromMap]'s doc comment on why `id` must be passed in separately from
  /// the response.
  Future<ActiveLookLayoutParameters> layoutGet(int id) {
    throw UnimplementedError('layoutGet() has not been implemented.');
  }

  // --- Gauge commands (ActiveLook_API.md §4.10) ---

  Future<void> gaugeSave(ActiveLookGaugeInfo gauge) {
    throw UnimplementedError('gaugeSave() has not been implemented.');
  }

  Future<void> gaugeDisplay(int id, int valuePercent) {
    throw UnimplementedError('gaugeDisplay() has not been implemented.');
  }

  Future<void> gaugeDelete(int id) {
    throw UnimplementedError('gaugeDelete() has not been implemented.');
  }

  // --- Page commands (ActiveLook_API.md §4.11) ---

  Future<void> pageSave(int id, List<int> layoutIds, List<int> xs, List<int> ys) {
    throw UnimplementedError('pageSave() has not been implemented.');
  }

  Future<void> pageDisplay(int id, List<String> texts) {
    throw UnimplementedError('pageDisplay() has not been implemented.');
  }

  Future<void> pageClear(int id) {
    throw UnimplementedError('pageClear() has not been implemented.');
  }

  Future<void> pageDelete(int id) {
    throw UnimplementedError('pageDelete() has not been implemented.');
  }

  // --- Animation commands (ActiveLook_API.md §4.12) ---

  Future<void> animDisplay(
    int handlerId,
    int animId,
    int frameDelayMs,
    int repeatCount,
    int x,
    int y,
  ) {
    throw UnimplementedError('animDisplay() has not been implemented.');
  }

  Future<void> animClear(int handlerId) {
    throw UnimplementedError('animClear() has not been implemented.');
  }

  // --- Pre-flashed "ALooK" firmware configuration (Activelook-Visual-Assets) ---

  /// Activates a named on-device firmware configuration (`cfgSet`) — used to
  /// select the default `ALooK` configuration bundling the 186 pre-built
  /// layouts, icons, and animations described in this repo's plan doc §4.
  Future<void> configSet(String name) {
    throw UnimplementedError('configSet() has not been implemented.');
  }

  // --- Image/bitmap commands ---
  //
  // pngBytes is always a PNG-encoded image (any Dart-side image source can
  // encode to PNG); each native implementation decodes to its own bitmap
  // type (Android Bitmap / iOS UIImage) before calling the underlying SDK,
  // since neither native SDK accepts raw encoded bytes directly for these.

  Future<List<ActiveLookImageInfo>> imgList() {
    throw UnimplementedError('imgList() has not been implemented.');
  }

  Future<void> imgSave(int id, List<int> pngBytes, ActiveLookImageFormat format) {
    throw UnimplementedError('imgSave() has not been implemented.');
  }

  Future<void> imgDisplay(int id, int x, int y) {
    throw UnimplementedError('imgDisplay() has not been implemented.');
  }

  Future<void> imgDelete(int id) {
    throw UnimplementedError('imgDelete() has not been implemented.');
  }

  Future<void> imgDeleteAll() {
    throw UnimplementedError('imgDeleteAll() has not been implemented.');
  }

  /// Draws [pngBytes] directly without saving it to device memory.
  Future<void> imgStream(List<int> pngBytes, ActiveLookImageStreamFormat format, int x, int y) {
    throw UnimplementedError('imgStream() has not been implemented.');
  }

  // --- Font commands ---

  Future<List<ActiveLookFontInfo>> fontList() {
    throw UnimplementedError('fontList() has not been implemented.');
  }

  Future<void> fontSave(int id, List<int> fontBytes) {
    throw UnimplementedError('fontSave() has not been implemented.');
  }

  Future<void> fontSelect(int id) {
    throw UnimplementedError('fontSelect() has not been implemented.');
  }

  Future<void> fontDelete(int id) {
    throw UnimplementedError('fontDelete() has not been implemented.');
  }

  Future<void> fontDeleteAll() {
    throw UnimplementedError('fontDeleteAll() has not been implemented.');
  }

  // --- Firmware configuration management (firmware 1.8+) ---

  Future<void> cfgWrite(String name, int version, int password) {
    throw UnimplementedError('cfgWrite() has not been implemented.');
  }

  Future<ActiveLookConfigurationElementsInfo> cfgRead(String name) {
    throw UnimplementedError('cfgRead() has not been implemented.');
  }

  Future<List<ActiveLookConfigurationDescription>> cfgList() {
    throw UnimplementedError('cfgList() has not been implemented.');
  }

  Future<void> cfgRename(String oldName, String newName, int password) {
    throw UnimplementedError('cfgRename() has not been implemented.');
  }

  Future<void> cfgDelete(String name) {
    throw UnimplementedError('cfgDelete() has not been implemented.');
  }

  Future<void> cfgDeleteLessUsed() {
    throw UnimplementedError('cfgDeleteLessUsed() has not been implemented.');
  }

  Future<ActiveLookFreeSpace> cfgFreeSpace() {
    throw UnimplementedError('cfgFreeSpace() has not been implemented.');
  }

  Future<int> cfgGetNb() {
    throw UnimplementedError('cfgGetNb() has not been implemented.');
  }

  /// Powers the glasses fully off (distinct from [power], which toggles the
  /// display).
  Future<void> shutdown() {
    throw UnimplementedError('shutdown() has not been implemented.');
  }

  // --- Legacy firmware 1.7-only configuration commands ---
  //
  // See ActiveLookLegacyConfiguration's doc comment: Android's and iOS's
  // native Configuration types for this command family are genuinely
  // different shapes, not just differently named.

  Future<void> legacyWriteConfig(ActiveLookLegacyConfiguration config) {
    throw UnimplementedError('legacyWriteConfig() has not been implemented.');
  }

  Future<ActiveLookLegacyConfiguration> legacyReadConfig(int number) {
    throw UnimplementedError('legacyReadConfig() has not been implemented.');
  }

  Future<void> legacySetConfig(int number) {
    throw UnimplementedError('legacySetConfig() has not been implemented.');
  }

  /// Android-only diagnostic command (task debugging). Throws
  /// [ActiveLookUnsupportedOnPlatformException] on iOS — confirmed no
  /// equivalent exists in `ActiveLook/ios-sdk`.
  Future<void> tdbg() {
    throw UnimplementedError('tdbg() has not been implemented.');
  }

  // --- Statistics commands ---

  Future<int> pixelCount() {
    throw UnimplementedError('pixelCount() has not been implemented.');
  }

  Future<int> getChargingCounter() {
    throw UnimplementedError('getChargingCounter() has not been implemented.');
  }

  Future<int> getChargingTime() {
    throw UnimplementedError('getChargingTime() has not been implemented.');
  }

  Future<void> resetChargingParam() {
    throw UnimplementedError('resetChargingParam() has not been implemented.');
  }

  // --- Widget commands (iOS-only) ---
  //
  // Confirmed by reading both native SDKs' source: zero widget commands
  // exist anywhere in ActiveLook's Android SDK. Every method below throws
  // ActiveLookUnsupportedOnPlatformException on Android.

  Future<void> widgetOpenGauge({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int value,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
  }) {
    throw UnimplementedError('widgetOpenGauge() has not been implemented.');
  }

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
  }) {
    throw UnimplementedError('widgetRangeGauge() has not been implemented.');
  }

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
  }) {
    throw UnimplementedError('widgetGaugeZone() has not been implemented.');
  }

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
  }) {
    throw UnimplementedError('widgetTarget() has not been implemented.');
  }

  /// As [widgetTarget], but the native SDK clamps [value] to `[16, 237]`
  /// before sending (confirmed in `Glasses.swift`'s `widgetTargetLeft`).
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
  }) {
    throw UnimplementedError('widgetTargetLeft() has not been implemented.');
  }

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
  }) {
    throw UnimplementedError('widgetBarChart() has not been implemented.');
  }

  Future<void> widgetData({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
  }) {
    throw UnimplementedError('widgetData() has not been implemented.');
  }
}
