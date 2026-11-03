package app.napstop.core.bridge.permission

import android.content.ActivityNotFoundException
import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.FlutterError
import app.napstop.core.bridge.LocationAccessMsg
import app.napstop.core.bridge.PermissionKindMsg
import app.napstop.core.bridge.PermissionStateMsg
import app.napstop.core.bridge.SettingsTargetMsg
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** K06: PermissionHostApiImpl with fake sources, flags, prompter and launcher (spec T21 §4). */
@OptIn(ExperimentalCoroutinesApi::class)
class PermissionHostApiImplTest {
    private val fakes = PermissionFakes()
    private val api = fakes.impl()

    private suspend fun requestError(kind: PermissionKindMsg): FlutterError {
        try {
            api.request(kind)
        } catch (e: FlutterError) {
            return e
        }
        fail("no error")
        error("unreachable")
    }

    @Test
    fun k06aRequestWhilePromptPendingIsRequestInProgress() =
        runTest {
            fakes.sources.granted.clear()
            fakes.sources.notificationsOn = false
            fakes.prompter.gate = CompletableDeferred()
            val first = async { api.request(PermissionKindMsg.LOCATION) }
            runCurrent()
            assertTrue(fakes.prompter.busy)
            assertEquals(BridgeErrors.REQUEST_IN_PROGRESS, requestError(PermissionKindMsg.NOTIFICATIONS).code)
            fakes.prompter.gate!!.complete(Unit)
            first.await()
            assertEquals(1, fakes.prompter.prompts.size)
        }

    @Test
    fun k06aTwoInterleavedRequestsBeforeAnyDialog() =
        runTest {
            // Review T21 #1: B arrives while A is still suspended reading the flags.
            fakes.sources.granted.clear()
            fakes.sources.notificationsOn = false
            fakes.flags.suspendOnRead = true
            fakes.prompter.gate = CompletableDeferred()
            val a = async { api.request(PermissionKindMsg.LOCATION) }
            val b = async { runCatching { api.request(PermissionKindMsg.NOTIFICATIONS) } }
            // Not prompting either: still answers with the status.
            val c = async { api.request(PermissionKindMsg.ALARM_KIT) }
            runCurrent()
            val error = b.await().exceptionOrNull() as FlutterError
            assertEquals(BridgeErrors.REQUEST_IN_PROGRESS, error.code)
            assertEquals(PermissionStateMsg.NOT_APPLICABLE, c.await().alarmKit)
            // B never showed a dialog, so it must not count as asked.
            assertFalse(fakes.flags.flags.notificationsRequested)
            assertFalse(fakes.log.contains("markNotifications"))
            fakes.prompter.gate!!.complete(Unit)
            a.await()
            assertEquals(listOf("markLocation", "prompt"), fakes.log)
            assertEquals(1, fakes.prompter.prompts.size)
            // Released: the next request may prompt.
            api.request(PermissionKindMsg.NOTIFICATIONS)
            assertEquals(2, fakes.prompter.prompts.size)
            assertTrue(fakes.flags.flags.notificationsRequested)
        }

    @Test
    fun k06aClaimIsReleasedWhenTheRequestFails() =
        runTest {
            fakes.sources.granted.clear()
            fakes.sources.throwing += "isGranted"
            try {
                api.request(PermissionKindMsg.LOCATION)
                fail("no error")
            } catch (e: FlutterError) {
                assertEquals(BridgeErrors.INTERNAL, e.code)
            }
            fakes.sources.throwing.clear()
            api.request(PermissionKindMsg.LOCATION)
            assertEquals(1, fakes.prompter.prompts.size)
        }

    @Test
    fun k06bNoActivityReturnsStatusWithoutPromptingOrFlags() =
        runTest {
            fakes.sources.granted.clear()
            fakes.prompter.attached = false
            val status = api.request(PermissionKindMsg.LOCATION)
            assertEquals(LocationAccessMsg.NOT_DETERMINED, status.location)
            assertTrue(fakes.prompter.prompts.isEmpty())
            assertEquals(emptyList<String>(), fakes.log)
            assertEquals(PermissionFlags.Flags.NONE, fakes.flags.flags)
        }

    @Test
    fun k06cNoLocationMarksTheFlagBeforePromptingAndReadsAgain() =
        runTest {
            fakes.sources.granted.clear()
            fakes.prompter.answer = { fakes.sources.granted += setOf(PermissionMapping.FINE, PermissionMapping.COARSE) }
            val status = api.request(PermissionKindMsg.LOCATION)
            assertEquals(listOf("markLocation", "prompt"), fakes.log)
            assertTrue(fakes.flags.flags.locationRequested)
            assertEquals(listOf(listOf(PermissionMapping.FINE, PermissionMapping.COARSE)), fakes.prompter.prompts)
            assertEquals(LocationAccessMsg.WHILE_IN_USE, status.location)
            assertEquals(PermissionStateMsg.GRANTED, status.precise)
        }

    @Test
    fun k06cDeniedTwiceEndsAsDenied() =
        runTest {
            fakes.sources.granted.clear()
            fakes.sources.rationale = false
            val status = api.request(PermissionKindMsg.LOCATION)
            assertEquals(LocationAccessMsg.DENIED, status.location)
        }

