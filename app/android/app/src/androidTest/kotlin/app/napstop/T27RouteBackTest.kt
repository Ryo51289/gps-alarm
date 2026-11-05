package app.napstop

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.RingSettings
import app.napstop.core.alarm.RingSource
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.host.RuntimeHost
import java.util.regex.Pattern
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * T27 AI-T27-1, AI-T27-2 (UI Automator, emulator API 34). The real AlarmController rings AlarmRingService in `:ring`
 * (same entry as the debug `ring_test` / `ring_overshoot`), the native AlarmActivity shows; the Flutter side of T27 reads
 * the launch action. Run: `./gradlew :app:connectedDevDebugAndroidTest
 * -Pandroid.testInstrumentationRunnerArguments.class=app.napstop.T27RouteBackTest` (needs a device; unlocked screen).
 *
 * Flutter text is read through its accessibility tree (UI Automator turns it on), as text or content description, in
 * vi or en (device language).
 */
class T27RouteBackTest {
    private val inst = InstrumentationRegistry.getInstrumentation()
    private val ctx: Context = inst.targetContext
    private val device = UiDevice.getInstance(inst)
    private val pkg = ctx.packageName
    private val trip = "t27route-${System.currentTimeMillis() % 100_000}"
    private val host get() = RuntimeHost.get(ctx)

    @Before
    fun setUp() {
        if (Build.VERSION.SDK_INT >= 33) shell("pm grant $pkg android.permission.POST_NOTIFICATIONS")
        device.wakeUp()
        shell("wm dismiss-keyguard")
        ctx.startActivity(
            ctx.packageManager.getLaunchIntentForPackage(pkg)!!
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        )
        device.wait(Until.hasObject(By.pkg(pkg).depth(0)), 15_000)
        Thread.sleep(3_000)
    }

    @After
    fun tearDown() {
        host.alarm.stopRinging(trip, StopCause.TRIP_ENDED)
        host.alarm.clearTrip(trip)
        device.pressHome()
    }

    private fun ring(pastM: Int? = null) {
        host.alarm.ringNow(
            RingRequest(
                tripId = trip, source = RingSource.ENGINE, reason = AlarmReason.DISTANCE, snoozeAllowed = pastM == null,
                distanceM = 1_200, etaS = 120, batteryPct = 50, destinationName = "Ga thử",
                settings = RingSettings("default", 0.3, false, "light", false, false, "swipe"),
                atWallMs = System.currentTimeMillis(),
            ),
        )
        if (pastM != null) {
            assertNotNull("native alarm screen", waitDesc(R.string.alarm_stop_a11y))
            host.alarm.overshoot(trip, pastM)
        }
    }

    private fun waitDesc(id: Int, ms: Long = 10_000): UiObject2? = device.wait(Until.findObject(By.desc(ctx.getString(id))), ms)

    /** Flutter text (label as text or content description), [regex] anywhere in it. */
    private fun waitFlutterText(regex: String, ms: Long = 15_000): UiObject2? {
        val p = Pattern.compile("(?s).*(?:$regex).*")
        val deadline = System.currentTimeMillis() + ms
        while (System.currentTimeMillis() < deadline) {
            device.findObject(By.text(p))?.let { return it }
            device.findObject(By.desc(p))?.let { return it }
            Thread.sleep(250)
        }
        return null
    }

