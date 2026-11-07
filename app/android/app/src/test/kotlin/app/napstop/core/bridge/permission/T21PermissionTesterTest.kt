package app.napstop.core.bridge.permission

import android.content.ActivityNotFoundException
import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.BridgeGuard
import app.napstop.core.bridge.DeviceStatusMsg
import app.napstop.core.bridge.FlutterError
import app.napstop.core.bridge.LocationAccessMsg
import app.napstop.core.bridge.PermissionKindMsg
import app.napstop.core.bridge.PermissionStateMsg
import app.napstop.core.bridge.PermissionStatusMsg
import app.napstop.core.bridge.SettingsTargetMsg
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Tester T21: adversarial checks of the pure permission mapping, the settings intents,
 * BridgeGuard and the request lifecycle. The oracle below is written from the spec text
 * (§4.2, §4.3, §4.4), not from the implementation.
 */
class T21PermissionTesterTest {
    // ------------------------------------------------------------------ oracle (spec §4.2)

    private fun promptable(requested: Boolean, rationale: Boolean?) = !requested || rationale == true

    private fun oracle(s: PermissionSnapshot): PermissionStatusMsg =
        PermissionStatusMsg(
            location =
                if (s.fine || s.coarse) {
                    LocationAccessMsg.WHILE_IN_USE
                } else if (promptable(s.locationRequested, s.locationRationale)) {
                    LocationAccessMsg.NOT_DETERMINED
                } else {
                    LocationAccessMsg.DENIED
                },
            precise =
                if (s.fine) {
                    PermissionStateMsg.GRANTED
                } else if (s.coarse) {
                    if (s.sdkInt >= 31 && s.preciseUpgradeAttempts == 0) PermissionStateMsg.NOT_DETERMINED else PermissionStateMsg.DENIED
                } else {
                    PermissionStateMsg.NOT_DETERMINED
                },
            locationServicesEnabled = s.locationEnabled,
            notifications =
                if (s.notificationsEnabled) {
                    PermissionStateMsg.GRANTED
                } else if (s.sdkInt >= 33 && !s.postNotificationsGranted &&
                    promptable(s.notificationsRequested, s.notificationsRationale)
                ) {
                    PermissionStateMsg.NOT_DETERMINED
                } else {
                    PermissionStateMsg.DENIED
                },
            fullScreenIntent =
                if (s.sdkInt < 34) {
                    PermissionStateMsg.GRANTED
                } else if (s.canUseFullScreenIntent == true) {
                    PermissionStateMsg.GRANTED
                } else {
                    PermissionStateMsg.DENIED
                },
            exactAlarm =
                if (s.sdkInt < 31) {
                    PermissionStateMsg.GRANTED
                } else if (s.canScheduleExactAlarms == true) {
                    PermissionStateMsg.GRANTED
                } else {
                    PermissionStateMsg.DENIED
                },
            batteryOptimizationIgnored =
                if (s.ignoringBatteryOptimizations == true) PermissionStateMsg.GRANTED else PermissionStateMsg.DENIED,
            alarmKit = PermissionStateMsg.NOT_APPLICABLE,
        )

    /** Every snapshot for API 26..35 (+36), attempts 0..2, every boolean / tri-state. */
    private fun everySnapshot(): Sequence<PermissionSnapshot> =
        sequence {
            val b = listOf(false, true)
            val tri = listOf(null, false, true)
            for (sdk in 26..36) for (fine in b) for (coarse in b) for (req in b) for (rat in tri) {
                for (attempts in 0..2) for (enabled in b) for (post in b) for (notifOn in b) for (notifReq in b) {
                    for (notifRat in tri) for (fsi in tri) for (exact in tri) for (battery in tri) {
                        yield(
                            PermissionSnapshot(
                                sdkInt = sdk,
                                fine = fine,
                                coarse = coarse,
                                locationRequested = req,
                                locationRationale = rat,
                                preciseUpgradeAttempts = attempts,
                                locationEnabled = enabled,
                                postNotificationsGranted = post,
                                notificationsEnabled = notifOn,
                                notificationsRequested = notifReq,
                                notificationsRationale = notifRat,
                                canUseFullScreenIntent = fsi,
                                canScheduleExactAlarms = exact,
                                ignoringBatteryOptimizations = battery,
                            ),
                        )
                    }
                }
            }
        }

