package com.tonepilot.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * iOS/Android parity: the shared Swift core on Android must reproduce the mix-only fixture recorded
 * on Linux/macOS (Packages/TonePilotCore/Tests/TonePilotCoreTests/Fixtures/pipeline/mix-only.json).
 */
@RunWith(AndroidJUnit4::class)
class CoreParityTest {
    @Test
    fun mixOnlyPipelineMatchesTheSharedFixture() {
        val inst = InstrumentationRegistry.getInstrumentation()
        val out = File(inst.targetContext.cacheDir, "mix-only.json")
        inst.context.assets.open("mix-only.json").use { input -> out.outputStream().use { input.copyTo(it) } }
        val result = NativeBridge.pipelineCheck(out.absolutePath)
        println("PARITY mix-only: $result")
        assertTrue("Android core differs from the shared fixture: $result", JSONObject(result).optBoolean("passed"))
    }
}
