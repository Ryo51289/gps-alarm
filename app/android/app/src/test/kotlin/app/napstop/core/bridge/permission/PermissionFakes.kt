package app.napstop.core.bridge.permission

import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.DeviceInfoMsg
import app.napstop.core.bridge.DeviceStatusMsg
import app.napstop.core.bridge.FlutterError
import app.napstop.core.bridge.InterruptionFilterMsg
import app.napstop.core.bridge.MapsConfigMsg
import app.napstop.core.bridge.PlatformMsg
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.yield

/** Fakes of the PermissionHostApiImpl collaborators (K06, K07). [log] records the order of effects. */
internal class PermissionFakes {
    val log = mutableListOf<String>()
    val warnings = mutableListOf<String>()

    /** When set, sdkInt, isGranted, deviceInfo and the background check throw it (K07). */
    var failure: (() -> Throwable)? = null

    val sources = FakeSources()
    val flags = FakeFlags()
    val prompter = FakePrompter()
    val started = mutableListOf<IntentSpec>()

    /** Per-candidate behaviour of the launcher; missing = opens. */
    val launchFailures = mutableMapOf<String, () -> Throwable>()

    val checks = FakeChecks()

    fun impl(): PermissionHostApiImpl =
        PermissionHostApiImpl(
            sources = sources,
            flags = flags,
            prompter = prompter,
            settings =
                SettingsLauncher { spec ->
                    started += spec
                    launchFailures[spec.action]?.let { throw it() }
                },
            readDeviceInfo = {
                failure?.let { throw it() }
                DeviceInfoMsg(
                    platform = PlatformMsg.ANDROID,
                    manufacturer = "Xiaomi",
                    brand = "Redmi",
                    model = "M1",
                    osVersion = "14",
                    androidSdkInt = 34L,
                )
            },
            readDeviceStatus = { DeviceStatusMsg(interruptionFilter = InterruptionFilterMsg.ALL) },
            readMapsConfig = { MapsConfigMsg() },
            readDistances = { _, _ -> null },
            backgroundChecks = checks,
            warn = { warnings += it },
        )

    inner class FakeSources : PermissionSources {
        var sdk = 34
        val granted = mutableSetOf(PermissionMapping.FINE, PermissionMapping.COARSE, PermissionMapping.POST_NOTIFICATIONS)
        var rationale: Boolean? = false
        var locationOn = true
        var notificationsOn = true
        var fsi = true
        var exact = true
        var battery = false

        /** Items whose read throws IllegalStateException. */
        val throwing = mutableSetOf<String>()

        private fun check(item: String) {
            if (item in throwing) throw IllegalStateException("21.0")
        }

        override val sdkInt: Int
            get() {
                failure?.let { throw it() }
                return sdk
            }

        override fun isGranted(permission: String): Boolean {
            failure?.let { throw it() }
            check("isGranted")
            return permission in granted
        }

        override fun rationale(permission: String): Boolean? {
            check("rationale")
            return rationale
        }

        override fun locationEnabled(): Boolean {
            check("locationEnabled")
            return locationOn
        }

        override fun notificationsEnabled(): Boolean {
            check("notificationsEnabled")
            return notificationsOn
        }

        override fun canUseFullScreenIntent(): Boolean {
            check("canUseFullScreenIntent")
            return fsi
        }

        override fun canScheduleExactAlarms(): Boolean {
            check("canScheduleExactAlarms")
            return exact
        }

        override fun ignoringBatteryOptimizations(): Boolean {
            check("ignoringBatteryOptimizations")
            return battery
        }
    }

    inner class FakeFlags : PermissionFlags {
        var flags = PermissionFlags.Flags.NONE
        var readError: Throwable? = null

        /** Suspends in read() (like the real IO switch), so calls can interleave. */
        var suspendOnRead = false

        override suspend fun read(): PermissionFlags.Flags {
            if (suspendOnRead) yield()
            readError?.let { throw it }
            return flags
        }

        override suspend fun markLocationRequested() {
            log += "markLocation"
            flags = flags.copy(locationRequested = true)
        }

        override suspend fun markNotificationsRequested() {
            log += "markNotifications"
            flags = flags.copy(notificationsRequested = true)
        }

        override suspend fun countPreciseAttempt() {
            log += "countPrecise"
            flags = flags.copy(preciseUpgradeAttempts = flags.preciseUpgradeAttempts + 1)
        }

        override suspend fun resetPreciseAttempts() {
            log += "resetPrecise"
            flags = flags.copy(preciseUpgradeAttempts = 0)
        }
    }

    inner class FakePrompter : PermissionPrompter {
        var attached = true
        var pending: CompletableDeferred<Unit>? = null

        /** Applied when the dialog "closes": the user's answer. */
        var answer: () -> Unit = {}

        /** When set, prompt() waits for it. */
        var gate: CompletableDeferred<Unit>? = null
        val prompts = mutableListOf<List<String>>()

        override val busy: Boolean get() = pending != null

        override fun canPrompt(): Boolean = attached

        override suspend fun prompt(permissions: List<String>) {
            if (pending != null) throw FlutterError(BridgeErrors.REQUEST_IN_PROGRESS, null, null)
            log += "prompt"
            prompts += permissions
            val d = CompletableDeferred<Unit>()
            pending = d
            try {
                gate?.await()
                answer()
            } finally {
                pending = null
            }
        }

        override fun rationale(permission: String): Boolean? = sources.rationale
    }

    inner class FakeChecks : BackgroundChecks {
        var record: BackgroundCheckRecord? = null

        override suspend fun start(delayMs: Long): BackgroundCheckRecord {
            failure?.let { throw it() }
            log += "start $delayMs"
            return BackgroundCheckRecord(1_000L, 1_000L + delayMs, null, null, true).also { record = it }
        }

        override suspend fun read(): BackgroundCheckRecord? = record

        override suspend fun cancel() {
            log += "cancel"
            record = null
        }
    }
}
