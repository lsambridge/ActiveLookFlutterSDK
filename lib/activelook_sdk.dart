import 'activelook_sdk_platform_interface.dart';
import 'src/activelook_types.dart';

export 'activelook_sdk_platform_interface.dart' show ActivelookSdkPlatform;
export 'src/activelook_safe_canvas.dart';
export 'src/activelook_sdk_fake.dart';
export 'src/activelook_types.dart';

/// Dart wrapper over ActiveLook's official Android (`android-sdk`) and iOS
/// (`ios-sdk`) native SDKs, for ActiveLook/ENGO Eyewear smart glasses.
///
/// There is no official Flutter SDK for ActiveLook — see
/// `docs/plan-race-mode-activelook-glasses.md` (Engyne repo) §3/§7/§13 for
/// the scoping behind this package. This class exposes the connection
/// lifecycle, device event streams, and the native SDKs' draw/query command
/// surface as idiomatic Dart, without re-implementing ActiveLook's own
/// byte-level protocol — both native SDKs already expose typed high-level
/// methods, so this bridge's job is surfacing those to Dart, not re-encoding
/// commands.
///
/// Usage:
/// ```dart
/// final sdk = ActivelookSdk();
/// final sub = sdk.startScan().listen((glasses) async {
///   await sdk.stopScan();
///   await sdk.connect(glasses.id);
/// });
/// ```
class ActivelookSdk {
  ActivelookSdkPlatform get _platform => ActivelookSdkPlatform.instance;

  // --- Scanning & connection ---

  /// Starts scanning for ActiveLook glasses. Keeps scanning until
  /// [stopScan] is called or the returned stream is cancelled.
  Stream<ActiveLookDiscoveredGlasses> startScan() => _platform.startScan();

  Future<void> stopScan() => _platform.stopScan();

  /// Connects to previously discovered (or previously paired) glasses by
  /// [id] (see [ActiveLookDiscoveredGlasses.id]).
  ///
  /// Throws [ActiveLookConnectionException] on failure.
  Future<void> connect(String id) => _platform.connect(id);

  Future<void> disconnect() => _platform.disconnect();

  /// Connection lifecycle, including unsolicited disconnects — the native
  /// SDKs deliver connection loss via a callback on the connected glasses
  /// object, not a separate stream, so this normalizes both into one place.
  Stream<ActiveLookConnectionState> get connectionState => _platform.connectionState;

  Future<ActiveLookDeviceInformation> getDeviceInformation() => _platform.getDeviceInformation();

  /// One-shot battery query (`battery` command), distinct from the ongoing
  /// [batteryLevelNotifications] stream the glasses push roughly every 30s.
  Future<int> getBatteryLevel() => _platform.getBatteryLevel();

  // --- Device event streams ---

  Stream<int> get batteryLevelNotifications => _platform.batteryLevelNotifications;

  /// The device's backpressure signal (`ActiveLook_API.md` §3.5). Callers
  /// must pause sending draw commands while this reports
  /// [ActiveLookFlowControlStatus.bufferFull] — this package does not queue
  /// or drop commands on the caller's behalf.
  Stream<ActiveLookFlowControlStatus> get flowControlNotifications => _platform.flowControlNotifications;

  /// Fires on a double-tap of the glasses' capacitive touch button — the
  /// only sensor event exposed by ActiveLook's API today (no payload).
  Stream<void> get sensorTapNotifications => _platform.sensorTapNotifications;

  // --- General device commands ---

  Future<void> power(bool on) => _platform.power(on);

  Future<void> clear() => _platform.clear();

  /// Sets the whole display to a grey level between 0 and 15.
  Future<void> grey(int level) => _platform.grey(level);

  Future<void> led(ActiveLookLedState state) => _platform.led(state);

  /// Sets display luminance, between 0 and 15.
  Future<void> luma(int level) => _platform.luma(level);

  /// Enables/disables both auto-brightness and gesture detection together.
  Future<void> sensor(bool enable) => _platform.sensor(enable);

  Future<void> gesture(bool enable) => _platform.gesture(enable);

  /// Ambient-light-sensor-driven auto brightness only.
  Future<void> als(bool enable) => _platform.als(enable);

  /// Shifts all subsequent draw commands by ([x], [y]) pixels, each between
  /// -128 and 127.
  Future<void> shift(int x, int y) => _platform.shift(x, y);

  /// Reads the device's current persisted settings (shift, luma, ALS,
  /// gesture) — see [ActiveLookGlassesSettings]'s doc comment on why this is
  /// worth calling on every connect before assuming/overwriting a shift
  /// value.
  Future<ActiveLookGlassesSettings> settings() => _platform.settings();

