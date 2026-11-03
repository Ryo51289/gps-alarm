package app.napstop.core.bridge.permission

import app.napstop.core.bridge.BackgroundCheckMsg
import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.BridgeGuard
import app.napstop.core.bridge.DeviceInfoMsg
import app.napstop.core.bridge.DeviceStatusMsg
import app.napstop.core.bridge.FlutterError
import app.napstop.core.bridge.MapsConfigMsg
import app.napstop.core.bridge.PermissionHostApi
import app.napstop.core.bridge.PermissionKindMsg
import app.napstop.core.bridge.PermissionStatusMsg
import app.napstop.core.bridge.SettingsTargetMsg
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException

/**
 * Real `PermissionHostApi` on Android (spec T21 §4, §5). Every method runs in
 * [BridgeGuard.call]: Dart only ever sees an error code and a class name (T14 F3).
 * Logs ([warn]) carry an item name and an exception class, never a value.
 *
 * Threading: Pigeon calls arrive on the main thread; flags and the background check
 * switch to their IO dispatcher, everything else is a cheap system-service read.
 */
class PermissionHostApiImpl(
    private val sources: PermissionSources,
    private val flags: PermissionFlags,
    private val prompter: PermissionPrompter,
    private val settings: SettingsLauncher,
    private val readDeviceInfo: () -> DeviceInfoMsg,
    private val readDeviceStatus: () -> DeviceStatusMsg,
    private val readMapsConfig: () -> MapsConfigMsg,
    private val readDistances: suspend (List<Double>, Long) -> List<Double>?,
    private val backgroundChecks: BackgroundChecks,
    private val warn: (String) -> Unit,
) : PermissionHostApi {
    /**
     * Claimed by the one request() that may show a dialog, before its first suspension
     * (review T21 #1): a second call interleaved while the first waits on the flags would
     * otherwise pass the busy check and mark "asked" for a dialog that never shows.
     */
    private val requesting = AtomicBoolean(false)

    override suspend fun status(): PermissionStatusMsg = BridgeGuard.call { statusOf(snapshot()) }

    override suspend fun request(kind: PermissionKindMsg): PermissionStatusMsg =
        BridgeGuard.call {
            // Claimed synchronously, before snapshot() suspends.
            val owner = !prompter.busy && requesting.compareAndSet(false, true)
            try {
                val before = snapshot()
                val plan = PermissionMapping.plan(kind, before)
                if (plan !is RequestPlan.Prompt) return@call statusOf(before)
                if (!owner || prompter.busy) throw FlutterError(BridgeErrors.REQUEST_IN_PROGRESS, null, null)
                // No activity: nothing is shown, so no flag changes.
                if (!prompter.canPrompt()) return@call statusOf(before)
                // Before the dialog: a process killed while it is shown still counts the prompt.
                if (plan.markLocation) bestEffort("flag location") { flags.markLocationRequested() }
                if (plan.markNotifications) bestEffort("flag notifications") { flags.markNotificationsRequested() }
                if (plan.countPreciseAttempt) bestEffort("flag precise") { flags.countPreciseAttempt() }
                prompter.prompt(plan.permissions)
                // Read again: grantResults is empty when the dialog was cancelled (A-REQ).
                statusOf(snapshot())
            } finally {
                if (owner) requesting.set(false)
            }
        }

    override fun openSettings(target: SettingsTargetMsg): Boolean =
        BridgeGuard.call {
            val specs = SettingsIntents.candidates(target, sources.sdkInt)
            specs.isNotEmpty() && settings.open(specs)
        }

    override fun deviceInfo(): DeviceInfoMsg = BridgeGuard.call { readDeviceInfo() }

    override fun deviceStatus(): DeviceStatusMsg = BridgeGuard.call { readDeviceStatus() }

    override fun mapsConfig(): MapsConfigMsg = BridgeGuard.call { readMapsConfig() }

    override suspend fun distancesFromLastKnownM(latLngPairs: List<Double>, maxAgeMs: Long): List<Double>? =
        BridgeGuard.call { readDistances(latLngPairs, maxAgeMs) }

    override suspend fun startBackgroundCheck(delayMs: Long): BackgroundCheckMsg =
        BridgeGuard.call {
            BackgroundCheckLogic.validate(delayMs)
            backgroundChecks.start(delayMs).toMsg()
        }

    override suspend fun backgroundCheck(): BackgroundCheckMsg? = BridgeGuard.call { backgroundChecks.read()?.toMsg() }

    override suspend fun cancelBackgroundCheck() = BridgeGuard.call { backgroundChecks.cancel() }

    /** Precise granted again: a later downgrade to "Approximate" may be asked once more (§4.2). */
    private suspend fun statusOf(s: PermissionSnapshot): PermissionStatusMsg {
        if (s.fine && s.preciseUpgradeAttempts > 0) bestEffort("flag precise reset") { flags.resetPreciseAttempts() }
        return PermissionMapping.status(s)
    }

    /**
     * Reads every item on its own (§4.1). A failing blocking item (location services) reads
     * as on: startTrip checks again natively. A failing warning item reads as off / unknown,
     * i.e. `denied` (better one warning too many); a failing rationale reads as "no activity".
     * [PermissionSources.sdkInt] and `isGranted` (documented not to throw) are not caught here:
     * guessing a runtime permission would be worse, so the call fails with `internal` (K06 g).
     */
    private suspend fun snapshot(): PermissionSnapshot {
        val sdk = sources.sdkInt
        val f =
            try {
                flags.read()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                warn("permission flags: ${e.javaClass.simpleName}")
                PermissionFlags.Flags.NONE
            }
        val rationaleFine = item("rationale fine", null) { sources.rationale(PermissionMapping.FINE) }
        val rationaleCoarse = item("rationale coarse", null) { sources.rationale(PermissionMapping.COARSE) }
        return PermissionSnapshot(
            sdkInt = sdk,
            fine = sources.isGranted(PermissionMapping.FINE),
            coarse = sources.isGranted(PermissionMapping.COARSE),
            locationRequested = f.locationRequested,
            locationRationale =
                if (rationaleFine == null && rationaleCoarse == null) null else rationaleFine == true || rationaleCoarse == true,
            preciseUpgradeAttempts = f.preciseUpgradeAttempts,
            locationEnabled = item("location services", true) { sources.locationEnabled() },
            postNotificationsGranted =
                sdk >= PermissionMapping.SDK_POST_NOTIFICATIONS &&
                    sources.isGranted(PermissionMapping.POST_NOTIFICATIONS),
            notificationsEnabled = item("notifications", false) { sources.notificationsEnabled() },
            notificationsRequested = f.notificationsRequested,
            notificationsRationale =
                if (sdk >= PermissionMapping.SDK_POST_NOTIFICATIONS) {
                    item("rationale notifications", null) { sources.rationale(PermissionMapping.POST_NOTIFICATIONS) }
                } else {
                    null
                },
            canUseFullScreenIntent =
                if (sdk >= PermissionMapping.SDK_FULL_SCREEN_INTENT) {
                    item("full screen intent", null) { sources.canUseFullScreenIntent() }
                } else {
                    null
                },
            canScheduleExactAlarms =
                if (sdk >= PermissionMapping.SDK_EXACT_ALARM) {
                    item("exact alarm", null) { sources.canScheduleExactAlarms() }
                } else {
                    null
                },
            ignoringBatteryOptimizations = item("battery optimization", null) { sources.ignoringBatteryOptimizations() },
        )
    }

    private inline fun <T> item(name: String, fallback: T, block: () -> T): T =
        try {
            block()
        } catch (e: Exception) {
            warn("permission $name: ${e.javaClass.simpleName}")
            fallback
        }

    private suspend inline fun bestEffort(name: String, block: () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            warn("permission $name: ${e.javaClass.simpleName}")
        }
    }
}
