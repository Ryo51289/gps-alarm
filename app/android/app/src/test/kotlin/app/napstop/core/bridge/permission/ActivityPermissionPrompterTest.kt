package app.napstop.core.bridge.permission

import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.FlutterError
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** ActivityPermissionPrompter with function seams (review T21 #2; spec T21 §4.3). */
@OptIn(ExperimentalCoroutinesApi::class)
class ActivityPermissionPrompterTest {
    private val requests = mutableListOf<Pair<List<String>, Int>>()
    private var rationale = true

    private fun prompter() =
        ActivityPermissionPrompter(
            requestPermissions = { permissions, code -> requests += permissions.toList() to code },
            shouldShowRationale = { rationale },
        )

    private val code = ActivityPermissionPrompter.REQUEST_CODE

    @Test
    fun ourResultCompletesThePrompt() =
        runTest {
            val p = prompter()
            assertTrue(p.canPrompt())
            val call = async { p.prompt(listOf("a", "b")) }
            runCurrent()
            assertTrue(p.busy)
            assertEquals(listOf(listOf("a", "b") to code), requests)
            // Another plugin's result: not ours, the prompt keeps waiting.
            assertFalse(p.onRequestPermissionsResult(code + 1))
            runCurrent()
            assertFalse(call.isCompleted)
            assertTrue(p.busy)
            assertTrue(p.onRequestPermissionsResult(code))
            call.await()
            assertFalse(p.busy)
        }

    @Test
    fun secondPromptWhileBusyIsRequestInProgress() =
        runTest {
            val p = prompter()
            val first = async { p.prompt(listOf("a")) }
            runCurrent()
            val second = async { runCatching { p.prompt(listOf("b")) } }
            runCurrent()
            val error = second.await().exceptionOrNull() as FlutterError
            assertEquals(BridgeErrors.REQUEST_IN_PROGRESS, error.code)
            assertEquals(1, requests.size)
            p.onRequestPermissionsResult(code)
            first.await()
            // Free again.
            val third = async { p.prompt(listOf("c")) }
            runCurrent()
            assertEquals(2, requests.size)
            p.onRequestPermissionsResult(code)
            third.await()
        }

    @Test
    fun detachAnswersAPendingPromptAndForgetsTheActivity() =
        runTest {
            val p = prompter()
            val call = async { p.prompt(listOf("a")) }
            runCurrent()
            p.detach()
            call.await()
            assertFalse(p.busy)
            assertFalse(p.canPrompt())
            assertNull(p.rationale("a"))
            assertNull(p.activity)
            // After detach nothing is shown and prompt() returns at once.
            p.prompt(listOf("b"))
            assertEquals(1, requests.size)
            // A late result is still recognised as ours, harmlessly.
            assertTrue(p.onRequestPermissionsResult(code))
        }

    @Test
    fun rationaleComesFromTheActivity() {
        val p = prompter()
        assertEquals(true, p.rationale("a"))
        rationale = false
        assertEquals(false, p.rationale("a"))
    }
}