    @Test
    fun mappingEqualsTheSpecOracleForEverySnapshotOnApi26To36() {
        var n = 0
        for (s in everySnapshot()) {
            val actual = PermissionMapping.status(s)
            if (actual != oracle(s)) fail("mismatch for $s: $actual vs ${oracle(s)}")
            assertNotEquals(PermissionStateMsg.NOT_APPLICABLE, actual.precise)
            assertNotEquals(LocationAccessMsg.ALWAYS, actual.location)
            n++
        }
        // 11 SDK levels x 2^7 booleans x 3^5 tri-states x 3 attempt counts.
        assertEquals(11 * 128 * 243 * 3, n)
    }

    /**
     * A row that says "Cấp quyền" / "Bật Chính xác" must show a dialog when tapped, and a row
     * that is done must not: status() and plan() agree for every snapshot.
     */
    @Test
    fun statusAndPlanAgreeSoNoButtonIsDead() {
        for (s in everySnapshot()) {
            val st = PermissionMapping.status(s)
            val loc = PermissionMapping.plan(PermissionKindMsg.LOCATION, s)
            val notif = PermissionMapping.plan(PermissionKindMsg.NOTIFICATIONS, s)
            assertEquals(RequestPlan.None, PermissionMapping.plan(PermissionKindMsg.ALARM_KIT, s))
            if (st.location == LocationAccessMsg.NOT_DETERMINED) {
                assertTrue("location row 'Cấp quyền' without dialog: $s", loc is RequestPlan.Prompt)
            }
            if (st.location == LocationAccessMsg.WHILE_IN_USE && st.precise == PermissionStateMsg.NOT_DETERMINED) {
                assertTrue("'Bật Chính xác' without dialog: $s", loc is RequestPlan.Prompt)
                assertTrue((loc as RequestPlan.Prompt).countPreciseAttempt)
            }
            if (st.precise == PermissionStateMsg.GRANTED) assertEquals(RequestPlan.None, loc)
            if (loc is RequestPlan.Prompt) {
                // FINE always together with COARSE, in one request (A-RT).
                assertEquals(listOf(PermissionMapping.FINE, PermissionMapping.COARSE), loc.permissions)
                assertTrue(loc.markLocation)
                assertFalse(loc.markNotifications)
                assertEquals(s.coarse, loc.countPreciseAttempt)
            }
            if (st.notifications == PermissionStateMsg.NOT_DETERMINED) {
                assertTrue("notifications 'Cấp quyền' without dialog: $s", notif is RequestPlan.Prompt)
            }
            if (st.notifications == PermissionStateMsg.GRANTED) assertEquals(RequestPlan.None, notif)
            if (notif is RequestPlan.Prompt) {
                assertEquals(listOf(PermissionMapping.POST_NOTIFICATIONS), notif.permissions)
                assertTrue(notif.markNotifications)
                assertTrue(s.sdkInt >= 33)
            }
        }
    }

    // ------------------------------------------------------------------ user journeys

    private fun journey(
        sdk: Int,
        fine: Boolean = false,
        coarse: Boolean = false,
        requested: Boolean = false,
        rationale: Boolean? = false,
        attempts: Int = 0,
    ) = PermissionMapping.status(
        PermissionSnapshot(
            sdkInt = sdk,
            fine = fine,
            coarse = coarse,
            locationRequested = requested,
            locationRationale = rationale,
            preciseUpgradeAttempts = attempts,
            locationEnabled = true,
            postNotificationsGranted = false,
            notificationsEnabled = false,
            notificationsRequested = false,
            notificationsRationale = false,
            canUseFullScreenIntent = true,
            canScheduleExactAlarms = true,
            ignoringBatteryOptimizations = false,
        ),
    )

