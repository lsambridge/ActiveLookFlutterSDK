import ActiveLookSDK
import Flutter
import UIKit

/// iOS bridge to ActiveLook's official `ios-sdk` (`ActiveLookSDK`/`Glasses`/`DiscoveredGlasses`).
///
/// `CBCentralManager` here is created with `queue: nil`, which per Apple's CoreBluetooth docs
/// means its delegate callbacks land on the main queue by default — confirmed by reading
/// `ActiveLookSDK.swift` directly (see docs/plan-race-mode-activelook-glasses.md §7.3/§13.3 in
/// the Engyne repo for the cross-platform threading comparison against Android). Callbacks are
/// still explicitly dispatched to the main queue here regardless, so this plugin does not rely on
/// that being the vendor SDK's permanent behaviour.
public class ActivelookSdkPlugin: NSObject, FlutterPlugin {
    private var scanSink: FlutterEventSink?
    private var connectionStateSink: FlutterEventSink?
    private var batterySink: FlutterEventSink?
    private var flowControlSink: FlutterEventSink?
    private var sensorTapSink: FlutterEventSink?

    private var discovered: [String: DiscoveredGlasses] = [:]
    private var connectedGlasses: Glasses?

    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }

    /// Builds the `SerializedGlasses` (`= Data`) blob `ActiveLookSDK.connect(using:)` needs for a
    /// scan-free reconnect from a saved id alone - confirmed against the SDK's own
    /// `UnserializedGlasses`/`SerializedGlasses.swift` (v4.5.5): a JSON object of exactly
    /// `{"id": String, "name": String, "manId": String}`, where only `id` (parsed back into a
    /// `UUID` and passed to `CBCentralManager.retrievePeripherals(withIdentifiers:)`) matters for
    /// reconnection - `name`/`manId` are never read on this path, so placeholders are fine. The
    /// SDK's documented preferred approach is instead persisting the real blob from
    /// `Glasses.getSerializedGlasses()` right after a scan-based connect, but this plugin only
    /// ever stores the raw id string (matching `ActiveLookPairingStorage` on the Flutter side), so
    /// this reconstructs the equivalent shape from that instead of changing what's persisted.
    private static func serializedGlasses(forId id: String) -> SerializedGlasses? {
        try? JSONSerialization.data(withJSONObject: ["id": id, "name": "", "manId": ""])
    }

    private func sdk() throws -> ActiveLookSDK {
        try ActiveLookSDK.shared(
            onUpdateStartCallback: { _ in },
            onUpdateAvailableCallback: { _, proceed in proceed() },
            onUpdateProgressCallback: { _ in },
            onUpdateSuccessCallback: { _ in },
            onUpdateFailureCallback: { _ in }
        )
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ActivelookSdkPlugin()

        let channel = FlutterMethodChannel(name: "activelook_sdk", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)

        FlutterEventChannel(name: "activelook_sdk/scan", binaryMessenger: registrar.messenger())
            .setStreamHandler(ScanStreamHandler(plugin: instance))
        FlutterEventChannel(name: "activelook_sdk/connection_state", binaryMessenger: registrar.messenger())
            .setStreamHandler(ConnectionStateStreamHandler(plugin: instance))
        FlutterEventChannel(name: "activelook_sdk/battery", binaryMessenger: registrar.messenger())
            .setStreamHandler(BatteryStreamHandler(plugin: instance))
        FlutterEventChannel(name: "activelook_sdk/flow_control", binaryMessenger: registrar.messenger())
            .setStreamHandler(FlowControlStreamHandler(plugin: instance))
        FlutterEventChannel(name: "activelook_sdk/sensor_tap", binaryMessenger: registrar.messenger())
            .setStreamHandler(SensorTapStreamHandler(plugin: instance))
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        func requireInt(_ key: String) -> Int? { args[key] as? Int }
        func requireString(_ key: String) -> String? { args[key] as? String }

        switch call.method {
        case "startScan":
            discovered.removeAll()
            do {
                try sdk().startScanning(onGlassesDiscovered: { [weak self] dg in
                    guard let self = self else { return }
                    self.onMain {
                        self.discovered[dg.identifier.uuidString] = dg
                        self.scanSink?([
                            "id": dg.identifier.uuidString,
                            "name": dg.name,
                            "manufacturer": dg.manufacturerId,
                        ])
                    }
                }, onScanError: { [weak self] error in
                    self?.onMain { self?.scanSink?(FlutterError(code: "SCAN_ERROR", message: error.localizedDescription, details: nil)) }
                })
                result(nil)
            } catch {
                result(FlutterError(code: "SDK_ERROR", message: error.localizedDescription, details: nil))
            }

        case "stopScan":
            try? sdk().stopScanning()
            result(nil)

        case "connect":
            guard let id = requireString("id") else {
                result(FlutterError(code: "NOT_FOUND", message: "No device id given to connect.", details: nil))
                return
            }
            // `result` must resolve exactly once, from whichever of onGlassesConnected/
            // onConnectionError fires first - confirmed on real hardware (2026-09-02,
            // Android build of this same handler) that the previous version called
            // result(nil) unconditionally, immediately after dispatching dg.connect()/
            // sdk().connect() below, rather than waiting for either callback. That made
            // the Dart-side `await sdk.connect(id)` resolve as soon as the native connect
            // *attempt* was merely dispatched - not once a real GATT/CoreBluetooth
            // connection existed - so RaceModeGlassesHud._onConnected's very next call
            // (sdk.settings()) could race a connection still mid-handshake and hang/fail
            // silently. A debugger breakpoint placed between the two masked this
            // completely on Android (gave the real handshake time to finish before the
            // next command fired) - fixed here defensively too since this iOS build has
            // no toolchain available to reproduce/verify the bug directly, only reason
            // about the parallel structure.
            var resultDelivered = false
            func deliverSuccess() {
                if resultDelivered { return }
                resultDelivered = true
                result(nil)
            }
            func deliverFailure(_ message: String, code: String = "CONNECT_FAILED") {
                if resultDelivered { return }
                resultDelivered = true
                result(FlutterError(code: code, message: message, details: nil))
            }

            let onConnected: (Glasses) -> Void = { [weak self] glasses in
                guard let self = self else { return }
                self.onMain {
                    self.connectedGlasses = glasses
                    glasses.onDisconnect {
                        self.onMain {
                            self.connectedGlasses = nil
                            self.connectionStateSink?("disconnected")
                        }
                    }
                    self.connectionStateSink?("connected")
                    deliverSuccess()
                }
            }
            let onDisconnected: () -> Void = { [weak self] in
                self?.onMain {
                    self?.connectedGlasses = nil
                    self?.connectionStateSink?("disconnected")
                }
            }
            let onConnectionError: (Error) -> Void = { [weak self] error in
                self?.onMain {
                    self?.connectedGlasses = nil
                    self?.connectionStateSink?("disconnected")
                    deliverFailure(error.localizedDescription)
                }
            }
            onMain { self.connectionStateSink?("connecting") }
            if let dg = discovered[id] {
                // Address just came from an active/recent scan (this session's
                // process) - connect through the DiscoveredGlasses instance the
                // scan callback handed us, as before.
                dg.connect(
                    onGlassesConnected: onConnected,
                    onGlassesDisconnected: onDisconnected,
                    onConnectionError: onConnectionError
                )
            } else if let serialized = Self.serializedGlasses(forId: id) {
                // No scan this process (e.g. app cold-started and the Flutter
                // side reconnects straight from a saved device id, deliberately
                // without scanning first - see RaceModeGlassesHud.start) - the
                // `discovered` dictionary above is scan-populated only and empty
                // here. ActiveLookSDK.connect(using:) is the SDK's own scan-free
                // path for exactly this: it unserializes the id, tries
                // CBCentralManager.retrievePeripherals(withIdentifiers:)
                // internally, so no prior discovery/scan result is required -
                // only name/manId are placeholders since only the id is used to
                // retrieve the peripheral.
                do {
                    try sdk().connect(
                        using: serialized,
                        onGlassesConnected: onConnected,
                        onGlassesDisconnected: onDisconnected,
                        onConnectionError: onConnectionError
                    )
                } catch {
                    onMain { self.connectionStateSink?("disconnected") }
                    deliverFailure(error.localizedDescription)
                }
            } else {
                onMain { self.connectionStateSink?("disconnected") }
                deliverFailure(
                    "No discovered glasses with id \(id) and could not build a serialized reconnect payload.",
                    code: "NOT_FOUND"
                )
            }

        case "disconnect":
            connectedGlasses?.disconnect()
            result(nil)

        case "getDeviceInformation":
            let di = connectedGlasses?.getDeviceInformation()
            result([
                "manufacturerName": di?.manufacturerName as Any,
                "modelNumber": di?.modelNumber as Any,
                "serialNumber": di?.serialNumber as Any,
                "hardwareVersion": di?.hardwareVersion as Any,
                "firmwareVersion": di?.firmwareVersion as Any,
                "softwareVersion": di?.softwareVersion as Any,
            ])

        case "getBatteryLevel":
            withGlasses(result: result) { g in g.battery { level in self.onMain { result(level) } } }

        case "power":
            withGlasses(result: result) { g in g.power(on: (args["on"] as? Bool) == true); result(nil) }
        case "clear":
            withGlasses(result: result) { g in g.clear(); result(nil) }
        case "grey":
            withGlasses(result: result) { g in g.grey(level: UInt8(requireInt("level") ?? 0)); result(nil) }
        case "led":
            withGlasses(result: result) { g in
                g.led(state: Self.ledState(from: requireString("state") ?? "off"))
                result(nil)
            }
        case "luma":
            withGlasses(result: result) { g in g.luma(level: UInt8(requireInt("level") ?? 0)); result(nil) }
        case "sensor":
            withGlasses(result: result) { g in g.sensor(enabled: (args["enable"] as? Bool) == true); result(nil) }
        case "gesture":
            withGlasses(result: result) { g in g.gesture(enabled: (args["enable"] as? Bool) == true); result(nil) }
        case "als":
            withGlasses(result: result) { g in g.als(enabled: (args["enable"] as? Bool) == true); result(nil) }
        case "shift":
            withGlasses(result: result) { g in
                g.shift(x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0))
                result(nil)
            }
        case "holdFlush":
            withGlasses(result: result) { g in
                g.holdFlush(holdFlush: requireString("action") == "hold" ? .HOLD : .FLUSH)
                result(nil)
            }
        case "settings":
            withGlasses(result: result) { g in
                g.settings { s in
                    self.onMain {
                        result([
                            "xShift": s.xShift,
                            "yShift": s.yShift,
                            "luma": s.luma,
                            "alsEnabled": s.brightnessAdjustmentEnabled,
                            "gestureEnabled": s.gestureDetectionEnabled,
                        ])
                    }
                }
            }

        case "color":
            withGlasses(result: result) { g in g.color(level: UInt8(requireInt("level") ?? 0)); result(nil) }
        case "rawColor":
            withGlasses(result: result) { g in
                Self.sendRawCommand(g, commandId: 0x3D, data: [UInt8(requireInt("value") ?? 0)])
                result(nil)
            }
        case "rawTextColor":
            withGlasses(result: result) { g in
                var data: [UInt8] = []
                data.append(contentsOf: Self.bigEndianInt16(Int16(requireInt("x") ?? 0)))
                data.append(contentsOf: Self.bigEndianInt16(Int16(requireInt("y") ?? 0)))
                data.append(Self.textRotation(from: requireString("rotation") ?? "topLeftToRight").rawValue)
                data.append(UInt8(requireInt("fontSize") ?? 0))
                data.append(UInt8(requireInt("colorValue") ?? 0))
                // android-sdk's addNulTerminatedStrings uses US_ASCII, confirmed by reading
                // CommandData.java directly - matched here rather than UTF-8 to keep both
                // platforms byte-identical for any non-ASCII input, even though this command
                // is only ever used with plain ASCII debug strings today.
                data.append(contentsOf: Array((requireString("text") ?? "").data(using: .ascii) ?? Data()))
                data.append(0x00)
                Self.sendRawCommand(g, commandId: 0x3E, data: data)
                result(nil)
            }
        case "sendRawFrames":
            withGlasses(result: result) { g in
                // Framework-standard-codec nested lists bridge to [Any] of [Any] on iOS, not
                // directly to [[Int]] - cast defensively per-element (each inner value arrives
                // as NSNumber) rather than risk a single all-or-nothing [[Int]] cast silently
                // producing an empty array on a bridging mismatch this file's author can't
                // verify without a Swift toolchain (2026-09-02).
                //
                // A Dart Uint8List frame specifically bridges to FlutterStandardTypedData (or
                // plain Data) here, not [Any] - confirmed by the Android build of this same
                // handler crashing on real hardware with exactly that mismatch ("byte[] cannot
                // be cast to java.util.List") before the Dart side was fixed to always send a
                // plain List<int>. Handled defensively here too since an unhandled case would
                // have silently dropped that frame via compactMap rather than erroring loudly.
                let framesAny = (args["frames"] as? [Any]) ?? []
                let hexLines: [String] = framesAny.compactMap { frameAny -> String? in
                    if let typedData = frameAny as? FlutterStandardTypedData {
                        return typedData.data.map { String(format: "%02X", $0) }.joined()
                    }
                    if let data = frameAny as? Data {
                        return data.map { String(format: "%02X", $0) }.joined()
                    }
                    guard let frame = frameAny as? [Any] else { return nil }
                    let bytes = frame.compactMap { ($0 as? NSNumber)?.uint8Value }
                    guard bytes.count == frame.count else { return nil }
                    return bytes.map { String(format: "%02X", $0) }.joined()
                }
                g.loadConfiguration(cfg: hexLines)
                result(nil)
            }
        case "point":
            withGlasses(result: result) { g in
                g.point(x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0))
                result(nil)
            }
        case "line":
            withGlasses(result: result) { g in
                g.line(
                    x0: Int16(requireInt("x1") ?? 0), x1: Int16(requireInt("x2") ?? 0),
                    y0: Int16(requireInt("y1") ?? 0), y1: Int16(requireInt("y2") ?? 0)
                )
                result(nil)
            }
        case "rect":
            withGlasses(result: result) { g in
                g.rect(
                    x0: Int16(requireInt("x1") ?? 0), x1: Int16(requireInt("x2") ?? 0),
                    y0: Int16(requireInt("y1") ?? 0), y1: Int16(requireInt("y2") ?? 0)
                )
                result(nil)
            }
        case "rectFilled":
            withGlasses(result: result) { g in
                g.rectf(
                    x0: Int16(requireInt("x1") ?? 0), x1: Int16(requireInt("x2") ?? 0),
                    y0: Int16(requireInt("y1") ?? 0), y1: Int16(requireInt("y2") ?? 0)
                )
                result(nil)
            }
        case "circle":
            withGlasses(result: result) { g in
                g.circ(x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0), radius: UInt8(requireInt("radius") ?? 0))
                result(nil)
            }
        case "circleFilled":
            withGlasses(result: result) { g in
                g.circf(x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0), radius: UInt8(requireInt("radius") ?? 0))
                result(nil)
            }
        case "text":
            withGlasses(result: result) { g in
                g.txt(
                    x: Int16(requireInt("x") ?? 0),
                    y: Int16(requireInt("y") ?? 0),
                    rotation: Self.textRotation(from: requireString("rotation") ?? "bottomLeftToRight"),
                    font: UInt8(requireInt("fontSize") ?? 0),
                    color: UInt8(requireInt("color") ?? 0),
                    string: requireString("text") ?? ""
                )
                result(nil)
            }
        case "polyline":
            withGlasses(result: result) { g in
                let xys = (args["xyPairs"] as? [Int]) ?? []
                var points: [Point] = []
                var i = 0
                while i + 1 < xys.count {
                    points.append((x: UInt16(xys[i]), y: UInt16(xys[i + 1])))
                    i += 2
                }
                g.polyline(thickness: UInt8(requireInt("thickness") ?? 1), points: points)
                result(nil)
            }

        case "layoutSave":
            withGlasses(result: result) { g in
                let layout = LayoutParameters(
                    id: UInt8(requireInt("id") ?? 0),
                    x: UInt16(requireInt("x") ?? 0),
                    y: UInt8(requireInt("y") ?? 0),
                    width: UInt16(requireInt("width") ?? 0),
                    height: UInt8(requireInt("height") ?? 0),
                    foregroundColor: UInt8(requireInt("foregroundColor") ?? 15),
                    backgroundColor: UInt8(requireInt("backgroundColor") ?? 0),
                    font: UInt8(requireInt("font") ?? 0),
                    textValid: (args["textValid"] as? Bool) ?? true,
                    textX: UInt16(requireInt("textX") ?? 0),
                    textY: UInt8(requireInt("textY") ?? 0),
                    textRotation: Self.textRotation(from: requireString("textRotation") ?? "topLeftToRight"),
                    textOpacity: (args["textOpacity"] as? Bool) ?? true
                )
                if let imageId = requireInt("imageId") {
                    _ = layout.addSubCommandBitmap(
                        id: UInt8(imageId),
                        x: Int16(requireInt("imageX") ?? 0),
                        y: Int16(requireInt("imageY") ?? 0)
                    )
                }
                g.layoutSave(parameters: layout)
                result(nil)
            }
        case "layoutSaveInColor":
            withGlasses(result: result) { g in
                let layout = LayoutParameters(
                    id: UInt8(requireInt("id") ?? 0),
                    x: UInt16(requireInt("x") ?? 0),
                    y: UInt8(requireInt("y") ?? 0),
                    width: UInt16(requireInt("width") ?? 0),
                    height: UInt8(requireInt("height") ?? 0),
                    foregroundColor: UInt8(requireInt("foregroundColor") ?? 15),
                    backgroundColor: UInt8(requireInt("backgroundColor") ?? 0),
                    font: UInt8(requireInt("font") ?? 0),
                    textValid: (args["textValid"] as? Bool) ?? true,
                    textX: UInt16(requireInt("textX") ?? 0),
                    textY: UInt8(requireInt("textY") ?? 0),
                    textRotation: Self.textRotation(from: requireString("textRotation") ?? "topLeftToRight"),
                    textOpacity: (args["textOpacity"] as? Bool) ?? true
                )
                if let imageId = requireInt("imageId") {
                    _ = layout.addSubCommandBitmap(
                        id: UInt8(imageId),
                        x: Int16(requireInt("imageX") ?? 0),
                        y: Int16(requireInt("imageY") ?? 0)
                    )
                }
                Self.sendRawCommand(g, commandId: 0x6B, data: layout.toCommandData())
                result(nil)
            }
        case "layoutDisplay":
            withGlasses(result: result) { g in
                g.layoutDisplay(id: UInt8(requireInt("id") ?? 0), text: requireString("text") ?? "")
                result(nil)
            }
        case "layoutDisplayExtended":
            withGlasses(result: result) { g in
                g.layoutDisplayExtended(
                    id: UInt8(requireInt("id") ?? 0),
                    x: UInt16(requireInt("x") ?? 0),
                    y: UInt8(requireInt("y") ?? 0),
                    text: requireString("text") ?? ""
                )
                result(nil)
            }
        case "layoutClear":
            withGlasses(result: result) { g in g.layoutClear(id: UInt8(requireInt("id") ?? 0)); result(nil) }
        case "layoutClearAndDisplay":
            withGlasses(result: result) { g in
                g.layoutClearAndDisplay(id: UInt8(requireInt("id") ?? 0), text: requireString("text") ?? "")
                result(nil)
            }
        case "layoutDelete":
            withGlasses(result: result) { g in g.layoutDelete(id: UInt8(requireInt("id") ?? 0)); result(nil) }
        case "layoutList":
            withGlasses(result: result) { g in g.layoutList { ids in self.onMain { result(ids) } } }

        case "gaugeSave":
            withGlasses(result: result) { g in
                g.gaugeSave(
                    id: UInt8(requireInt("id") ?? 0),
                    x: UInt16(requireInt("x") ?? 0),
                    y: UInt16(requireInt("y") ?? 0),
                    externalRadius: UInt16(requireInt("externalRadius") ?? 0),
                    internalRadius: UInt16(requireInt("internalRadius") ?? 0),
                    start: UInt8(requireInt("startAngle") ?? 0),
                    end: UInt8(requireInt("endAngle") ?? 0),
                    clockwise: (args["clockwise"] as? Bool) ?? true
                )
                result(nil)
            }
        case "gaugeDisplay":
            withGlasses(result: result) { g in
                g.gaugeDisplay(id: UInt8(requireInt("id") ?? 0), value: UInt8(requireInt("value") ?? 0))
                result(nil)
            }
        case "gaugeDelete":
            withGlasses(result: result) { g in g.gaugeDelete(id: UInt8(requireInt("id") ?? 0)); result(nil) }

        case "pageSave":
            withGlasses(result: result) { g in
                let layoutIds = (args["layoutIds"] as? [Int])?.map { UInt8($0) } ?? []
                let xs = (args["xs"] as? [Int])?.map { Int16($0) } ?? []
                let ys = (args["ys"] as? [Int])?.map { UInt8($0) } ?? []
                g.pageSave(id: UInt8(requireInt("id") ?? 0), layoutIds: layoutIds, xs: xs, ys: ys)
                result(nil)
            }
        case "pageDisplay":
            withGlasses(result: result) { g in
                g.pageDisplay(id: UInt8(requireInt("id") ?? 0), texts: (args["texts"] as? [String]) ?? [])
                result(nil)
            }
        case "pageClear":
            withGlasses(result: result) { g in g.pageClear(id: UInt8(requireInt("id") ?? 0)); result(nil) }
        case "pageDelete":
            withGlasses(result: result) { g in g.pageDelete(id: UInt8(requireInt("id") ?? 0)); result(nil) }

        case "animDisplay":
            withGlasses(result: result) { g in
                g.animDisplay(
                    handlerId: UInt8(requireInt("handlerId") ?? 0),
                    id: UInt8(requireInt("animId") ?? 0),
                    delay: UInt16(requireInt("frameDelayMs") ?? 0),
                    repeatAnim: UInt8(requireInt("repeatCount") ?? 0),
                    x: Int16(requireInt("x") ?? 0),
                    y: Int16(requireInt("y") ?? 0)
                )
                result(nil)
            }
        case "animClear":
            withGlasses(result: result) { g in g.animClear(handlerId: UInt8(requireInt("handlerId") ?? 0)); result(nil) }

        case "configSet":
            withGlasses(result: result) { g in g.cfgSet(name: requireString("name") ?? ""); result(nil) }

        // --- Image/bitmap commands ---
        case "imgList":
            withGlasses(result: result) { g in g.imgList { images in
                self.onMain { result(images.map { ["id": $0.id, "width": $0.width, "height": $0.height] }) }
            } }
        case "imgSave":
            withGlasses(result: result) { g in
                guard let data = args["pngBytes"] as? FlutterStandardTypedData, let image = UIImage(data: data.data) else {
                    result(FlutterError(code: "BAD_IMAGE", message: "Could not decode pngBytes as an image.", details: nil))
                    return
                }
                g.imgSave(id: UInt8(requireInt("id") ?? 0), image: image, imgSaveFmt: Self.imgSaveFmt(from: requireString("format") ?? "mono4bpp"))
                result(nil)
            }
        case "imgDisplay":
            withGlasses(result: result) { g in
                g.imgDisplay(id: UInt8(requireInt("id") ?? 0), x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0))
                result(nil)
            }
        case "imgDelete":
            withGlasses(result: result) { g in g.imgDelete(id: UInt8(requireInt("id") ?? 0)); result(nil) }
        case "imgDeleteAll":
            withGlasses(result: result) { g in g.imgDeleteAll(); result(nil) }
        case "imgStream":
            withGlasses(result: result) { g in
                guard let data = args["pngBytes"] as? FlutterStandardTypedData, let image = UIImage(data: data.data) else {
                    result(FlutterError(code: "BAD_IMAGE", message: "Could not decode pngBytes as an image.", details: nil))
                    return
                }
                g.imgStream(
                    image: image,
                    x: Int16(requireInt("x") ?? 0),
                    y: Int16(requireInt("y") ?? 0),
                    imgStreamFmt: Self.imgStreamFmt(from: requireString("format") ?? "mono1bpp")
                )
                result(nil)
            }

        // --- Font commands ---
        // NOTE: iOS's own SDK names this `fontlist` (lowercase 'l') and its own doc comment
        // flags the callback as "NOT WORKING as of 3.7.4b" — a confirmed upstream bug, not a
        // bridge issue. See README.md.
        case "fontList":
            withGlasses(result: result) { g in g.fontlist { fonts in
                self.onMain { result(fonts.map { ["id": $0.id, "height": $0.height] }) }
            } }
        case "fontSave":
            withGlasses(result: result) { g in
                let bytes = (args["fontBytes"] as? FlutterStandardTypedData)?.data ?? Data()
                g.fontSave(id: UInt8(requireInt("id") ?? 0), fontData: FontData(data: [UInt8](bytes)))
                result(nil)
            }
        case "fontSelect":
            withGlasses(result: result) { g in g.fontSelect(id: UInt8(requireInt("id") ?? 0)); result(nil) }
        case "fontDelete":
            withGlasses(result: result) { g in g.fontDelete(id: UInt8(requireInt("id") ?? 0)); result(nil) }
        case "fontDeleteAll":
            withGlasses(result: result) { g in g.fontDeleteAll(); result(nil) }

        // --- Firmware configuration management ---
        case "cfgWrite":
            withGlasses(result: result) { g in
                g.cfgWrite(name: requireString("name") ?? "", version: requireInt("version") ?? 0, password: UInt32(requireInt("password") ?? 0))
                result(nil)
            }
        case "cfgRead":
            withGlasses(result: result) { g in
                g.cfgRead(name: requireString("name") ?? "") { info in
                    self.onMain {
                        result([
                            "version": info.version,
                            "imageCount": info.nbImg,
                            "layoutCount": info.nbLayout,
                            "fontCount": info.nbFont,
                            "pageCount": info.nbPage,
                            "gaugeCount": info.nbGauge,
                        ])
                    }
                }
            }
        case "cfgList":
            withGlasses(result: result) { g in g.cfgList { configs in
                self.onMain {
                    result(configs.map {
                        [
                            "name": $0.name, "size": $0.size, "version": $0.version,
                            "usageCount": $0.usageCnt, "installCount": $0.installCnt, "isSystem": $0.isSystem,
                        ]
                    })
                }
            } }
        case "cfgRename":
            withGlasses(result: result) { g in
                g.cfgRename(oldName: requireString("oldName") ?? "", newName: requireString("newName") ?? "", password: UInt32(requireInt("password") ?? 0))
                result(nil)
            }
        case "cfgDelete":
            withGlasses(result: result) { g in g.cfgDelete(name: requireString("name") ?? ""); result(nil) }
        case "cfgDeleteLessUsed":
            withGlasses(result: result) { g in g.cfgDeleteLessUsed(); result(nil) }
        case "cfgFreeSpace":
            withGlasses(result: result) { g in g.cfgFreeSpace { space in
                self.onMain { result(["totalSize": space.totalSize, "freeSpace": space.freeSpace]) }
            } }
        case "cfgGetNb":
            // Unlike Android (see the Kotlin plugin's comment on this same case), iOS's cfgGetNb
            // is implemented correctly against the real cfgGetNb command id — no known bug here.
            withGlasses(result: result) { g in g.cfgGetNb { n in self.onMain { result(n) } } }
        case "shutdown":
            withGlasses(result: result) { g in g.shutdown(); result(nil) }

        // --- Legacy firmware 1.7-only configuration commands ---
        case "legacyWriteConfig":
            withGlasses(result: result) { g in
                let config = Configuration(number: UInt8(requireInt("number") ?? 0), id: UInt32(requireInt("id") ?? 0))
                g.writeConfigID(configuration: config)
                result(nil)
            }
        case "legacyReadConfig":
            withGlasses(result: result) { g in
                g.readConfigID(number: UInt8(requireInt("number") ?? 0)) { config in
                    self.onMain {
                        result(["id": config.id, "number": config.number, "version": nil, "androidElementCounts": nil])
                    }
                }
            }
        case "legacySetConfig":
            withGlasses(result: result) { g in g.setConfigID(number: UInt8(requireInt("number") ?? 0)); result(nil) }
        case "tdbg":
            // Confirmed: no tdbg() equivalent exists anywhere in ActiveLook/ios-sdk (Android-only
            // legacy diagnostic command).
            result(FlutterError(code: "UNSUPPORTED_ON_PLATFORM", message: "iOS", details: "ActiveLook's iOS SDK has no tdbg() command (Android-only legacy diagnostic)."))

        // --- Statistics commands ---
        case "pixelCount":
            withGlasses(result: result) { g in g.pixelCount { n in self.onMain { result(n) } } }
        case "getChargingCounter":
            withGlasses(result: result) { g in g.getChargingCounter { n in self.onMain { result(n) } } }
        case "getChargingTime":
            withGlasses(result: result) { g in g.getChargingTime { n in self.onMain { result(n) } } }
        case "resetChargingParam":
            withGlasses(result: result) { g in g.resetChargingParam(); result(nil) }

        // --- Widget commands (iOS-only — real native functionality here, unlike Android) ---
        case "widgetOpenGauge":
            withGlasses(result: result) { g in
                g.widgetOpenGauge(
                    size: Self.widgetSize(from: requireString("size") ?? "large"),
                    x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0),
                    value: UInt8(requireInt("value") ?? 0), imgId: UInt8(requireInt("imageId") ?? 0),
                    valueType: Self.widgetValueType(from: requireString("valueType") ?? "text"),
                    unit: requireString("unit") ?? "", shownValue: requireString("shownValue") ?? ""
                )
                result(nil)
            }
        case "widgetRangeGauge":
            withGlasses(result: result) { g in
                g.widgetRangeGauge(
                    size: Self.widgetSize(from: requireString("size") ?? "large"),
                    x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0),
                    value: UInt8(requireInt("value") ?? 0), imgId: UInt8(requireInt("imageId") ?? 0),
                    valueType: Self.widgetValueType(from: requireString("valueType") ?? "text"),
                    unit: requireString("unit") ?? "", shownValue: requireString("shownValue") ?? "",
                    min: requireString("min") ?? "", max: requireString("max") ?? ""
                )
                result(nil)
            }
        case "widgetGaugeZone":
            withGlasses(result: result) { g in
                g.widgetGaugeZone(
                    size: Self.widgetSize(from: requireString("size") ?? "large"),
                    x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0),
                    value: UInt8(requireInt("value") ?? 0), imgId: UInt8(requireInt("imageId") ?? 0),
                    valueType: Self.widgetValueType(from: requireString("valueType") ?? "text"),
                    unit: requireString("unit") ?? "", shownValue: requireString("shownValue") ?? "",
                    chosenZone: UInt8(requireInt("chosenZone") ?? 0), zoneNb: UInt8(requireInt("zoneCount") ?? 0)
                )
                result(nil)
            }
        case "widgetTarget":
            withGlasses(result: result) { g in
                g.widgetTarget(
                    size: Self.widgetSize(from: requireString("size") ?? "large"),
                    x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0),
                    value: UInt8(requireInt("value") ?? 0), imgId: UInt8(requireInt("imageId") ?? 0),
                    valueType: Self.widgetValueType(from: requireString("valueType") ?? "text"),
                    unit: requireString("unit") ?? "", shownValue: requireString("shownValue") ?? "",
                    goal: requireString("goal") ?? ""
                )
                result(nil)
            }
        case "widgetTargetLeft":
            withGlasses(result: result) { g in
                g.widgetTargetLeft(
                    size: Self.widgetSize(from: requireString("size") ?? "large"),
                    x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0),
                    value: UInt8(requireInt("value") ?? 0), imgId: UInt8(requireInt("imageId") ?? 0),
                    valueType: Self.widgetValueType(from: requireString("valueType") ?? "text"),
                    unit: requireString("unit") ?? "", shownValue: requireString("shownValue") ?? "",
                    goal: requireString("goal") ?? ""
                )
                result(nil)
            }
        case "widgetBarChart":
            withGlasses(result: result) { g in
                let zoneValues = (args["zoneValues"] as? [Int])?.map { UInt8($0) } ?? []
                g.widgetBarChart(
                    size: Self.widgetSize(from: requireString("size") ?? "large"),
                    x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0),
                    imgId: UInt8(requireInt("imageId") ?? 0),
                    valueType: Self.widgetValueType(from: requireString("valueType") ?? "text"),
                    unit: requireString("unit") ?? "", shownValue: requireString("shownValue") ?? "",
                    chosenZone: UInt8(requireInt("chosenZone") ?? 0), zoneNb: UInt8(requireInt("zoneCount") ?? 0),
                    zoneNbValue: zoneValues
                )
                result(nil)
            }
        case "widgetData":
            withGlasses(result: result) { g in
                g.widgetData(
                    size: Self.widgetSize(from: requireString("size") ?? "large"),
                    x: Int16(requireInt("x") ?? 0), y: Int16(requireInt("y") ?? 0),
                    imgId: UInt8(requireInt("imageId") ?? 0),
                    valueType: Self.widgetValueType(from: requireString("valueType") ?? "text"),
                    unit: requireString("unit") ?? "", shownValue: requireString("shownValue") ?? ""
                )
                result(nil)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func withGlasses(result: @escaping FlutterResult, _ body: (Glasses) -> Void) {
        guard let g = connectedGlasses else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No glasses connected — call connect() first.", details: nil))
            return
        }
        body(g)
    }

    // 0x6B layoutSaveInColor (ActiveLook_API.md §4.11) — not exposed by ios-sdk's `Glasses`
    // (confirmed by reading Glasses.swift directly: only the grayscale 0x60 layoutSave is
    // wrapped, via `sendCommand(id: .layoutSave, ...)`, and `sendCommand`/the peripheral/
    // characteristic are all private/internal, unreachable from outside the SDK). This builds
    // the same frame ios-sdk's own private `sendCommand` builds and sends it via
    // `loadConfiguration` — ios-sdk's public raw-command escape hatch (`Glasses.swift`,
    // `loadConfiguration(cfg: [String])`, confirmed public: takes hex-string lines and queues
    // them exactly like every typed command does internally).
    //
    // Byte layout: ActiveLook_API.md §3.1's frame, no Query ID, 1-byte Length format — correct
    // for every command this bridge sends this way (layout payloads are 17-126 bytes, nowhere
    // near the ~250-byte threshold where the protocol's 2-byte-Length format would be needed).
    private static func sendRawCommand(_ glasses: Glasses, commandId: UInt8, data: [UInt8]) {
        let fullLength = 5 + data.count
        precondition(fullLength <= 0xFF, "sendRawCommand: frame too large for 1-byte length (\(fullLength) bytes)")
        var frame: [UInt8] = [0xFF, commandId, 0x00, UInt8(fullLength)]
        frame.append(contentsOf: data)
        frame.append(0xAA)
        let hex = frame.map { String(format: "%02X", $0) }.joined()
        glasses.loadConfiguration(cfg: [hex])
    }

    /// `ActiveLook_API.md` §3.1: "All data are in Big Endian" — confirmed against
    /// `com.activelook.activelooksdk.core.CommandData.Int16.asBytes` on the Android side (high
    /// byte first), used here for `rawTextColor`'s x/y fields since ios-sdk's own
    /// `Int16.asUInt8Array` equivalent isn't reachable from outside the SDK module.
    private static func bigEndianInt16(_ value: Int16) -> [UInt8] {
        let bits = UInt16(bitPattern: value)
        return [UInt8(bits >> 8), UInt8(bits & 0xFF)]
    }

    private static func ledState(from name: String) -> LedState {
        switch name {
        case "on": return .on
        case "toggle": return .toggle
        case "blink": return .blink
        default: return .off
        }
    }

    // Maps the Dart-side ActiveLookTextRotation enum name to the native SDK's TextRotation.
    // Order must match ActiveLookTextRotation's declaration in lib/src/activelook_types.dart.
    private static func textRotation(from name: String) -> TextRotation {
        switch name {
        case "bottomRightToLeft": return .bottomRL
        case "bottomLeftToRight": return .bottomLR
        case "leftBottomToTop": return .leftBT
        case "leftTopToBottom": return .leftTB
        case "topLeftToRight": return .topLR
        case "topRightToLeft": return .topRL
        case "rightTopToBottom": return .rightTB
        case "rightBottomToTop": return .rightBT
        default: return .bottomLR
        }
    }

    // Case names and wire values confirmed identical to Android's ImgSaveFormat.
    private static func imgSaveFmt(from name: String) -> ImgSaveFmt {
        switch name {
        case "mono4bpp": return .MONO_4BPP
        case "mono1bpp": return .MONO_1BPP
        case "mono4bppHeatshrink": return .MONO_4BPP_HEATSHRINK
        case "mono4bppHeatshrinkSaveComp": return .MONO_4BPP_HEATSHRINK_SAVE_COMP
        default: return .MONO_4BPP
        }
    }

    private static func imgStreamFmt(from name: String) -> ImgStreamFmt {
        switch name {
        case "mono1bpp": return .MONO_1BPP
        case "mono4bppHeatshrink": return .MONO_4BPP_HEATSHRINK
        default: return .MONO_1BPP
        }
    }

    // iOS-only: WidgetSize/WidgetValueType have no Android equivalent (see plan doc §13).
    private static func widgetSize(from name: String) -> WidgetSize {
        switch name {
        case "large": return .large
        case "thin": return .thin
        case "half": return .half
        default: return .large
        }
    }

    private static func widgetValueType(from name: String) -> WidgetValueType {
        switch name {
        case "text": return .text
        case "number": return .number
        case "durationHms": return .duration_hms
        case "durationHm": return .duration_hm
        case "durationMs": return .duration_ms
        default: return .text
        }
    }

    // MARK: - Event stream handlers

    private class ScanStreamHandler: NSObject, FlutterStreamHandler {
        weak var plugin: ActivelookSdkPlugin?
        init(plugin: ActivelookSdkPlugin) { self.plugin = plugin }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.scanSink = events
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.scanSink = nil
            return nil
        }
    }

    private class ConnectionStateStreamHandler: NSObject, FlutterStreamHandler {
        weak var plugin: ActivelookSdkPlugin?
        init(plugin: ActivelookSdkPlugin) { self.plugin = plugin }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.connectionStateSink = events
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.connectionStateSink = nil
            return nil
        }
    }

    private class BatteryStreamHandler: NSObject, FlutterStreamHandler {
        weak var plugin: ActivelookSdkPlugin?
        init(plugin: ActivelookSdkPlugin) { self.plugin = plugin }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.batterySink = events
            plugin?.connectedGlasses?.subscribeToBatteryLevelNotifications { level in
                self.plugin?.onMain { self.plugin?.batterySink?(level) }
            }
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.batterySink = nil
            return nil
        }
    }

    private class FlowControlStreamHandler: NSObject, FlutterStreamHandler {
        weak var plugin: ActivelookSdkPlugin?
        init(plugin: ActivelookSdkPlugin) { self.plugin = plugin }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.flowControlSink = events
            plugin?.connectedGlasses?.subscribeToFlowControlNotifications { state in
                let name: String
                switch state {
                case .on: name = "bufferOk"
                case .off: name = "bufferFull"
                case .error: name = "cmdError"
                case .overflow: name = "overflow"
                case .missingConfiguration: name = "missingConfigId"
                case .unexpectedDataType: name = "reserved"
                }
                self.plugin?.onMain { self.plugin?.flowControlSink?(name) }
            }
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.flowControlSink = nil
            return nil
        }
    }

    private class SensorTapStreamHandler: NSObject, FlutterStreamHandler {
        weak var plugin: ActivelookSdkPlugin?
        init(plugin: ActivelookSdkPlugin) { self.plugin = plugin }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.sensorTapSink = events
            plugin?.connectedGlasses?.subscribeToSensorInterfaceNotifications {
                self.plugin?.onMain { self.plugin?.sensorTapSink?(nil) }
            }
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.sensorTapSink = nil
            return nil
        }
    }
}
