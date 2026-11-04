package app.napstop.alarm

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import app.napstop.R
import app.napstop.core.alarm.RingEnd
import app.napstop.core.alarm.RingFactsStore
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.RingSettings
import app.napstop.core.alarm.RingSource
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.host.RuntimeHost
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * T16 AI01–AI07 (UI Automator, emulator API 34 / 36): the real AlarmController rings AlarmRingService in `:ring`, the
 * native AlarmActivity shows and stops it. Run: `./gradlew :app:connectedDevDebugAndroidTest` (needs a device).
 */
class AlarmUiTest {
    private val inst = InstrumentationRegistry.getInstrumentation()
    private val ctx: Context = inst.targetContext
    private val device = UiDevice.getInstance(inst)
    private val pkg = ctx.packageName
    private val trip = "ai-ring-${System.currentTimeMillis() % 100_000}"
    private val host get() = RuntimeHost.get(ctx)
    private val book = RingFactsStore(File(ctx.noBackupFilesDir, RingFactsStore.DIR_NAME))

    @Before
    fun setUp() {
        // AGP installs the app without -g: without POST_NOTIFICATIONS (API 33+) there is no notification, hence no
        // full-screen intent on the lock screen (AI01). The app asks for it on screen 0 in real use.
        if (Build.VERSION.SDK_INT >= 33) shell("pm grant $pkg android.permission.POST_NOTIFICATIONS")
        device.wakeUp()
        shell("wm dismiss-keyguard")
        // The app is visible (as when a trip runs with the location FGS): the ring service may start (D3).
        ctx.startActivity(
            ctx.packageManager.getLaunchIntentForPackage(pkg)!!.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP),
        )
        device.wait(Until.hasObject(By.pkg(pkg).depth(0)), 15_000)
        Thread.sleep(2_000)
    }

    @After
    fun tearDown() {
        host.alarm.stopRinging(trip, StopCause.TRIP_ENDED)
        host.alarm.clearTrip(trip)
        device.wakeUp()
    }

    private fun ring(dismiss: String = "swipe", snooze: Boolean = true, reason: AlarmReason = AlarmReason.DISTANCE, pastM: Int? = null) {
        host.alarm.ringNow(
            RingRequest(
                tripId = trip, source = RingSource.ENGINE, reason = reason, snoozeAllowed = snooze, distanceM = 1_200, etaS = 120,
                batteryPct = 50, destinationName = "Ga thử", settings = RingSettings("default", 0.3, false, "light", false, false, dismiss),
                atWallMs = System.currentTimeMillis(),
            ),
        )
        if (pastM != null) {
            waitDesc(R.string.alarm_stop_a11y)
            host.alarm.overshoot(trip, pastM)
        }
    }

    private fun text(id: Int, upper: Boolean = false): String = ctx.getString(id).let { if (upper) it.uppercase(ctx.resources.configuration.locales[0]) else it }

    private fun waitText(id: Int, upper: Boolean = false, ms: Long = 8_000): UiObject2? = device.wait(Until.findObject(By.text(text(id, upper))), ms)

    private fun waitDesc(id: Int, ms: Long = 8_000): UiObject2? = device.wait(Until.findObject(By.desc(ctx.getString(id))), ms)

    private fun shell(cmd: String): String {
        val pfd: ParcelFileDescriptor = inst.uiAutomation.executeShellCommand(cmd)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).bufferedReader().readText()
    }

    private fun swipe(o: UiObject2, fraction: Float) {
        val b = o.visibleBounds
        val y = b.centerY()
        val startX = b.left + b.height() / 2
        val endX = (b.left + b.height() / 2 + (b.width() - b.height()) * fraction).toInt()
        device.swipe(startX, y, endX, y, 40)
    }

    @Test
    fun ai01_showsOverTheLockScreen() {
        device.sleep()
        Thread.sleep(1_500)
        ring()
        assertNotNull("alarm screen on the lock screen", waitDesc(R.string.alarm_stop_a11y, 10_000))
        assertTrue(device.isScreenOn)
        val km = ctx.getSystemService(KeyguardManager::class.java)
        assertTrue("keyguard still locked", km.isKeyguardLocked)
    }

    @Test
    fun ai02_swipeAllTheWayStops() {
        ring()
        val bar = waitDesc(R.string.alarm_stop_a11y)!!
        swipe(bar, 0.8f)
        Thread.sleep(1_000)
        assertTrue("80 % keeps ringing", host.alarm.ringFacts(trip).ringingNow)
        swipe(waitDesc(R.string.alarm_stop_a11y)!!, 1.0f)
        assertTrue(device.wait(Until.gone(By.desc(ctx.getString(R.string.alarm_stop_a11y))), 5_000))
        Thread.sleep(1_000)
        val r = book.read(trip)
        if (r != null) {
            // The runtime has no such trip: the book stays with the dismiss (else clearTrip removed it).
            assertEquals(RingEnd.DISMISSED, r.endedBy)
            assertNotNull(r.pendingDismissAtWallMs)
        }
        assertFalse(host.alarm.ringFacts(trip).ringingNow)
        assertFalse(shell("dumpsys activity services $pkg").contains("AlarmRingService"))
    }

    @Test
    fun ai03_mathWrongThenRight() {
        ring(dismiss = "math")
        val problem = device.wait(Until.findObject(By.textContains("+")), 8_000)!!
        val (a, b) = Regex("(\\d+) \\+ (\\d+)").find(problem.text)!!.destructured
        fun type(s: String) = s.forEach { d -> device.findObject(By.text(d.toString()))!!.click() }
        type("1")
        device.findObject(By.text(text(R.string.alarm_math_confirm)))!!.click()
        assertNotNull(waitText(R.string.alarm_math_wrong, ms = 3_000))
        type((a.toInt() + b.toInt()).toString())
        device.findObject(By.text(text(R.string.alarm_math_confirm)))!!.click()
        assertTrue(device.wait(Until.gone(By.textContains(" + ")), 5_000))
        assertFalse(host.alarm.ringFacts(trip).ringingNow)
    }

    @Test
    fun ai04_snoozeButtonFollowsSnoozeAllowed() {
        ring(snooze = false)
        assertNotNull(waitDesc(R.string.alarm_stop_a11y))
        assertNull(device.findObject(By.text(ctx.getString(R.string.alarm_snooze_minutes, "1"))))
        host.alarm.stopRinging(trip, StopCause.TRIP_ENDED)
        host.alarm.clearTrip(trip)
        Thread.sleep(1_500)
        ring(snooze = true)
        val snooze = device.wait(Until.findObject(By.text(ctx.getString(R.string.alarm_snooze_minutes, "1"))), 8_000)
        assertNotNull(snooze)
        snooze!!.click()
        Thread.sleep(1_500)
        val r = book.read(trip)
        if (r != null) assertEquals(RingEnd.SNOOZED, r.endedBy)
        assertFalse(host.alarm.ringFacts(trip).ringingNow)
    }

    @Test
    fun ai05_ringServiceRunsInTheRingProcess() {
        ring()
        assertNotNull(waitDesc(R.string.alarm_stop_a11y))
        val dump = shell("dumpsys activity services $pkg/app.napstop.core.alarm.ring.AlarmRingService")
        assertTrue(dump, dump.contains("$pkg:ring"))
        assertTrue(dump, dump.contains("isForeground=true"))
        if (Build.VERSION.SDK_INT >= 34) assertTrue(dump, dump.contains("types=00000400"))
    }

    @Test
    fun ai06_backAndVolumeDoNothing() {
        ring()
        assertNotNull(waitDesc(R.string.alarm_stop_a11y))
        device.pressBack()
        device.pressKeyCode(android.view.KeyEvent.KEYCODE_VOLUME_DOWN)
        Thread.sleep(1_000)
        assertNotNull(device.findObject(By.desc(ctx.getString(R.string.alarm_stop_a11y))))
        assertTrue(host.alarm.ringFacts(trip).ringingNow)
    }

    /** Review T16 #1 (the reviewer's repro): a snoozed ring's book from an older boot must not silence the next ring. */
    @Test
    fun ai08_bookOfAnOlderBootDoesNotSilenceTheRing() {
        book.update(trip) {
            app.napstop.core.alarm.RingFactsRecord(
                tripId = trip, ringSeq = 900_000_000_000_000L, ringing = false, mode = app.napstop.core.alarm.RingMode.SERVICE,
                source = RingSource.ENGINE, reason = AlarmReason.DISTANCE, startedAtWallMs = System.currentTimeMillis() - 3_600_000L,
                heartbeatElapsedMs = null, heartbeatWallMs = null, bootCount = 1, pendingDismissAtWallMs = null, snoozedAtWallMs = null,
                silencedAtWallMs = null, endedBy = RingEnd.SNOOZED, stopSeq = 900_000_000_000_000L, restarts = 0,
            )
        }
        ring(reason = AlarmReason.SNOOZE_END, snooze = false)
        assertNotNull("the ring sounds and shows", waitDesc(R.string.alarm_stop_a11y))
        assertTrue(shell("dumpsys activity services $pkg/app.napstop.core.alarm.ring.AlarmRingService").contains("isForeground=true"))
        assertTrue(host.alarm.ringFacts(trip).ringingNow)
    }

    @Test
    fun ai07_overshootVariant() {
        ring(reason = AlarmReason.OVERSHOOT, snooze = false, pastM = 1_200)
        assertNotNull(waitText(R.string.alarm_overline_overshoot, upper = true))
        assertNotNull(device.findObject(By.text(text(R.string.alarm_route_back))))
        assertNull(device.findObject(By.text(ctx.getString(R.string.alarm_snooze_minutes, "1"))))
    }
}