    private fun shell(cmd: String): String {
        val pfd: ParcelFileDescriptor = inst.uiAutomation.executeShellCommand(cmd)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).bufferedReader().readText()
    }

    private fun resumedActivities(): List<Activity> {
        var out: List<Activity> = emptyList()
        inst.runOnMainSync { out = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).toList() }
        return out
    }

    /** Distinct ActivityRecords of MainActivity (dumpsys prints one record on several lines). */
    private fun mainActivityRecords(): Int =
        Regex("ActivityRecord\\{(\\w+) u0 ${Regex.escape(pkg)}/app\\.napstop\\.MainActivity")
            .findAll(shell("dumpsys activity activities")).map { it.groupValues[1] }.toSet().size

    private fun topResumed(): String =
        shell("dumpsys activity activities").lineSequence().firstOrNull { "topResumedActivity" in it || "ResumedActivity:" in it }.orEmpty()

    @Test
    fun aiT27_1_routeBackOpensScreen8() {
        ring(pastM = 1_200)
        val routeBack = device.wait(Until.findObject(By.text(ctx.getString(R.string.alarm_route_back))), 10_000)
        assertNotNull("route back button", routeBack)
        routeBack!!.click()

        // Screen 8 (Flutter): no trips row for this debug trip → generic title, "Đã qua 1,2 km", no directions button.
        assertNotNull("past line", waitFlutterText("Đã qua 1,2 km|1\\.2 km past it"))
        assertNotNull("title without a trips row", waitFlutterText("Bạn đã đi quá điểm đến|You've gone past your stop"))
        assertNull("no directions button without a row", waitFlutterText("Chỉ đường quay lại|Directions back", ms = 1_500))
        assertNotNull("go home button", waitFlutterText("Về trang chủ|Go to home", ms = 3_000))

        assertTrue("MainActivity on top: ${topResumed()}", topResumed().contains("$pkg/app.napstop.MainActivity") ||
            topResumed().contains("$pkg/.MainActivity"))
        assertTrue(resumedActivities().any { it is MainActivity })
        // singleTop in the existing task: still one MainActivity (one Flutter engine).
        assertEquals("MainActivity records", 1, mainActivityRecords())
        Thread.sleep(1_500)
        assertFalse(host.alarm.ringFacts(trip).ringingNow)
        assertFalse("ring service gone", shell("dumpsys activity services $pkg").contains("AlarmRingService"))
        // Maps was not opened (no row: D7, D12).
        assertFalse(topResumed().contains("com.google.android.apps.maps"))
    }

    /** Beyond the spec (D3, Q3 = A): an overshoot ring stopped by the swipe bar does not open screen 8. */
    @Test
    fun aiT27_1b_overshootSwipeDoesNotOpenScreen8() {
        ring(pastM = 900)
        val bar = waitDesc(R.string.alarm_stop_a11y)!!
        val b = bar.visibleBounds
        device.swipe(b.left + b.height() / 2, b.centerY(), b.right - b.height() / 2 + 4, b.centerY(), 40)
        assertTrue("alarm screen gone", device.wait(Until.gone(By.desc(ctx.getString(R.string.alarm_stop_a11y))), 8_000))
        Thread.sleep(4_000)
        assertFalse(host.alarm.ringFacts(trip).ringingNow)
        assertNull("no screen 8", waitFlutterText("Đã qua 900 m|900 m past it|Bạn đã đi quá điểm đến|You've gone past your stop", ms = 2_000))
        assertNull("no launch action left", app.napstop.core.alarm.LaunchActions.consume())
    }

    @Test
    fun aiT27_2_nativeScreenCoversTheOpenApp() {
        assertTrue("app visible first", resumedActivities().any { it is MainActivity })
        ring()
        assertNotNull("native alarm screen", waitDesc(R.string.alarm_stop_a11y))
        // T27 D1: once AlarmActivity shows, MainActivity is no longer resumed (Flutter leaves `resumed`), for the
        // whole 8 s (2 × kRingUiGrace) and longer.
        val end = System.currentTimeMillis() + 12_000
        while (System.currentTimeMillis() < end) {
            assertFalse("MainActivity resumed under the alarm", resumedActivities().any { it is MainActivity })
            assertTrue("AlarmActivity on top: ${topResumed()}", topResumed().contains("AlarmActivity"))
            Thread.sleep(500)
        }
        assertNull("Flutter fallback screen 5", waitFlutterText("Mở màn báo thức|Open alarm screen", ms = 500))
        assertTrue(host.alarm.ringFacts(trip).ringingNow)
    }
}