  /// Holds or flushes the on-device graphic engine — see
  /// [ActiveLookHoldFlushAction]. `clear()` is not affected by hold.
  Future<void> holdFlush(ActiveLookHoldFlushAction action) => _platform.holdFlush(action);

  // --- Vector drawing (ActiveLook_API.md §4.6) ---

  /// Sets the grey level (0-15) used to draw subsequent graphical elements.
  ///
  /// Despite the method name (matching both native SDKs' own naming), this
  /// is genuinely the `0x30 grayscale` wire command, **not** `0x3D color`
  /// (`ActiveLook_API.md` §4.6) — confirmed on real hardware (2026-09-02):
  /// both `android-sdk`'s and `ios-sdk`'s `color(level)` route through
  /// grayscale-only encoding (Android's asserts `0-15` and crashed when
  /// given a real RG palette byte; iOS has no assert but sends the same
  /// `0x30` opcode). Neither native SDK exposes the real `0x3D color`
  /// command under any name — use [rawColor]/[rawTextColor] for that on
  /// color-panel (`MDP08`) glasses, with an [ActiveLookColorPalette] byte.
  ///
  /// Calling this before each draw call (`rect`, `circle`, `text`, etc.)
  /// lets different shapes on the same screen carry different grey levels
  /// simultaneously — the device remembers the value drawn with, it is not
  /// a single global mode (`ActiveLook_API.md` §5.1).
  Future<void> color(int level) => _platform.color(level);

  Future<void> point(int x, int y) => _platform.point(x, y);

  Future<void> line(int x1, int y1, int x2, int y2) => _platform.line(x1, y1, x2, y2);

  Future<void> rect(int x1, int y1, int x2, int y2) => _platform.rect(x1, y1, x2, y2);

  Future<void> rectFilled(int x1, int y1, int x2, int y2) => _platform.rectFilled(x1, y1, x2, y2);

  Future<void> circle(int x, int y, int radius) => _platform.circle(x, y, radius);

  Future<void> circleFilled(int x, int y, int radius) => _platform.circleFilled(x, y, radius);

  /// [color] is a grey level 0-15 (`ActiveLook_API.md` §4.6, `0x37 txt`'s
  /// `u8 grey` parameter) — **not** an [ActiveLookColorPalette] byte, on
  /// any hardware. For real color text on color-panel glasses use
  /// [rawTextColor] (`0x3E txtColor`) instead — see that method's doc
  /// comment, and [color]-the-method's doc comment for the same
  /// grayscale-vs-color distinction found on real hardware (2026-09-02).
  Future<void> text(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int color,
    String text,
  ) =>
      _platform.text(x, y, rotation, fontSize, color, text);

  /// Draws connected line segments through [xyPairs] (`[x0, y0, x1, y1, ...]`).
  Future<void> polyline(List<int> xyPairs, {int thickness = 1}) =>
      _platform.polyline(xyPairs, thickness: thickness);

  // --- Layouts (ActiveLook_API.md §4.11) ---

  Future<void> layoutSave(ActiveLookLayoutParameters layout) => _platform.layoutSave(layout);

  /// As [layoutSave], but interprets [layout]'s
  /// foregroundColor/backgroundColor as [ActiveLookColorPalette] bytes
  /// (`COLOR_VERSION`/`0x6B layoutSaveInColor`) instead of grey levels —
  /// color-panel (`MDP08`) glasses only. See
  /// [ActivelookSdkPlatform.layoutSaveInColor]'s doc comment for why this
  /// needs its own method rather than being a flag on [layoutSave].
  Future<void> layoutSaveInColor(ActiveLookLayoutParameters layout) =>
      _platform.layoutSaveInColor(layout);

  /// The real `0x3D color` command — see
  /// [ActivelookSdkPlatform.rawColor]'s doc comment on why this is
  /// distinct from [color], which is actually wired to `0x30 grayscale` on
  /// both native SDKs despite its name (found on real hardware,
  /// 2026-09-02). Color-panel glasses only.
  Future<void> rawColor(int value) => _platform.rawColor(value);

  /// The real `0x3E txtColor` command — as [text], but [colorValue] is an
  /// [ActiveLookColorPalette] byte, not a grey level. See [rawColor]'s doc
  /// comment.
  Future<void> rawTextColor(
    int x,
    int y,
    ActiveLookTextRotation rotation,
    int fontSize,
    int colorValue,
    String text,
  ) =>
      _platform.rawTextColor(x, y, rotation, fontSize, colorValue, text);