    @Test
    fun locationJourneyOnEveryApi() {
        for (sdk in 26..35) {
            // Fresh install: rationale false, never asked -> dialog.
            assertEquals("$sdk fresh", LocationAccessMsg.NOT_DETERMINED, journey(sdk).location)
            // Denied once: rationale true -> dialog again.
            assertEquals("$sdk denied once", LocationAccessMsg.NOT_DETERMINED, journey(sdk, requested = true, rationale = true).location)
            // Denied twice ("don't ask again"): rationale false -> Settings only.
            assertEquals("$sdk denied twice", LocationAccessMsg.DENIED, journey(sdk, requested = true, rationale = false).location)
            // Granted precise.
            val ok = journey(sdk, fine = true, coarse = true, requested = true)
            assertEquals(LocationAccessMsg.WHILE_IN_USE, ok.location)
            assertEquals(PermissionStateMsg.GRANTED, ok.precise)
            // "Approximate" chosen (31+): one upgrade dialog, then Settings.
            val approx0 = journey(sdk, coarse = true, requested = true, attempts = 0)
            val approx1 = journey(sdk, coarse = true, requested = true, attempts = 1)
            assertEquals(LocationAccessMsg.WHILE_IN_USE, approx0.location)
            assertEquals(
                "$sdk approx 0",
                if (sdk >= 31) PermissionStateMsg.NOT_DETERMINED else PermissionStateMsg.DENIED,
                approx0.precise,
            )
            assertEquals("$sdk approx 1", PermissionStateMsg.DENIED, approx1.precise)
        }
    }

    @Test
    fun notificationsJourney() {
        fun n(sdk: Int, on: Boolean, post: Boolean, req: Boolean, rat: Boolean?) =
            PermissionMapping.status(
                PermissionSnapshot(
                    sdkInt = sdk, fine = true, coarse = true, locationRequested = true, locationRationale = false,
                    preciseUpgradeAttempts = 0, locationEnabled = true, postNotificationsGranted = post,
                    notificationsEnabled = on, notificationsRequested = req, notificationsRationale = rat,
                    canUseFullScreenIntent = true, canScheduleExactAlarms = true, ignoringBatteryOptimizations = true,
                ),
            ).notifications
        for (sdk in 26..32) {
            // Below 33 there is no dialog: on = granted, off = Settings.
            assertEquals(PermissionStateMsg.GRANTED, n(sdk, on = true, post = false, req = false, rat = null))
            assertEquals(PermissionStateMsg.DENIED, n(sdk, on = false, post = false, req = false, rat = null))
        }
        for (sdk in 33..35) {
            assertEquals(PermissionStateMsg.NOT_DETERMINED, n(sdk, on = false, post = false, req = false, rat = false))
            assertEquals(PermissionStateMsg.NOT_DETERMINED, n(sdk, on = false, post = false, req = true, rat = true))
            assertEquals(PermissionStateMsg.DENIED, n(sdk, on = false, post = false, req = true, rat = false))
            // Permission granted, then the user switched notifications off: Settings only.
            assertEquals(PermissionStateMsg.DENIED, n(sdk, on = false, post = true, req = true, rat = false))
            assertEquals(PermissionStateMsg.GRANTED, n(sdk, on = true, post = true, req = true, rat = false))
        }
    }

    // ------------------------------------------------------------------ settings intents (§4.4)

