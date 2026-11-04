package app.napstop.core.alarm.ring.view

import android.content.Context
import android.graphics.Typeface
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.accessibility.AccessibilityManager
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.ShakeDetector

/**
 * "Lắc máy để tắt" (spec T16 D16, §5.8): the accelerometer is registered only while AlarmActivity is visible (Android 9+
 * gives no continuous sensor events in the background). Shows the hint and the progress; with TalkBack an
 * accessibility action stops the alarm too.
 */
class ShakeDismissController(
    private val context: Context,
    private val hint: String,
    private val progressA11y: (percent: Int) -> String,
    private val a11yLabel: String,
    typeface: Typeface?,
    c: AlarmConstants,
    private val onDone: () -> Unit,
) : SensorEventListener {
    private val detector = ShakeDetector(c)
    private val sensors: SensorManager? = context.getSystemService(SensorManager::class.java)
    private val progress: ProgressBar
    private var done = false
    val view: LinearLayout

    init {
        val d = context.resources.displayMetrics.density
        view =
            LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                minimumHeight = (72 * d).toInt()
                isFocusable = true
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            }
        val text =
            TextView(context).apply {
                text = hint
                textSize = 17f
                setTextColor(0xFFFFFFFF.toInt())
                gravity = Gravity.CENTER
                this.typeface = typeface
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }
        progress =
            ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = c.shakePeaksRequired
                progress = 0
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }
        view.addView(text, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        view.addView(
            progress,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (12 * d).toInt()).apply { topMargin = (16 * d).toInt() },
        )
        view.contentDescription = "$hint. ${progressA11y(0)}"
        val am = context.getSystemService(AccessibilityManager::class.java)
        if (am?.isTouchExplorationEnabled == true) {
            ViewCompat.replaceAccessibilityAction(view, AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_CLICK, a11yLabel) { _, _ ->
                finish()
                true
            }
        }
    }

    fun start() {
        val s = sensors ?: return
        val acc = s.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        detector.reset()
        update(0)
        s.registerListener(this, acc, SensorManager.SENSOR_DELAY_GAME)
    }

    fun stop() {
        sensors?.unregisterListener(this)
        detector.reset()
    }

    override fun onSensorChanged(e: SensorEvent) {
        if (done) return
        val p = detector.onSample(e.values[0], e.values[1], e.values[2], SystemClock.elapsedRealtime())
        update(p.count)
        if (p.done) finish()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun update(count: Int) {
        progress.progress = count
        val pct = (count * 100) / progress.max.coerceAtLeast(1)
        view.contentDescription = "$hint. ${progressA11y(pct)}"
    }

    private fun finish() {
        if (done) return
        done = true
        stop()
        onDone()
    }
}
