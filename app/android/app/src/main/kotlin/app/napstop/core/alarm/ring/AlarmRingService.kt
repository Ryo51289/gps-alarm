package app.napstop.core.alarm.ring

import android.app.AlarmManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.ServiceCompat
import app.napstop.core.alarm.AlarmChannels
import app.napstop.core.alarm.AppLocale
import app.napstop.core.alarm.FgsType
import app.napstop.core.alarm.FgsTypePolicy
import app.napstop.core.alarm.RingIntents

/**
 * The ring foreground service of spec T16 D1, D2, §5.4, in process `:ring` (RK14: it keeps ringing when the main process
 * dies). startForeground is the first thing of every start; the type follows [FgsTypePolicy] (`systemExempted` with exact
 * alarm access on API 34+, else `mediaPlayback`; `0` below API 29). START_STICKY: a restart without intent plays the live
 * ring of the book on (§8). All the work is in [RingSession] on its own thread.
 */
class AlarmRingService : Service() {
    private lateinit var session: RingSession
    private val journal by lazy { RingJournalSink.create(this) }
    @Volatile
    private var lastStartId = 0

    /** Type the service runs with (journal ring_start.fg). */
    @Volatile
    var fgType: FgsType? = null
        private set

    override fun onCreate() {
        super.onCreate()
        AlarmChannels.ensure(this)
        session = RingSession.get(this)
        session.attach(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        // Runs on the ring thread before this start's work: a stop decided for an older start leaves this one alone.
        session.noteStartId(startId)
        // Parsed once (in memory); its tag names the placeholder (T28), else the session's.
        val start = if (intent?.action == RingIntents.ACTION_RING_START) RingIntents.fromBundle(intent.extras) else null
        if (!startForegroundFirst(start?.localeTag ?: session.localeTag)) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        when (intent?.action) {
            RingIntents.ACTION_RING_START -> {
                if (start == null) session.stopServiceIfIdle() else session.start(start)
            }
            RingIntents.ACTION_RING_ADOPT -> {
                val trip = RingIntents.validTripId(intent.getStringExtra(RingIntents.EXTRA_TRIP_ID))
                val start = RingIntents.fromBundle(intent.getBundleExtra(RingIntents.EXTRA_RING_START))?.takeIf { it.request.tripId == trip }
                if (trip == null) session.stopServiceIfIdle() else session.adopt(trip, start)
            }
            null -> session.stickyRestart()
            else -> session.stopServiceIfIdle()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        session.onServiceDestroyed(this)
        super.onDestroy()
    }

    /**
     * Called by the session (ring thread): the ring is over. [handledStartId] = the last start the session handled; a newer
     * start (RING_START already in onStartCommand, its work queued on the ring thread) keeps the service (review T16 #3).
     */
    fun stopRing(handledStartId: Int) {
        if (handledStartId != lastStartId) return
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            Log.w(TAG, "stopForeground failed (${e.javaClass.simpleName})")
        }
        stopSelfResult(handledStartId)
    }

    private fun startForegroundFirst(localeTag: String?): Boolean {
        val notif = RingNotifications.placeholder(this, AppLocale.localizedWith(this, localeTag))
        for (t in FgsTypePolicy.ringTypes(Build.VERSION.SDK_INT, canScheduleExact())) {
            try {
                ServiceCompat.startForeground(this, RingNotifications.ID_RING_FGS, notif, androidType(t))
                fgType = t
                return true
            } catch (e: Exception) {
                journal.log("ring_fg_fail", mapOf("type" to t.name, "ex" to e.javaClass.simpleName))
                Log.w(TAG, "startForeground $t failed (${e.javaClass.simpleName})")
            }
        }
        return false
    }

    private fun canScheduleExact(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() ?: false
            } catch (e: Exception) {
                false
            }
        } else {
            true
        }

    private fun androidType(t: FgsType): Int =
        when (t) {
            FgsType.SYSTEM_EXEMPTED -> if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED else 0
            FgsType.MEDIA_PLAYBACK -> if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0
            FgsType.NONE -> 0
        }

    private companion object {
        const val TAG = "NapStopRing"
    }
}
