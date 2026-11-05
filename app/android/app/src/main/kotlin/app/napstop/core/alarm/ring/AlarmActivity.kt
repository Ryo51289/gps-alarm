package app.napstop.core.alarm.ring

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import app.napstop.R
import app.napstop.core.alarm.AlarmConstantsHolder
import app.napstop.core.alarm.AppLocale
import app.napstop.core.alarm.DismissMethod
import app.napstop.core.alarm.LaunchActions
import app.napstop.core.alarm.MathChallenge
import app.napstop.core.alarm.RingContent
import app.napstop.core.alarm.RingFactsStore
import app.napstop.core.alarm.RingIntents
import app.napstop.core.alarm.RingPhase
import app.napstop.core.alarm.RingStrings
import app.napstop.core.alarm.RingVariant
import app.napstop.core.alarm.ring.view.MathKeypadView
import app.napstop.core.alarm.ring.view.ShakeDismissController
import app.napstop.core.alarm.ring.view.SwipeToDismissView
import java.io.File
import java.security.SecureRandom
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * The alarm screen (screen 5, and screen 8 while ringing) of spec T16 D8, D9, §5.8 — the only alarm UI, native, in
 * `:ring`. Shows over the lock screen and turns the screen on; never dismisses the keyguard to stop (only "Xem đường
 * quay lại" does). Back and volume keys do nothing. It renders [RingSession.state] and sends the user's dismiss /
 * snooze to the session. Opened from the backup notification, it asks the service to adopt the ring (D4).
 *
 * Strings follow the ring's app language (T28 D9): the `localeTag` of the RING_START this activity was opened with
 * (backup notification), else the session's. Not through attachBaseContext: the intent is not known there yet, and the
 * session learns the language only when its start runs. Every render reads it again.
 */
class AlarmActivity : Activity() {
    private lateinit var session: RingSession
    private var scope: CoroutineScope? = null
    private var tripId: String? = null
    private var seenRinging = false
    private var method: DismissMethod? = null
    private var shake: ShakeDismissController? = null
    private var glowAnim: ObjectAnimator? = null
    private var variant: RingVariant? = null
    private var handledEnd = false

    /** Language the dismiss control was built with (rebuilt when it changes, T28). */
    private var dismissTag: String? = null

    private lateinit var glow: View
    private lateinit var overline: TextView
    private lateinit var title: TextView
    private lateinit var subtitle: TextView
    private lateinit var past: TextView
    private lateinit var banner: TextView
    private lateinit var routeBack: Button
    private lateinit var dismissArea: FrameLayout
    private lateinit var snooze: Button

    private val giveUp = Runnable { if (!seenRinging) finish() }

    /** The ring's language; never the language file (this is `:ring`). */
    private fun localeTag(): String? =
        RingIntents.fromBundle(intent?.getBundleExtra(RingIntents.EXTRA_RING_START))?.localeTag ?: session.localeTag

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_alarm)
        bindViews()
        applyInsets()
        if (Build.VERSION.SDK_INT >= 33) {
            // Back does nothing while ringing (the dismiss method decides).
            onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT) {}
        }
        session = RingSession.get(this)
        tripId = RingIntents.validTripId(intent.getStringExtra(RingIntents.EXTRA_TRIP_ID))
        observe()
        adoptIfNeeded()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        RingIntents.validTripId(intent.getStringExtra(RingIntents.EXTRA_TRIP_ID))?.let { if (!seenRinging) tripId = it }
        adoptIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        shake?.start()
    }

    override fun onPause() {
        shake?.stop()
        super.onPause()
    }

    override fun onDestroy() {
        scope?.cancel()
        scope = null
        glowAnim?.cancel()
        window.decorView.removeCallbacks(giveUp)
        super.onDestroy()
    }

    @Deprecated("Back does nothing on the alarm screen")
    override fun onBackPressed() = Unit

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        when (event.keyCode) {
            // No sleepy thumb lowers the alarm by accident.
            KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_VOLUME_MUTE, KeyEvent.KEYCODE_BACK -> true
            else -> super.dispatchKeyEvent(event)
        }

    /** targetSdk 36: edge-to-edge on API 35+; keep the swipe bar and buttons clear of the system bars (review T16 #8). */
    private fun applyInsets() {
        val root = findViewById<View>(R.id.alarm_content)
        val l = root.paddingLeft
        val t = root.paddingTop
        val r = root.paddingRight
        val b = root.paddingBottom
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars() or androidx.core.view.WindowInsetsCompat.Type.displayCutout())
            v.setPadding(l + bars.left, t + bars.top, r + bars.right, b + bars.bottom)
            insets
        }
    }

    private fun bindViews() {
        glow = findViewById(R.id.alarm_glow)
        overline = findViewById(R.id.alarm_overline)
        title = findViewById(R.id.alarm_title)
        subtitle = findViewById(R.id.alarm_subtitle)
        past = findViewById(R.id.alarm_past)
        banner = findViewById(R.id.alarm_banner)
        routeBack = findViewById(R.id.alarm_route_back)
        dismissArea = findViewById(R.id.alarm_dismiss_area)
        snooze = findViewById(R.id.alarm_snooze)
        val bold = AlarmFonts.get(this, AlarmFonts.Weight.BOLD)
        val regular = AlarmFonts.get(this, AlarmFonts.Weight.REGULAR)
        val semi = AlarmFonts.get(this, AlarmFonts.Weight.SEMI_BOLD)
        bold?.let {
            overline.typeface = it
            title.typeface = it
        }
        regular?.let {
            subtitle.typeface = it
            past.typeface = it
            banner.typeface = it
        }
        semi?.let {
            routeBack.typeface = it
            snooze.typeface = it
        }
        val d = resources.displayMetrics.density
        routeBack.background = GradientDrawable().apply {
            setColor(0xFFFFFFFF.toInt())
            cornerRadius = 28 * d
        }
        routeBack.setOnClickListener { session.userDismiss(routeBack = true) }
        snooze.background = GradientDrawable().apply {
            setColor(0x00000000)
            setStroke((2 * d).toInt(), getColor(R.color.alarm_outline))
            cornerRadius = 28 * d
        }
        snooze.setOnClickListener { session.userSnooze() }
    }

    private fun observe() {
        val s = MainScope()
        scope = s
        s.launch {
            session.state.collect { st ->
                val mine = tripId == null || st.tripId == tripId
                if (st.phase == RingPhase.RINGING && mine && st.content != null) {
                    seenRinging = true
                    tripId = st.tripId
                    render(st.content, st.method, st.banner)
                } else if (seenRinging && mine && st.phase != RingPhase.RINGING) {
                    onEnded(st.routeBack)
                }
            }
        }
    }

    /** Not ringing in this process for our trip: the backup notification rings → start the service and adopt it. */
    private fun adoptIfNeeded() {
        val st = session.state.value
        if (st.phase == RingPhase.RINGING && (tripId == null || st.tripId == tripId)) return
        val trip = tripId
        if (trip == null) {
            window.decorView.postDelayed(giveUp, ADOPT_WAIT_MS)
            return
        }
        // Book read off the main thread (ring thread).
        session.handler.post {
            val r =
                try {
                    RingFactsStore(File(noBackupFilesDir, RingFactsStore.DIR_NAME)).read(trip)
                } catch (e: Exception) {
                    null
                }
            val ringing = r != null && r.ringing && r.pendingDismissAtWallMs == null
            runOnUiThread {
                if (!ringing) {
                    if (!seenRinging) finish()
                    return@runOnUiThread
                }
                try {
                    // The activity is visible: it may start the foreground service (D4).
                    startForegroundService(RingIntents.adoptService(this, trip, intent.getBundleExtra(RingIntents.EXTRA_RING_START)))
                } catch (e: Exception) {
                    android.util.Log.w("NapStopRing", "adopt failed (${e.javaClass.simpleName})")
                }
                window.decorView.postDelayed(giveUp, ADOPT_WAIT_MS)
            }
        }
    }

    private fun render(content: RingContent, m: DismissMethod, bannerKey: String?) {
        val tag = localeTag()
        val res = AppLocale.localizedWith(this, tag)
        val overshoot = content.variant == RingVariant.OVERSHOOT
        val overlineText = res.getString(if (overshoot) R.string.alarm_overline_overshoot else R.string.alarm_overline_arriving)
        // Upper case in code (not textAllCaps) so TalkBack and UI tests read the same text.
        overline.text = overlineText.uppercase(AppLocale.localeWith(this, tag))
        overline.setTextColor(getColor(if (overshoot) R.color.alarm_overline_overshoot else R.color.alarm_accent))
        val name = RingStrings.title(res, content)
        title.text = name
        subtitle.text = RingStrings.text(res, content.subtitle)
        val pastLine = content.pastLine
        past.visibility = if (pastLine != null) View.VISIBLE else View.GONE
        if (pastLine != null) past.text = RingStrings.text(res, pastLine)
        banner.visibility = if (bannerKey != null) View.VISIBLE else View.GONE
        if (bannerKey != null) banner.text = RingStrings.key(res, bannerKey)
        routeBack.text = res.getString(R.string.alarm_route_back)
        routeBack.visibility = if (overshoot) View.VISIBLE else View.GONE
        val label = content.snoozeLabel
        snooze.visibility = if (label != null) View.VISIBLE else View.GONE
        if (label != null) snooze.text = RingStrings.text(res, label)
        setTitle("$overlineText. $name")
        if (variant != content.variant) {
            variant = content.variant
            setGlow(overshoot)
        }
        if (method != m || dismissTag != tag) {
            method = m
            dismissTag = tag
            buildDismiss(m, res)
        }
    }

    private fun setGlow(overshoot: Boolean) {
        val color = getColor(if (overshoot) R.color.alarm_overshoot else R.color.alarm_accent)
        glow.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
        }
        glow.backgroundTintList = ColorStateList.valueOf(color)
        glowAnim?.cancel()
        glow.alpha = 1f
        // Reduced motion (animator duration scale 0): static.
        if (ValueAnimator.areAnimatorsEnabled()) {
            glowAnim =
                ObjectAnimator.ofFloat(glow, View.ALPHA, 1f, 0.35f).apply {
                    duration = 600
                    repeatCount = ValueAnimator.INFINITE
                    repeatMode = ValueAnimator.REVERSE
                    start()
                }
        }
    }

    private fun buildDismiss(m: DismissMethod, res: Context) {
        shake?.stop()
        shake = null
        dismissArea.removeAllViews()
        val semi = AlarmFonts.get(this, AlarmFonts.Weight.SEMI_BOLD)
        val stopLabel = res.getString(R.string.alarm_stop_a11y)
        // No accelerometer (or no sensor service): shaking could never stop the alarm → swipe (review T16 #5).
        val hasAccel = getSystemService(android.hardware.SensorManager::class.java)?.getDefaultSensor(android.hardware.Sensor.TYPE_ACCELEROMETER) != null
        val method = if (m == DismissMethod.SHAKE && !hasAccel) DismissMethod.SWIPE else m
        val v: View =
            when (method) {
                DismissMethod.SWIPE ->
                    SwipeToDismissView(this, res.getString(R.string.alarm_swipe_hint), stopLabel, semi) { session.userDismiss(routeBack = false) }
                DismissMethod.SHAKE ->
                    ShakeDismissController(
                        this, res.getString(R.string.alarm_shake_hint), { pct -> res.getString(R.string.alarm_shake_progress_a11y, pct.toString()) },
                        stopLabel, semi, AlarmConstantsHolder.load(this),
                    ) { session.userDismiss(routeBack = false) }.also {
                        shake = it
                        it.start()
                    }.view
                DismissMethod.MATH ->
                    MathKeypadView(
                        this, MathChallenge(SecureRandom()), res.getString(R.string.alarm_math_hint), res.getString(R.string.alarm_math_wrong),
                        res.getString(R.string.alarm_math_delete), res.getString(R.string.alarm_math_confirm), semi,
                    ) { session.userDismiss(routeBack = false) }
            }
        dismissArea.addView(v, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))
    }

    private fun onEnded(routeBackPressed: Boolean) {
        if (handledEnd) return
        handledEnd = true
        if (!routeBackPressed) {
            finish()
            return
        }
        val trip = tripId
        // T27 D6: how far past the destination, for "Đã qua …" on screen 8 (read before finish).
        val pastM = session.state.value.overshootPastM
        val open = {
            try {
                startActivity(
                    Intent().setClassName(packageName, MAIN_ACTIVITY)
                        .putExtra(LaunchActions.EXTRA_LAUNCH, LaunchActions.OVERSHOOT_ROUTE)
                        .putExtra(LaunchActions.EXTRA_TRIP_ID, trip)
                        .also { i -> if (pastM != null) i.putExtra(LaunchActions.EXTRA_PAST_M, pastM) }
                        // Review T27 #1: MainActivity drops an action older than 10 min (a replayed task intent).
                        .putExtra(LaunchActions.EXTRA_AT_WALL_MS, System.currentTimeMillis())
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (e: Exception) {
                android.util.Log.w("NapStopRing", "route back failed (${e.javaClass.simpleName})")
            }
            finish()
        }
        val km = getSystemService(KeyguardManager::class.java)
        if (km == null || !km.isKeyguardLocked) {
            open()
            return
        }
        km.requestDismissKeyguard(
            this,
            object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() = open()

                // Shown after the user unlocks.
                override fun onDismissCancelled() = open()

                override fun onDismissError() = open()
            },
        )
    }

    private companion object {
        const val ADOPT_WAIT_MS = 6_000L
        const val MAIN_ACTIVITY = "app.napstop.MainActivity"
    }
}
