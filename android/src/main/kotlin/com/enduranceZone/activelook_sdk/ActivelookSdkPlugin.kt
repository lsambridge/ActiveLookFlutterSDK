package com.enduranceZone.activelook_sdk

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.activelook.activelooksdk.DiscoveredGlasses
import com.activelook.activelooksdk.Glasses
import com.activelook.activelooksdk.Sdk
import com.activelook.activelooksdk.types.Configuration
import com.activelook.activelooksdk.types.DemoPattern
import com.activelook.activelooksdk.types.FlowControlStatus
import com.activelook.activelooksdk.types.FontData
import com.activelook.activelooksdk.types.ImgSaveFormat
import com.activelook.activelooksdk.types.ImgStreamFormat
import com.activelook.activelooksdk.types.LayoutParameters
import com.activelook.activelooksdk.types.LedState
import com.activelook.activelooksdk.types.Rotation
import com.activelook.activelooksdk.types.holdFlushAction
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android bridge to ActiveLook's official `android-sdk` (`Sdk`/`Glasses`/`DiscoveredGlasses`).
 *
 * `Sdk`/`Glasses` callbacks are documented in the SDK as arriving off the main thread
 * (the underlying `BluetoothGattCallback` fires on a Binder thread) — see
 * docs/plan-race-mode-activelook-glasses.md §7.3/§13.3 in the Engyne repo. Every callback
 * here is explicitly posted back to the main thread before touching Flutter channels, since
 * `MethodChannel`/`EventChannel` calls must originate on the platform thread.
 */
class ActivelookSdkPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var scanChannel: EventChannel
    private lateinit var connectionStateChannel: EventChannel
    private lateinit var batteryChannel: EventChannel
    private lateinit var flowControlChannel: EventChannel
    private lateinit var sensorTapChannel: EventChannel

    private val mainHandler = Handler(Looper.getMainLooper())
    private fun onMain(body: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) body() else mainHandler.post(body)
    }

    private lateinit var appContext: android.content.Context
    private var sdk: Sdk? = null
    private var discovered: MutableMap<String, DiscoveredGlasses> = mutableMapOf()
    private var connectedGlasses: Glasses? = null

    private var scanSink: EventChannel.EventSink? = null
    private var connectionStateSink: EventChannel.EventSink? = null
    private var batterySink: EventChannel.EventSink? = null
    private var flowControlSink: EventChannel.EventSink? = null
    private var sensorTapSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        channel = MethodChannel(binding.binaryMessenger, "activelook_sdk")
        channel.setMethodCallHandler(this)

        scanChannel = EventChannel(binding.binaryMessenger, "activelook_sdk/scan")
        scanChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { scanSink = events }
            override fun onCancel(arguments: Any?) { scanSink = null }
        })

        connectionStateChannel = EventChannel(binding.binaryMessenger, "activelook_sdk/connection_state")
        connectionStateChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { connectionStateSink = events }
            override fun onCancel(arguments: Any?) { connectionStateSink = null }
        })

        batteryChannel = EventChannel(binding.binaryMessenger, "activelook_sdk/battery")
        batteryChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                batterySink = events
                connectedGlasses?.subscribeToBatteryLevelNotifications { level ->
                    onMain { batterySink?.success(level) }
                }
            }
            override fun onCancel(arguments: Any?) { batterySink = null }
        })

        flowControlChannel = EventChannel(binding.binaryMessenger, "activelook_sdk/flow_control")
        flowControlChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                flowControlSink = events
                connectedGlasses?.subscribeToFlowControlNotifications { status ->
                    onMain { flowControlSink?.success(flowControlStatusName(status)) }
                }
            }
            override fun onCancel(arguments: Any?) { flowControlSink = null }
        })

        sensorTapChannel = EventChannel(binding.binaryMessenger, "activelook_sdk/sensor_tap")
        sensorTapChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sensorTapSink = events
                connectedGlasses?.subscribeToSensorInterfaceNotifications {
                    onMain { sensorTapSink?.success(null) }
                }
            }
            override fun onCancel(arguments: Any?) { sensorTapSink = null }
        })
    }

    private fun ensureSdk(): Sdk {
        return sdk ?: Sdk.init(
            appContext,
            { }, // onUpdateStart
            { pair -> pair.second.run() }, // onUpdateAvailableCallback: always accept firmware updates
            { }, // onUpdateProgress
            { }, // onUpdateSuccess
            { }, // onUpdateError
        ).also { sdk = it }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startScan" -> {
                discovered.clear()
                ensureSdk().startScan { dg ->
                    onMain {
                        discovered[dg.address] = dg
                        scanSink?.success(
                            mapOf("id" to dg.address, "name" to dg.name, "manufacturer" to dg.manufacturer),
                        )
                    }
                }
                result.success(null)
            }
            "stopScan" -> {
                ensureSdk().stopScan()
                result.success(null)
            }
            "connect" -> {
                val id = call.argument<String>("id")
                val dg = discovered[id]
                if (dg == null) {
                    result.error("NOT_FOUND", "No discovered glasses with id $id — scan first.", null)
                    return
                }
                onMain { connectionStateSink?.success("connecting") }
                dg.connect(
                    { glasses ->
                        onMain {
                            connectedGlasses = glasses
                            glasses.setOnDisconnected {
                                onMain {
                                    connectedGlasses = null
                                    connectionStateSink?.success("disconnected")
                                }
                            }
                            connectionStateSink?.success("connected")
                        }
                    },
                    { _ ->
                        onMain { connectionStateSink?.success("disconnected") }
                    },
                    { _ ->
                        onMain {
                            connectedGlasses = null
                            connectionStateSink?.success("disconnected")
                        }
                    },
                )
                result.success(null)
            }
            "disconnect" -> {
                connectedGlasses?.disconnect()
                result.success(null)
            }
            "getDeviceInformation" -> {
                val di = connectedGlasses?.deviceInformation
                result.success(
                    mapOf(
                        "manufacturerName" to di?.manufacturerName,
                        "modelNumber" to di?.modelNumber,
                        "serialNumber" to di?.serialNumber,
                        "hardwareVersion" to di?.hardwareVersion,
                        "firmwareVersion" to di?.firmwareVersion,
                        "softwareVersion" to di?.softwareVersion,
                    ),
                )
            }
            "getBatteryLevel" -> withGlasses(result) { g ->
                g.battery { level -> onMain { result.success(level) } }
            }
            "power" -> withGlasses(result) { g -> g.power(call.argument<Boolean>("on") == true); result.success(null) }
            "clear" -> withGlasses(result) { g -> g.clear(); result.success(null) }
            "grey" -> withGlasses(result) { g -> g.grey(call.requireInt("level").toByte()); result.success(null) }
            "led" -> withGlasses(result) { g ->
                g.led(LedState.valueOf(call.requireString("state").uppercase()))
                result.success(null)
            }
            "luma" -> withGlasses(result) { g -> g.luma(call.requireInt("level").toByte()); result.success(null) }
            "sensor" -> withGlasses(result) { g -> g.sensor(call.argument<Boolean>("enable") == true); result.success(null) }
            "gesture" -> withGlasses(result) { g -> g.gesture(call.argument<Boolean>("enable") == true); result.success(null) }
            "als" -> withGlasses(result) { g -> g.als(call.argument<Boolean>("enable") == true); result.success(null) }
            "shift" -> withGlasses(result) { g ->
                g.shift(call.requireInt("x").toShort(), call.requireInt("y").toShort())
                result.success(null)
            }
            "holdFlush" -> withGlasses(result) { g ->
                val action = if (call.requireString("action") == "hold") holdFlushAction.HOLD else holdFlushAction.FLUSH
                g.holdFlush(action)
                result.success(null)
            }
            "color" -> withGlasses(result) { g -> g.color(call.requireInt("level").toByte()); result.success(null) }
            "point" -> withGlasses(result) { g ->
                g.point(call.requireInt("x").toShort(), call.requireInt("y").toShort())
                result.success(null)
            }
            "line" -> withGlasses(result) { g ->
                g.line(
                    call.requireInt("x1").toShort(), call.requireInt("y1").toShort(),
                    call.requireInt("x2").toShort(), call.requireInt("y2").toShort(),
                )
                result.success(null)
            }
            "rect" -> withGlasses(result) { g ->
                g.rect(
                    call.requireInt("x1").toShort(), call.requireInt("y1").toShort(),
                    call.requireInt("x2").toShort(), call.requireInt("y2").toShort(),
                )
                result.success(null)
            }
            "rectFilled" -> withGlasses(result) { g ->
                g.rectf(
                    call.requireInt("x1").toShort(), call.requireInt("y1").toShort(),
                    call.requireInt("x2").toShort(), call.requireInt("y2").toShort(),
                )
                result.success(null)
            }
            "circle" -> withGlasses(result) { g ->
                g.circ(call.requireInt("x").toShort(), call.requireInt("y").toShort(), call.requireInt("radius").toByte())
                result.success(null)
            }
            "circleFilled" -> withGlasses(result) { g ->
                g.circf(call.requireInt("x").toShort(), call.requireInt("y").toShort(), call.requireInt("radius").toByte())
                result.success(null)
            }
            "text" -> withGlasses(result) { g ->
                g.txt(
                    call.requireInt("x").toShort(),
                    call.requireInt("y").toShort(),
                    rotationFromDartName(call.requireString("rotation")),
                    call.requireInt("fontSize").toByte(),
                    call.requireInt("color").toByte(),
                    call.requireString("text"),
                )
                result.success(null)
            }
            "polyline" -> withGlasses(result) { g ->
                val xys = (call.argument<List<Int>>("xyPairs") ?: emptyList()).map { it.toShort() }.toShortArray()
                g.polyline(call.requireInt("thickness").toByte(), xys)
                result.success(null)
            }
            "layoutSave" -> withGlasses(result) { g ->
                val layout = LayoutParameters(
                    call.requireInt("id").toByte(),
                    call.requireInt("x").toShort(),
                    call.requireInt("y").toByte(),
                    call.requireInt("width").toShort(),
                    call.requireInt("height").toByte(),
                    call.requireInt("foregroundColor").toByte(),
                    call.requireInt("backgroundColor").toByte(),
                    call.requireInt("font").toByte(),
                    call.argument<Boolean>("textValid") ?: true,
                    call.requireInt("textX").toShort(),
                    call.requireInt("textY").toByte(),
                    rotationFromDartName(call.requireString("textRotation")),
                    call.argument<Boolean>("textOpacity") ?: true,
                )
                g.layoutSave(layout)
                result.success(null)
            }
            "layoutDisplay" -> withGlasses(result) { g ->
                g.layoutDisplay(call.requireInt("id").toByte(), call.requireString("text"))
                result.success(null)
            }
            "layoutDisplayExtended" -> withGlasses(result) { g ->
                g.layoutDisplayExtended(
                    call.requireInt("id").toByte(),
                    call.requireInt("x").toShort(),
                    call.requireInt("y").toByte(),
                    call.requireString("text"),
                )
                result.success(null)
            }
            "layoutClear" -> withGlasses(result) { g -> g.layoutClear(call.requireInt("id").toByte()); result.success(null) }
            "layoutClearAndDisplay" -> withGlasses(result) { g ->
                g.layoutClearAndDisplay(call.requireInt("id").toByte(), call.requireString("text"))
                result.success(null)
            }
            "layoutDelete" -> withGlasses(result) { g -> g.layoutDelete(call.requireInt("id").toByte()); result.success(null) }
            "layoutList" -> withGlasses(result) { g ->
                g.layoutList { ids -> onMain { result.success(ids) } }
            }
            "gaugeSave" -> withGlasses(result) { g ->
                g.gaugeSave(
                    call.requireInt("id").toByte(),
                    call.requireInt("x").toShort(),
                    call.requireInt("y").toShort(),
                    call.requireInt("externalRadius").toChar(),
                    call.requireInt("internalRadius").toChar(),
                    call.requireInt("startAngle").toByte(),
                    call.requireInt("endAngle").toByte(),
                    call.argument<Boolean>("clockwise") ?: true,
                )
                result.success(null)
            }
            "gaugeDisplay" -> withGlasses(result) { g ->
                g.gaugeDisplay(call.requireInt("id").toByte(), call.requireInt("value").toByte())
                result.success(null)
            }
            "gaugeDelete" -> withGlasses(result) { g -> g.gaugeDelete(call.requireInt("id").toByte()); result.success(null) }
            "pageSave" -> withGlasses(result) { g ->
                val layoutIds = (call.argument<List<Int>>("layoutIds") ?: emptyList()).map { it.toByte() }.toByteArray()
                val xs = (call.argument<List<Int>>("xs") ?: emptyList()).map { it.toShort() }.toShortArray()
                val ys = (call.argument<List<Int>>("ys") ?: emptyList()).map { it.toByte() }.toByteArray()
                g.pageSave(call.requireInt("id").toByte(), layoutIds, xs, ys)
                result.success(null)
            }
            "pageDisplay" -> withGlasses(result) { g ->
                val texts = (call.argument<List<String>>("texts") ?: emptyList()).toTypedArray()
                g.pageDisplay(call.requireInt("id").toByte(), texts)
                result.success(null)
            }
            "pageClear" -> withGlasses(result) { g -> g.pageClear(call.requireInt("id").toByte()); result.success(null) }
            "pageDelete" -> withGlasses(result) { g -> g.pageDelete(call.requireInt("id").toByte()); result.success(null) }
            "animDisplay" -> withGlasses(result) { g ->
                g.animDisplay(
                    call.requireInt("handlerId").toByte(),
                    call.requireInt("animId").toByte(),
                    call.requireInt("frameDelayMs").toShort(),
                    call.requireInt("repeatCount").toByte(),
                    call.requireInt("x").toShort(),
                    call.requireInt("y").toShort(),
                )
                result.success(null)
            }
            "animClear" -> withGlasses(result) { g -> g.animClear(call.requireInt("handlerId").toByte()); result.success(null) }
            "configSet" -> withGlasses(result) { g -> g.cfgSet(call.requireString("name")); result.success(null) }
            "demo" -> withGlasses(result) { g -> g.demo(DemoPattern.FILL); result.success(null) }

            // --- Image/bitmap commands ---
            "imgList" -> withGlasses(result) { g ->
                g.imgList { images ->
                    onMain {
                        result.success(
                            images.map { mapOf("id" to it.id, "width" to it.width, "height" to it.height) },
                        )
                    }
                }
            }
            "imgSave" -> withGlasses(result) { g ->
                val bitmap = decodePng(call.argument<ByteArray>("pngBytes"))
                if (bitmap == null) {
                    result.error("BAD_IMAGE", "Could not decode pngBytes as an image.", null)
                    return@withGlasses
                }
                g.imgSave(call.requireInt("id").toByte(), bitmap, imgSaveFormatFromDartName(call.requireString("format")))
                result.success(null)
            }
            "imgDisplay" -> withGlasses(result) { g ->
                g.imgDisplay(call.requireInt("id").toByte(), call.requireInt("x").toShort(), call.requireInt("y").toShort())
                result.success(null)
            }
            "imgDelete" -> withGlasses(result) { g -> g.imgDelete(call.requireInt("id").toByte()); result.success(null) }
            "imgDeleteAll" -> withGlasses(result) { g -> g.imgDeleteAll(); result.success(null) }
            "imgStream" -> withGlasses(result) { g ->
                val bitmap = decodePng(call.argument<ByteArray>("pngBytes"))
                if (bitmap == null) {
                    result.error("BAD_IMAGE", "Could not decode pngBytes as an image.", null)
                    return@withGlasses
                }
                val format = imgStreamFormatFromDartName(call.requireString("format"))
                g.imgStream(bitmap, format, call.requireInt("x").toShort(), call.requireInt("y").toShort())
                result.success(null)
            }

            // --- Font commands ---
            "fontList" -> withGlasses(result) { g ->
                g.fontList { fonts ->
                    onMain { result.success(fonts.map { mapOf("id" to it.id, "height" to it.height) }) }
                }
            }
            "fontSave" -> withGlasses(result) { g ->
                val bytes = call.argument<ByteArray>("fontBytes") ?: ByteArray(0)
                g.fontSave(call.requireInt("id").toByte(), FontData(bytes))
                result.success(null)
            }
            "fontSelect" -> withGlasses(result) { g -> g.fontSelect(call.requireInt("id").toByte()); result.success(null) }
            "fontDelete" -> withGlasses(result) { g -> g.fontDelete(call.requireInt("id").toByte()); result.success(null) }
            "fontDeleteAll" -> withGlasses(result) { g -> g.fontDeleteAll(); result.success(null) }

            // --- Firmware configuration management ---
            "cfgWrite" -> withGlasses(result) { g ->
                g.cfgWrite(call.requireString("name"), call.requireInt("version"), call.requireInt("password"))
                result.success(null)
            }
            "cfgRead" -> withGlasses(result) { g ->
                g.cfgRead(call.requireString("name")) { info ->
                    onMain {
                        result.success(
                            mapOf(
                                "version" to info.version,
                                "imageCount" to info.nbImg,
                                "layoutCount" to info.nbLayout,
                                "fontCount" to info.nbFont,
                                "pageCount" to info.nbPage,
                                "gaugeCount" to info.nbGauge,
                            ),
                        )
                    }
                }
            }
            "cfgList" -> withGlasses(result) { g ->
                g.cfgList { configs ->
                    onMain {
                        result.success(
                            configs.map {
                                mapOf(
                                    "name" to it.name,
                                    "size" to it.size,
                                    "version" to it.version,
                                    "usageCount" to it.usageCount,
                                    "installCount" to it.installCount,
                                    "isSystem" to it.isSystem,
                                )
                            },
                        )
                    }
                }
            }
            "cfgRename" -> withGlasses(result) { g ->
                g.cfgRename(call.requireString("oldName"), call.requireString("newName"), call.requireInt("password"))
                result.success(null)
            }
            "cfgDelete" -> withGlasses(result) { g -> g.cfgDelete(call.requireString("name")); result.success(null) }
            "cfgDeleteLessUsed" -> withGlasses(result) { g -> g.cfgDeleteLessUsed(); result.success(null) }
            "cfgFreeSpace" -> withGlasses(result) { g ->
                g.cfgFreeSpace { space ->
                    onMain { result.success(mapOf("totalSize" to space.totalSize, "freeSpace" to space.freeSpace)) }
                }
            }
            "cfgGetNb" -> withGlasses(result) { g ->
                // NOTE: Android's own SDK has a confirmed bug where cfgGetNb's implementation sends
                // the wrong command ID internally (ID_getChargingTime instead of ID_cfgGetNb) — see
                // docs/plan-race-mode-activelook-glasses.md §13 in the Engyne repo. We call the SDK's
                // public cfgGetNb() as-is rather than routing around it, since bypassing the public
                // API to work around an upstream bug is out of scope for a wrapper aimed at being
                // handed back to ActiveLook; this is flagged here and in README.md instead.
                g.cfgGetNb { count -> onMain { result.success(count) } }
            }
            "shutdown" -> withGlasses(result) { g -> g.shutdown(); result.success(null) }

            // --- Legacy firmware 1.7-only configuration commands ---
            "legacyWriteConfig" -> withGlasses(result) { g ->
                // Configuration's only public constructor parses a raw response payload
                // (id: 1 byte, version: 4 bytes, nbImg/nbLayout/nbFont: 1 byte each) — there is no
                // field-based constructor. Its own toBytes() (what WConfigID actually sends) only
                // re-encodes id + version + 3 zero bytes, ignoring nbImg/nbLayout/nbFont entirely,
                // so we build the minimal 8-byte payload toBytes() would read back out.
                val id = call.requireInt("id")
                val version = call.argument<Int>("version") ?: 0
                val bytes = byteArrayOf(
                    id.toByte(),
                    (version shr 24).toByte(), (version shr 16).toByte(),
                    (version shr 8).toByte(), version.toByte(),
                    0x00, 0x00, 0x00,
                )
                g.WConfigID(Configuration(bytes))
                result.success(null)
            }
            "legacyReadConfig" -> withGlasses(result) { g ->
                g.RConfigID(call.requireInt("number").toByte()) { config ->
                    onMain {
                        result.success(
                            mapOf(
                                "id" to config.id,
                                "version" to config.version.toInt(),
                                "number" to null,
                                "androidElementCounts" to mapOf(
                                    "version" to config.version.toInt(),
                                    "imageCount" to config.nbImg,
                                    "layoutCount" to config.nbLayout,
                                    "fontCount" to config.nbFont,
                                ),
                            ),
                        )
                    }
                }
            }
            "legacySetConfig" -> withGlasses(result) { g -> g.SetConfigID(call.requireInt("number").toByte()); result.success(null) }
            "tdbg" -> withGlasses(result) { g -> g.tdbg(); result.success(null) }

            // --- Statistics commands ---
            "pixelCount" -> withGlasses(result) { g -> g.pixelCount { n -> onMain { result.success(n.toInt()) } } }
            "getChargingCounter" -> withGlasses(result) { g ->
                g.getChargingCounter { n -> onMain { result.success(n.toInt()) } }
            }
            "getChargingTime" -> withGlasses(result) { g ->
                g.getChargingTime { n -> onMain { result.success(n.toInt()) } }
            }
            "resetChargingParam" -> withGlasses(result) { g -> g.resetChargingParam(); result.success(null) }

            // --- Widget commands: confirmed iOS-only, zero equivalent in ActiveLook's Android SDK ---
            "widgetOpenGauge", "widgetRangeGauge", "widgetGaugeZone", "widgetTarget",
            "widgetTargetLeft", "widgetBarChart", "widgetData",
            -> result.error(
                "UNSUPPORTED_ON_PLATFORM",
                "Android",
                "ActiveLook's Android SDK has no widget commands (iOS-only feature).",
            )

            else -> result.notImplemented()
        }
    }

    private inline fun withGlasses(result: Result, body: (Glasses) -> Unit) {
        val g = connectedGlasses
        if (g == null) {
            result.error("NOT_CONNECTED", "No glasses connected — call connect() first.", null)
            return
        }
        body(g)
    }

    // Android's SDK only forwards these 4 error states to subscribeToFlowControlNotifications;
    // buffer-ok/buffer-full ("on"/"off" internally) are handled purely inside the SDK's own send
    // queue and never reach this callback — see ActiveLookFlowControlStatus's doc comment on the
    // Dart side for the confirmed platform divergence vs. iOS.
    private fun flowControlStatusName(status: FlowControlStatus): String = when (status) {
        FlowControlStatus.CMD_ERROR -> "cmdError"
        FlowControlStatus.OVERFLOW -> "overflow"
        FlowControlStatus.MISSING_CONFIG_ID -> "missingConfigId"
        FlowControlStatus.RESERVED -> "reserved"
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scanChannel.setStreamHandler(null)
        connectionStateChannel.setStreamHandler(null)
        batteryChannel.setStreamHandler(null)
        flowControlChannel.setStreamHandler(null)
        sensorTapChannel.setStreamHandler(null)
    }
}

