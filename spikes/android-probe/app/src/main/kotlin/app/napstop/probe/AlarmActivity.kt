package app.napstop.probe

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch

/**
 * Full-screen alarm on the lock screen (S2 §5.3). Opened only through the notification's full-screen intent.
 * `singleInstance`: a later alarm reuses this instance through [onNewIntent], so it always shows the current run and closes
 * itself whenever no alarm is ringing ([AlarmState], Vòng 4 #3).
 */
class AlarmActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // No requestDismissKeyguard: the user dismisses without unlocking.

        setContentView(R.layout.activity_alarm)
        findViewById<View>(R.id.alarmRoot).applySystemBarsPadding()
        bind(intent)
        findViewById<Button>(R.id.btnDismiss).setOnClickListener {
            // Routed to the service that rings (S2 Vòng 4 V4-1).
            val dismiss = if (AlarmState.owner == AlarmState.OWNER_RING) {
                AlarmRingService.dismissIntent(this, ProbeService.BY_ACTIVITY)
            } else {
                ProbeService.dismissIntent(this, ProbeService.BY_ACTIVITY)
            }
            startService(dismiss)
            finish()
        }

        // Back does not dismiss the alarm.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = Unit
        })

        if (savedInstanceState == null) logShown()

        // Close when the alarm is not (or no longer) ringing: notification action, "Dừng lượt", timeout, stale intent.
        // Collected for the whole life of the activity (not only while STARTED), so a stopped instance is closed too.
        lifecycleScope.launch {
            AlarmState.active.filter { !it }.collect { finish() }
        }
    }

    /** FSI of a later alarm while this (singleInstance) activity still exists: show that alarm, log it like a new screen. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bind(intent)
        logShown()
    }

    override fun onStart() {
        super.onStart()
        if (!AlarmState.active.value) finish()
    }

    private fun bind(intent: Intent) {
        findViewById<TextView>(R.id.alarmPlanned).text =
            getString(R.string.alarm_planned, intent.getStringExtra(EXTRA_PLANNED).orEmpty())
        findViewById<TextView>(R.id.alarmSource).text =
            getString(R.string.alarm_source, intent.getStringExtra(EXTRA_SRC).orEmpty())
    }

    /** Only while an alarm rings: a screen that closes at once in onStart is not "shown". */
    private fun logShown() {
        if (!AlarmState.active.value) return
        val keyguardLocked = getSystemService(KeyguardManager::class.java).isKeyguardLocked
        val interactiveBefore = AlarmState.interactiveAtTrigger
        EventLog.log(
            "alarm_ui_shown",
            "keyguardLocked" to keyguardLocked,
            "interactive" to getSystemService(PowerManager::class.java).isInteractive,
            "viaFsi" to (keyguardLocked || interactiveBefore == false),
        )
    }

    companion object {
        private const val EXTRA_PLANNED = "planned"
        private const val EXTRA_SRC = "src"

        fun intent(context: Context, plannedClock: String, src: String): Intent =
            Intent(context, AlarmActivity::class.java)
                .putExtra(EXTRA_PLANNED, plannedClock)
                .putExtra(EXTRA_SRC, src)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
    }
}