    @Test
    fun settingsCandidatesForEveryTargetOnApi21To36() {
        val forbidden = "android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"
        val appDetails = "android.settings.APPLICATION_DETAILS_SETTINGS"
        for (sdk in 21..36) {
            for (target in SettingsTargetMsg.entries) {
                val c = SettingsIntents.candidates(target, sdk)
                assertFalse("$target/$sdk", c.any { it.action == forbidden })
                // Specific pages always fall back to the app details page (R7).
                when (target) {
                    SettingsTargetMsg.APP_DETAILS -> assertEquals(listOf(appDetails), c.map { it.action })
                    SettingsTargetMsg.LOCATION_SERVICES ->
                        assertEquals(listOf("android.settings.LOCATION_SOURCE_SETTINGS"), c.map { it.action })
                    SettingsTargetMsg.FULL_SCREEN_INTENT ->
                        if (sdk < 34) assertTrue(c.isEmpty()) else assertEquals(appDetails, c.last().action)
                    SettingsTargetMsg.EXACT_ALARM ->
                        if (sdk < 31) assertTrue(c.isEmpty()) else assertEquals(appDetails, c.last().action)
                    else -> assertEquals("$target/$sdk", appDetails, c.last().action)
                }
                // The app-details page needs package:<pkg>; the location page must not get one.
                for (spec in c) {
                    if (spec.action == appDetails) assertTrue(spec.packageUri)
                    if (spec.action == "android.settings.LOCATION_SOURCE_SETTINGS") {
                        assertFalse(spec.packageUri || spec.extraAppPackage)
                    }
                    if (spec.action == "android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS") {
                        // A list page: a package URI makes some ROMs refuse to start it.
                        assertFalse(spec.packageUri)
                    }
                }
            }
        }
    }

    @Test
    fun launcherStopsAtTheFirstPageThatOpensAndSkipsOnlyKnownFailures() {
        val tried = mutableListOf<String>()
        val launcher =
            SettingsLauncher { spec ->
                tried += spec.action
                if (spec.action == "a") throw SecurityException("secret 21.03")
                if (spec.action == "b") throw ActivityNotFoundException()
            }
        assertTrue(launcher.open(listOf(IntentSpec("a"), IntentSpec("b"), IntentSpec("c"), IntentSpec("d"))))
        assertEquals(listOf("a", "b", "c"), tried)
        assertFalse(launcher.open(emptyList()))
    }

    @Test
    fun anUnexpectedLauncherErrorReachesDartAsInternalWithoutItsMessage() {
        val fakes = PermissionFakes()
        fakes.launchFailures["android.settings.APPLICATION_DETAILS_SETTINGS"] = { IllegalStateException("lat 21.03") }
        try {
            fakes.impl().openSettings(SettingsTargetMsg.APP_DETAILS)
            fail("no error")
        } catch (e: FlutterError) {
            assertEquals(BridgeErrors.INTERNAL, e.code)
            assertEquals("IllegalStateException", e.message)
            assertNull(e.details)
        }
    }

    @Test
    fun openSettingsIsFalseNotAnErrorWhenNoPageExistsOnAnyApi() {
        for (sdk in 26..35) {
            for (target in SettingsTargetMsg.entries) {
                val fakes = PermissionFakes()
                fakes.sources.sdk = sdk
                for (a in listOf(
                    "android.settings.APPLICATION_DETAILS_SETTINGS",
                    "android.settings.LOCATION_SOURCE_SETTINGS",
                    "android.settings.APP_NOTIFICATION_SETTINGS",
                    "android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT",
                    "android.settings.REQUEST_SCHEDULE_EXACT_ALARM",
                    "android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS",
                )) {
                    fakes.launchFailures[a] = { ActivityNotFoundException() }
                }
                assertFalse("$target/$sdk", fakes.impl().openSettings(target))
            }
        }
    }

    // ------------------------------------------------------------------ BridgeGuard (T14 F3)