  /// Sends pre-built command frames straight to the device - see
  /// [ActivelookSdkPlatform.sendRawFrames]'s doc comment. Used for
  /// `animSave`, whose frames are pre-encoded offline (not built at
  /// runtime, unlike [layoutSaveInColor]/[rawColor]).
  Future<void> sendRawFrames(List<List<int>> frames) => _platform.sendRawFrames(frames);

  /// Displays [text] using the previously saved layout [id], at the
  /// layout's saved position.
  Future<void> layoutDisplay(int id, String text) => _platform.layoutDisplay(id, text);

  /// As [layoutDisplay], but at an explicit position that is not saved.
  Future<void> layoutDisplayExtended(int id, int x, int y, String text) =>
      _platform.layoutDisplayExtended(id, x, y, text);

  Future<void> layoutClear(int id) => _platform.layoutClear(id);

  Future<void> layoutClearAndDisplay(int id, String text) => _platform.layoutClearAndDisplay(id, text);

  Future<void> layoutDelete(int id) => _platform.layoutDelete(id);

  Future<List<int>> layoutList() => _platform.layoutList();

  /// Reads back saved layout [id]'s real parameters (position, size, font,
  /// text position/rotation/opacity) — useful to confirm what a pre-built
  /// configuration's layout ids actually contain on a specific unit, rather
  /// than trusting third-party documentation of what a config version is
  /// supposed to contain (confirmed necessary on real hardware, 2026-09-02:
  /// a unit's on-device `ALooK` layout ids didn't match
  /// `Activelook-Visual-Assets`' published table at all).
  Future<ActiveLookLayoutParameters> layoutGet(int id) => _platform.layoutGet(id);

  // --- Gauges (ActiveLook_API.md §4.10) ---

  Future<void> gaugeSave(ActiveLookGaugeInfo gauge) => _platform.gaugeSave(gauge);

  /// Displays gauge [id] (previously saved via [gaugeSave]) at [valuePercent]
  /// (0-100).
  Future<void> gaugeDisplay(int id, int valuePercent) => _platform.gaugeDisplay(id, valuePercent);

  Future<void> gaugeDelete(int id) => _platform.gaugeDelete(id);

  // --- Pages (ActiveLook_API.md §4.11) ---

  Future<void> pageSave(int id, List<int> layoutIds, List<int> xs, List<int> ys) =>
      _platform.pageSave(id, layoutIds, xs, ys);

  Future<void> pageDisplay(int id, List<String> texts) => _platform.pageDisplay(id, texts);

  Future<void> pageClear(int id) => _platform.pageClear(id);

  Future<void> pageDelete(int id) => _platform.pageDelete(id);

  // --- Animations (ActiveLook_API.md §4.12) ---

  /// Plays animation [animId], identified at runtime by caller-chosen
  /// [handlerId] (used later to [animClear] it), at ([x], [y]).
  Future<void> animDisplay(
    int handlerId,
    int animId,
    int frameDelayMs,
    int repeatCount,
    int x,
    int y,
  ) =>
      _platform.animDisplay(handlerId, animId, frameDelayMs, repeatCount, x, y);

  Future<void> animClear(int handlerId) => _platform.animClear(handlerId);

  // --- Pre-flashed "ALooK" firmware configuration ---

  /// Activates a named on-device configuration (`cfgSet`) — e.g. `"ALooK"`,
  /// ActiveLook's default pre-flashed configuration bundling ~186 layout
  /// templates, icons, and small animations. See this repo's plan doc §4.
  Future<void> configSet(String name) => _platform.configSet(name);

  // --- Image/bitmap commands ---

  Future<List<ActiveLookImageInfo>> imgList() => _platform.imgList();

  /// Saves a PNG-encoded image to the glasses at [id], in [format].
  Future<void> imgSave(int id, List<int> pngBytes, ActiveLookImageFormat format) =>
      _platform.imgSave(id, pngBytes, format);

  Future<void> imgDisplay(int id, int x, int y) => _platform.imgDisplay(id, x, y);

  Future<void> imgDelete(int id) => _platform.imgDelete(id);

  Future<void> imgDeleteAll() => _platform.imgDeleteAll();

  /// Draws a PNG-encoded image directly at ([x], [y]) without saving it to
  /// device memory.
  Future<void> imgStream(List<int> pngBytes, ActiveLookImageStreamFormat format, int x, int y) =>
      _platform.imgStream(pngBytes, format, x, y);

