package com.enduranceZone.activelook_sdk

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/*
 * Runs under Robolectric because the plugin's onMain() helper touches
 * android.os.Looper.getMainLooper(), which a plain JVM unit test does not mock.
 *
 * Run via `./gradlew testDebugUnitTest` in `example/android/`, or from an IDE.
 */

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
internal class ActivelookSdkPluginTest {
    @Test
    fun onMethodCall_unknownMethod_isNotImplemented() {
        val plugin = ActivelookSdkPlugin()

        val call = MethodCall("notARealMethod", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).notImplemented()
    }

    @Test
    fun onMethodCall_drawCommandWithoutConnectedGlasses_errorsNotConnected() {
        val plugin = ActivelookSdkPlugin()

        val call = MethodCall("clear", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("NOT_CONNECTED"),
            Mockito.anyString(),
            Mockito.isNull(),
        )
    }
}