    @Test
    fun guardNeverForwardsMessagesCausesOrStackTraces() {
        val throwables: List<Throwable> =
            listOf(
                IllegalStateException("Hà Nội 21.0285,105.8542"),
                RuntimeException("outer", IllegalArgumentException("inner 21.0")),
                StackOverflowError("deep 21.0"),
                OutOfMemoryError("oom 21.0"),
                ArithmeticException(),
                object : IllegalStateException("anon 21.0") {},
                NotImplementedError("todo 21.0"),
                ClassCastException("x 105.8"),
            )
        for (t in throwables) {
            try {
                BridgeGuard.call<Unit> { throw t }
                fail("no error for $t")
            } catch (e: FlutterError) {
                assertEquals(BridgeErrors.INTERNAL, e.code)
                assertNull(e.details)
                assertNull("cause leaks for $t", e.cause)
                val msg = e.message ?: ""
                assertFalse("message leaks for $t: $msg", msg.contains("21.0") || msg.contains("105.8") || msg.contains(" "))
                assertTrue(msg.isNotEmpty())
            }
        }
    }

    @Test
    fun guardPassesFlutterErrorsUnchanged() {
        val original = FlutterError(BridgeErrors.INVALID_CONFIG, "delayMs: out of range", null)
        try {
            BridgeGuard.call<Unit> { throw original }
            fail("no error")
        } catch (e: FlutterError) {
            assertTrue(e === original)
        }
    }

    @Test
    fun everyHostMethodIsGuarded() =
        runTest {
            val secret = { IllegalArgumentException("lat 21.0285 lng 105.8542") }
            val impl =
                PermissionHostApiImpl(
                    sources = PermissionFakes().sources,
                    flags = PermissionFakes().flags,
                    prompter = PermissionFakes().prompter,
                    settings = SettingsLauncher { throw secret() },
                    readDeviceInfo = { throw secret() },
                    readDeviceStatus = { throw secret() },
                    readDistances = { _, _ -> throw secret() },
                    backgroundChecks =
                        object : BackgroundChecks {
                            override suspend fun start(delayMs: Long): BackgroundCheckRecord = throw secret()

                            override suspend fun read(): BackgroundCheckRecord? = throw secret()

                            override suspend fun cancel() {
                                throw secret()
                            }
                        },
                    warn = {},
                )
            val calls: List<Pair<String, suspend () -> Any?>> =
                listOf(
                    "openSettings" to { impl.openSettings(SettingsTargetMsg.APP_DETAILS) },
                    "deviceInfo" to { impl.deviceInfo() },
                    "deviceStatus" to { impl.deviceStatus() },
                    "distances" to { impl.distancesFromLastKnownM(listOf(21.0, 105.8), 1_000L) },
                    "startBackgroundCheck" to { impl.startBackgroundCheck(30_000L) },
                    "backgroundCheck" to { impl.backgroundCheck() },
                    "cancelBackgroundCheck" to { impl.cancelBackgroundCheck() },
                )
            for ((name, call) in calls) {
                try {
                    call()
                    fail("$name: no error")
                } catch (e: FlutterError) {
                    assertEquals(name, BridgeErrors.INTERNAL, e.code)
                    assertEquals(name, "IllegalArgumentException", e.message)
                    assertNull(name, e.details)
                }
            }
        }

    @Test
    fun warningsCarryNoValues() =
        runTest {
            val fakes = PermissionFakes()
            fakes.sources.throwing +=
                listOf(
                    "rationale", "locationEnabled", "notificationsEnabled", "canUseFullScreenIntent",
                    "canScheduleExactAlarms", "ignoringBatteryOptimizations",
                )
            fakes.flags.readError = IllegalStateException("21.0 disk")
            val s = fakes.impl().status()
            // Blocking item reads as on; warning items as denied (better one warning too many).
            assertTrue(s.locationServicesEnabled)
            assertEquals(PermissionStateMsg.DENIED, s.notifications)
            assertEquals(PermissionStateMsg.DENIED, s.fullScreenIntent)
            assertEquals(PermissionStateMsg.DENIED, s.exactAlarm)
            assertEquals(PermissionStateMsg.DENIED, s.batteryOptimizationIgnored)
            // flags, rationale fine/coarse/notifications, location services, notifications, FSI, exact, battery.
            assertEquals(9, fakes.warnings.size)
            for (w in fakes.warnings) {
                assertTrue(w, w.startsWith("permission ") && w.endsWith(": IllegalStateException"))
                assertFalse(w, w.contains("21.0"))
            }
        }