  // --- Font commands ---

  Future<List<ActiveLookFontInfo>> fontList() => _platform.fontList();

  Future<void> fontSave(int id, List<int> fontBytes) => _platform.fontSave(id, fontBytes);

  /// Selects the font used by subsequent [text] calls.
  Future<void> fontSelect(int id) => _platform.fontSelect(id);

  Future<void> fontDelete(int id) => _platform.fontDelete(id);

  Future<void> fontDeleteAll() => _platform.fontDeleteAll();

  // --- Firmware configuration management (firmware 1.8+) ---

  Future<void> cfgWrite(String name, int version, int password) =>
      _platform.cfgWrite(name, version, password);

  Future<ActiveLookConfigurationElementsInfo> cfgRead(String name) => _platform.cfgRead(name);

  Future<List<ActiveLookConfigurationDescription>> cfgList() => _platform.cfgList();

  Future<void> cfgRename(String oldName, String newName, int password) =>
      _platform.cfgRename(oldName, newName, password);

  Future<void> cfgDelete(String name) => _platform.cfgDelete(name);

  Future<void> cfgDeleteLessUsed() => _platform.cfgDeleteLessUsed();

  Future<ActiveLookFreeSpace> cfgFreeSpace() => _platform.cfgFreeSpace();

  Future<int> cfgGetNb() => _platform.cfgGetNb();

  /// Powers the glasses fully off (distinct from [power], which only toggles
  /// the display).
  Future<void> shutdown() => _platform.shutdown();

  // --- Legacy firmware 1.7-only configuration commands ---

  Future<void> legacyWriteConfig(ActiveLookLegacyConfiguration config) =>
      _platform.legacyWriteConfig(config);

  Future<ActiveLookLegacyConfiguration> legacyReadConfig(int number) =>
      _platform.legacyReadConfig(number);

  Future<void> legacySetConfig(int number) => _platform.legacySetConfig(number);

  /// Android-only diagnostic command. Throws
  /// [ActiveLookUnsupportedOnPlatformException] on iOS.
  Future<void> tdbg() => _platform.tdbg();

  // --- Statistics commands ---

  Future<int> pixelCount() => _platform.pixelCount();

  Future<int> getChargingCounter() => _platform.getChargingCounter();

  Future<int> getChargingTime() => _platform.getChargingTime();

  Future<void> resetChargingParam() => _platform.resetChargingParam();

  // --- Widget commands (iOS-only; throw ActiveLookUnsupportedOnPlatformException on Android) ---

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
      _platform.widgetOpenGauge(
        size: size,
        x: x,
        y: y,
        value: value,
        imageId: imageId,
        valueType: valueType,
        unit: unit,
        shownValue: shownValue,
      );

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
      _platform.widgetRangeGauge(
        size: size,
        x: x,
        y: y,
        value: value,
        imageId: imageId,
        valueType: valueType,
        unit: unit,
        shownValue: shownValue,
        min: min,
        max: max,
      );

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
      _platform.widgetGaugeZone(
        size: size,
        x: x,
        y: y,
        value: value,
        imageId: imageId,
        valueType: valueType,
        unit: unit,
        shownValue: shownValue,
        chosenZone: chosenZone,
        zoneCount: zoneCount,
      );

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
      _platform.widgetTarget(
        size: size,
        x: x,
        y: y,
        value: value,
        imageId: imageId,
        valueType: valueType,
        unit: unit,
        shownValue: shownValue,
        goal: goal,
      );

  /// As [widgetTarget], but the native SDK clamps [value] to `[16, 237]`.
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
      _platform.widgetTargetLeft(
        size: size,
        x: x,
        y: y,
        value: value,
        imageId: imageId,
        valueType: valueType,
        unit: unit,
        shownValue: shownValue,
        goal: goal,
      );

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
      _platform.widgetBarChart(
        size: size,
        x: x,
        y: y,
        imageId: imageId,
        valueType: valueType,
        unit: unit,
        shownValue: shownValue,
        chosenZone: chosenZone,
        zoneCount: zoneCount,
        zoneValues: zoneValues,
      );

  Future<void> widgetData({
    required ActiveLookWidgetSize size,
    required int x,
    required int y,
    required int imageId,
    required ActiveLookWidgetValueType valueType,
    required String unit,
    required String shownValue,
  }) =>
      _platform.widgetData(
        size: size,
        x: x,
        y: y,
        imageId: imageId,
        valueType: valueType,
        unit: unit,
        shownValue: shownValue,
      );
}