private fun MethodCall.requireInt(key: String): Int =
    this.argument<Int>(key) ?: throw IllegalArgumentException("Missing required argument: $key")

private fun MethodCall.requireString(key: String): String =
    this.argument<String>(key) ?: throw IllegalArgumentException("Missing required argument: $key")

// Maps the Dart-side ActiveLookTextRotation enum name (e.g. "bottomLeftToRight") to the
// native SDK's Rotation enum (e.g. Rotation.BOTTOM_LR). Order here must match the order declared
// in lib/src/activelook_types.dart's ActiveLookTextRotation.
private val dartRotationOrder = listOf(
    Rotation.BOTTOM_RL, Rotation.BOTTOM_LR,
    Rotation.LEFT_BT, Rotation.LEFT_TB,
    Rotation.TOP_LR, Rotation.TOP_RL,
    Rotation.RIGHT_TB, Rotation.RIGHT_BT,
)
private val dartRotationNames = listOf(
    "bottomRightToLeft", "bottomLeftToRight",
    "leftBottomToTop", "leftTopToBottom",
    "topLeftToRight", "topRightToLeft",
    "rightTopToBottom", "rightBottomToTop",
)

private fun rotationFromDartName(name: String): Rotation =
    dartRotationOrder[dartRotationNames.indexOf(name).coerceAtLeast(0)]