    // ------------------------------------------------------------------ request lifecycle

    @Test
    fun aRequestPendingWhenTheEngineGoesAwayReturnsAndTheNextOneIsNotBlocked() =
        runTest {
            val requested = mutableListOf<Int>()
            val prompter = ActivityPermissionPrompter({ _, code -> requested += code }, { false })
            val fakes = PermissionFakes()
            fakes.sources.granted.clear()
            val impl =
                PermissionHostApiImpl(
                    sources = fakes.sources, flags = fakes.flags, prompter = prompter,
                    settings = SettingsLauncher {}, readDeviceInfo = { error("unused") },
                    readDeviceStatus = { DeviceStatusMsg(interruptionFilter = app.napstop.core.bridge.InterruptionFilterMsg.ALL) },
                    readDistances = { _, _ -> null }, backgroundChecks = fakes.checks, warn = {},
                )
            val first = async { impl.request(PermissionKindMsg.LOCATION) }
            runCurrent()
            assertEquals(listOf(ActivityPermissionPrompter.REQUEST_CODE), requested)
            assertTrue(prompter.busy)
            // Process / activity goes away while the dialog is open (cleanUpFlutterEngine -> detach).
            prompter.detach()
            runCurrent()
            // Answers (no hang) with the state read again.
            first.await()
            assertFalse(prompter.busy)
            assertTrue(fakes.flags.flags.locationRequested)
            // A new engine gets a new prompter; the stale result of the old dialog is harmless.
            val next = ActivityPermissionPrompter({ _, code -> requested += code }, { true })
            assertTrue(next.onRequestPermissionsResult(ActivityPermissionPrompter.REQUEST_CODE))
            assertFalse(next.busy)
            // The detached prompter shows nothing; request() answers with the state.
            assertEquals(LocationAccessMsg.DENIED, impl.request(PermissionKindMsg.LOCATION).location)
            assertEquals(1, requested.size)
        }

    @Test
    fun aCancelledRequestCoroutineReleasesTheClaim() =
        runTest {
            val fakes = PermissionFakes()
            fakes.sources.granted.clear()
            fakes.prompter.gate = CompletableDeferred()
            val impl = fakes.impl()
            val first = async { impl.request(PermissionKindMsg.LOCATION) }
            runCurrent()
            assertTrue(fakes.prompter.busy)
            first.cancel()
            runCurrent()
            assertFalse(fakes.prompter.busy)
            fakes.prompter.gate = null
            // Not stuck in request-in-progress: the next request shows a dialog again.
            impl.request(PermissionKindMsg.LOCATION)
            assertEquals(2, fakes.prompter.prompts.size)
        }

    @Test
    fun anotherPluginsResultNeverCompletesOurDialog() =
        runTest {
            val prompter = ActivityPermissionPrompter({ _, _ -> }, { false })
            val p = async { prompter.prompt(listOf(PermissionMapping.POST_NOTIFICATIONS)) }
            runCurrent()
            for (code in listOf(0, 1, 0xFFFF, ActivityPermissionPrompter.REQUEST_CODE + 1, -1)) {
                assertFalse(prompter.onRequestPermissionsResult(code))
            }
            runCurrent()
            assertTrue(prompter.busy)
            assertTrue(prompter.onRequestPermissionsResult(ActivityPermissionPrompter.REQUEST_CODE))
            runCurrent()
            assertTrue(p.isCompleted)
            assertFalse(prompter.busy)
        }