    @Test
    fun k06dCoarseOnlyCountsAPreciseAttempt() =
        runTest {
            fakes.sources.granted.remove(PermissionMapping.FINE)
            val status = api.request(PermissionKindMsg.LOCATION)
            assertEquals(listOf("markLocation", "countPrecise", "prompt"), fakes.log)
            assertEquals(1, fakes.flags.flags.preciseUpgradeAttempts)
            // Still approximate after the prompt: Settings only.
            assertEquals(PermissionStateMsg.DENIED, status.precise)
        }

    @Test
    fun k06eFineAgainResetsTheAttempts() =
        runTest {
            fakes.flags.flags = PermissionFlags.Flags(true, false, 1)
            val status = api.status()
            assertEquals(listOf("resetPrecise"), fakes.log)
            assertEquals(PermissionStateMsg.GRANTED, status.precise)
            fakes.log.clear()
            api.status()
            assertEquals(emptyList<String>(), fakes.log)
        }

    @Test
    fun k06fAlarmKitAndFineLocationDoNotPrompt() =
        runTest {
            val status = api.request(PermissionKindMsg.ALARM_KIT)
            assertEquals(PermissionStateMsg.NOT_APPLICABLE, status.alarmKit)
            api.request(PermissionKindMsg.LOCATION)
            api.request(PermissionKindMsg.NOTIFICATIONS)
            assertTrue(fakes.prompter.prompts.isEmpty())
        }

    @Test
    fun k06gIsGrantedThrowingIsInternal() =
        runTest {
            fakes.sources.throwing += "isGranted"
            for (call in listOf<suspend () -> Unit>({ api.status() }, { api.request(PermissionKindMsg.LOCATION) })) {
                try {
                    call()
                    fail("no error")
                } catch (e: FlutterError) {
                    assertEquals(BridgeErrors.INTERNAL, e.code)
                    assertEquals("IllegalStateException", e.message)
                }
            }
        }

    @Test
    fun k06gOtherItemsFailSoftly() =
        runTest {
            fakes.sources.throwing +=
                setOf(
                    "rationale",
                    "locationEnabled",
                    "notificationsEnabled",
                    "canUseFullScreenIntent",
                    "canScheduleExactAlarms",
                    "ignoringBatteryOptimizations",
                )
            fakes.sources.battery = true
            fakes.flags.readError = IllegalStateException("disk")
            val status = api.status()
            // Blocking item reads as on; warning items as denied.
            assertTrue(status.locationServicesEnabled)
            assertEquals(PermissionStateMsg.DENIED, status.notifications)
            assertEquals(PermissionStateMsg.DENIED, status.fullScreenIntent)
            assertEquals(PermissionStateMsg.DENIED, status.exactAlarm)
            assertEquals(PermissionStateMsg.DENIED, status.batteryOptimizationIgnored)
            assertEquals(LocationAccessMsg.WHILE_IN_USE, status.location)
            assertTrue(fakes.warnings.contains("permission flags: IllegalStateException"))
            assertTrue(fakes.warnings.contains("permission location services: IllegalStateException"))
            assertFalse(fakes.warnings.any { it.contains("21.0") || it.contains("disk") })
        }

    @Test
    fun k06hOpenSettingsTriesTheNextCandidate() {
        fakes.launchFailures["android.settings.APP_NOTIFICATION_SETTINGS"] = { ActivityNotFoundException() }
        assertTrue(api.openSettings(SettingsTargetMsg.NOTIFICATIONS))
        assertEquals(
            listOf("android.settings.APP_NOTIFICATION_SETTINGS", "android.settings.APPLICATION_DETAILS_SETTINGS"),
            fakes.started.map { it.action },
        )
    }

    @Test
    fun k06hOpenSettingsAllCandidatesFail() {
        fakes.launchFailures["android.settings.APP_NOTIFICATION_SETTINGS"] = { ActivityNotFoundException() }
        fakes.launchFailures["android.settings.APPLICATION_DETAILS_SETTINGS"] = { SecurityException() }
        assertFalse(api.openSettings(SettingsTargetMsg.NOTIFICATIONS))
        assertEquals(2, fakes.started.size)
    }

    @Test
    fun k06hFullScreenIntentBelow34IsNotApplicable() {
        fakes.sources.sdk = 33
        assertFalse(api.openSettings(SettingsTargetMsg.FULL_SCREEN_INTENT))
        assertTrue(fakes.started.isEmpty())
        fakes.sources.sdk = 34
        assertTrue(api.openSettings(SettingsTargetMsg.FULL_SCREEN_INTENT))
    }

    @Test
    fun backgroundCheckValidatesBeforeScheduling() =
        runTest {
            try {
                api.startBackgroundCheck(1_000L)
                fail("accepted")
            } catch (e: FlutterError) {
                assertEquals(BridgeErrors.INVALID_CONFIG, e.code)
            }
            assertTrue(fakes.log.isEmpty())
            val msg = api.startBackgroundCheck(30_000L)
            assertEquals(31_000L, msg.dueAtMs)
            assertEquals(msg, api.backgroundCheck())
            api.cancelBackgroundCheck()
            assertEquals(null, api.backgroundCheck())
            assertEquals(listOf("start 30000", "cancel"), fakes.log)
        }
}
