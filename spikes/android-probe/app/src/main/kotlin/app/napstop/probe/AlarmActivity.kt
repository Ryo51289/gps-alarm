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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch

/** Full-screen alarm on the lock screen (S2 §5.3). Opened only through the notification's full-screen intent. */
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
        findViewById<TextView>(R.id.alarmPlanned).text =
            getString(R.string.alarm_planned, intent.getStringExtra(EXTRA_PLANNED).orEmpty())
        findViewById<TextView>(R.id.alarmSource).text =
            getString(R.string.alarm_source, intent.getStringExtra(EXTRA_SRC).orEmpty())
        findViewById<Button>(R.id.btnDismiss).setOnClickListener {
            startService(ProbeService.dismissIntent(this, ProbeService.BY_ACTIVITY))
            finish()
        }

        // Back does not dismiss the alarm.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = Unit
        })

        if (savedInstanceState == null) {
            val keyguardLocked = getSystemService(KeyguardManager::class.java).isKeyguardLocked
            val interactiveBefore = ProbeService.interactiveAtTrigger
            EventLog.log(
                "alarm_ui_shown",
                "keyguardLocked" to keyguardLocked,
                "interactive" to getSystemService(PowerManager::class.java).isInteractive,
                "viaFsi" to (keyguardLocked || interactiveBefore == false),
            )
        }

        // Close when the alarm is not (or no longer) ringing: notification action, timeout, stale intent.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                ProbeService.alarmActive.filter { !it }.collect { finish() }
            }
        }
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