    @Test
    fun preciseUpgradeAttemptsResetOnlyWhenFineIsBack() =
        runTest {
            val fakes = PermissionFakes()
            fakes.sources.granted.remove(PermissionMapping.FINE)
            fakes.flags.flags = PermissionFlags.Flags(true, false, 1)
            val impl = fakes.impl()
            assertEquals(PermissionStateMsg.DENIED, impl.status().precise)
            assertFalse(fakes.log.contains("resetPrecise"))
            fakes.sources.granted += PermissionMapping.FINE
            assertEquals(PermissionStateMsg.GRANTED, impl.status().precise)
            assertEquals(listOf("resetPrecise"), fakes.log)
            // Downgraded again later: one more upgrade dialog is allowed.
            fakes.sources.granted.remove(PermissionMapping.FINE)
            assertEquals(PermissionStateMsg.NOT_DETERMINED, impl.status().precise)
        }

    // ------------------------------------------------------------------ background check logic (§5)

    @Test
    fun backgroundCheckVibratesAtMostOncePerCheck() {
        val r = BackgroundCheckRecord(1_000L, 31_000L, null, null, true)
        val fired = BackgroundCheckLogic.onFired(r, 1_000L, 31_010L, interactive = false)!!
        assertEquals(31_010L, fired.firedAtMs)
        assertEquals(false, fired.screenOnAtFire)
        // Duplicate delivery of the same alarm.
        assertNull(BackgroundCheckLogic.onFired(fired, 1_000L, 31_020L, interactive = true))
        // Missing extra (-1) or the alarm of a replaced check.
        assertNull(BackgroundCheckLogic.onFired(r, -1L, 31_010L, false))
        assertNull(BackgroundCheckLogic.onFired(r, 999L, 31_010L, false))
        // Cancelled check (record cleared) whose alarm still arrives.
        assertNull(BackgroundCheckLogic.onFired(null, 1_000L, 31_010L, false))
    }

    @Test
    fun backgroundCheckDelayBounds() {
        for (ok in listOf(5_000L, 30_000L, 120_000L)) BackgroundCheckLogic.validate(ok)
        for (bad in listOf(Long.MIN_VALUE, -30_000L, 0L, 4_999L, 120_001L, Long.MAX_VALUE)) {
            try {
                BackgroundCheckLogic.validate(bad)
                fail("accepted $bad")
            } catch (e: FlutterError) {
                assertEquals(BridgeErrors.INVALID_CONFIG, e.code)
                assertEquals("delayMs: out of range", e.message)
            }
        }
    }

    @Test
    fun backgroundCheckUsesExactWheneverAllowed() {
        for (sdk in 26..30) for (c in listOf(null, false, true)) assertTrue(BackgroundCheckLogic.useExact(sdk, c))
        for (sdk in 31..36) {
            assertTrue(BackgroundCheckLogic.useExact(sdk, true))
            assertFalse(BackgroundCheckLogic.useExact(sdk, false))
            assertFalse(BackgroundCheckLogic.useExact(sdk, null))
        }
    }

    @Test
    fun backgroundCheckDecodeRejectsCorruptRecords() {
        val good = BackgroundCheckLogic.encode(BackgroundCheckRecord(1L, 2L, 3L, true, false))
        assertEquals(BackgroundCheckRecord(1L, 2L, 3L, true, false), BackgroundCheckLogic.decode(good))
        assertEquals(
            BackgroundCheckRecord(1L, 2L, null, null, true),
            BackgroundCheckLogic.decode(BackgroundCheckLogic.encode(BackgroundCheckRecord(1L, 2L, null, null, true))),
        )
        // Extra keys are ignored.
        assertEquals(BackgroundCheckRecord(1L, 2L, 3L, true, false), BackgroundCheckLogic.decode(good + ("other" to "x")))
        assertNull(BackgroundCheckLogic.decode(emptyMap<String, Any?>()))
        assertNull(BackgroundCheckLogic.decode(good + ("scheduledAtMs" to 1)))
        assertNull(BackgroundCheckLogic.decode(good + ("firedAtMs" to "3")))
        assertNull(BackgroundCheckLogic.decode(good + ("screenOnAtFire" to 1L)))
        assertNull(BackgroundCheckLogic.decode(good - "exact"))
        assertNull(BackgroundCheckLogic.decode(good - "dueAtMs"))
    }
}