private fun decodePng(bytes: ByteArray?): android.graphics.Bitmap? {
    if (bytes == null) return null
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
}

// Maps the Dart-side ActiveLookImageFormat enum name to the native SDK's ImgSaveFormat.
// Case names/wire values are confirmed identical to iOS's ImgSaveFmt.
private fun imgSaveFormatFromDartName(name: String): ImgSaveFormat = when (name) {
    "mono4bpp" -> ImgSaveFormat.MONO_4BPP
    "mono1bpp" -> ImgSaveFormat.MONO_1BPP
    "mono4bppHeatshrink" -> ImgSaveFormat.MONO_4BPP_HEATSHRINK
    "mono4bppHeatshrinkSaveComp" -> ImgSaveFormat.MONO_4BPP_HEATSHRINK_SAVE_COMP
    else -> ImgSaveFormat.MONO_4BPP
}

// Maps the Dart-side ActiveLookImageStreamFormat enum name to the native SDK's ImgStreamFormat.
private fun imgStreamFormatFromDartName(name: String): ImgStreamFormat = when (name) {
    "mono1bpp" -> ImgStreamFormat.MONO_1BPP
    "mono4bppHeatshrink" -> ImgStreamFormat.MONO_4BPP_HEATSHRINK
    else -> ImgStreamFormat.MONO_1BPP
}
