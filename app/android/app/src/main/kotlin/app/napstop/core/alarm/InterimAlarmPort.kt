package app.napstop.core.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.util.Log
import androidx.core.app.NotificationCompat
import app.napstop.R
import app.napstop.core.trip.host.RingEventReceiver
import app.napstop.core.trip.host.TripNotifications
import app.napstop.core.trip.runtime.NoticeFormatter
import app.napstop.core.trip.runtime.RingEventKind
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.Properties
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Interim [AlarmPort] of T15 (spec §3, RK-T15-7) so the runtime can be tested before T16: the "ring" is a
 * high-importance notification on channel `napstop_alarm_interim` with the alarm sound (USAGE_ALARM), FLAG_INSISTENT
 * (repeats until handled), a full-screen intent to MainActivity, Dismiss / Snooze actions and a delete intent, all
 * sent to [RingEventReceiver] as RING_EVENT. It stops by itself after [MAX_RING_MS] (→ SILENCED). Ring facts live in
 * noBackupFilesDir/napstop_ring/<tripId>.properties; `ringingNow` also requires the notification to be showing, so a
 * dead process or a swiped notification never reports a ring that is not there. DND / silent mode may mute it.
 * When the notification cannot be posted (POST_NOTIFICATIONS denied, notifications off) the alarm sound plays directly
 * on the alarm stream (review T15 #3); only if that fails too does ring() throw. The user then stops it in the app.
 */
@Deprecated("Replaced by T16 AlarmController")
class InterimAlarmPort(
    context: Context,
    private val scope: CoroutineScope,
    private val notifications: TripNotifications,
    /** Auto-stop seen while the process lives: RING_EVENT SILENCED to the runtime. */
    private val onAutoSilenced: (tripId: String, atWallMs: Long) -> Unit,
) : AlarmPort {
    private val ctx = context.applicationContext
    private val dir = File(ctx.noBackupFilesDir, DIR_NAME)
    private val nm: NotificationManager? get() = ctx.getSystemService(NotificationManager::class.java)
    private val lock = Any()
    private val players = ConcurrentHashMap<String, MediaPlayer>()

    override fun ringNow(request: RingRequest) {
        // Debug `ring_fail on` (protocol LM7): the "now" ring cannot start, as when T16 cannot start AlarmRingService.
        if (app.napstop.core.trip.host.RuntimeDebugFlags.ringFail) throw IllegalStateException("debug ring_fail")
        ring(request)
    }

    override fun ringFallback(request: RingRequest) = ring(request)

    private fun ring(request: RingRequest) {
        ensureChannel()
        val facts = read(request.tripId)
        val already = facts.ringing && isShowing(request.tripId)
        // One ring per trip: an active ring only gets its content updated (same id, setOnlyAlertOnce).
        val notification = build(request, onlyAlertOnce = already)
        val posted =
            try {
                val manager = nm ?: throw IllegalStateException("no NotificationManager")
                if (!manager.areNotificationsEnabled()) throw IllegalStateException("notifications disabled")
                manager.notify(request.tripId, ID_RING, notification)
                true
            } catch (e: Exception) {
                Log.w(TAG, "interim notification failed (${e.javaClass.simpleName}), playing on the alarm stream")
                false
            }
        if (!posted && !already && !playDirect(request.tripId)) throw IllegalStateException("cannot ring")
        if (!already) {
            write(request.tripId, facts.copy(ringing = true, source = request.source, startedAtWallMs = request.atWallMs))
            val started = request.atWallMs
            scope.launch {
                delay(MAX_RING_MS)
                stopDirect(request.tripId)
                delay(2_000)
                val f = read(request.tripId)
                if (f.ringing && f.startedAtWallMs == started && !isShowing(request.tripId)) {
                    val at = started + MAX_RING_MS
                    write(request.tripId, f.copy(ringing = false, silencedAtWallMs = at))
                    onAutoSilenced(request.tripId, at)
                }
            }
        }
    }

    override fun stopRinging(tripId: String, cause: StopCause) {
        stopDirect(tripId)
        try {
            nm?.cancel(tripId, ID_RING)
        } catch (e: Exception) {
            Log.w(TAG, "interim cancel failed (${e.javaClass.simpleName})")
        }
        val f = read(tripId)
        val handledSnooze = if (cause == StopCause.SNOOZED) null else f.pendingSnoozeAtWallMs
        if (f.ringing || handledSnooze != f.pendingSnoozeAtWallMs) write(tripId, f.copy(ringing = false, pendingSnoozeAtWallMs = handledSnooze))
    }

    override fun preAlert(request: PreAlertRequest) {
        val name = request.destinationName ?: ctx.getString(R.string.notif_destination_unknown)
        val text = ctx.getString(R.string.notif_tracking_distance, NoticeFormatter.distance(request.distanceM.toDouble(), notifications.locale()))
        val n =
            NotificationCompat.Builder(ctx, TripNotifications.CHANNEL_ALERTS)
                .setSmallIcon(R.drawable.ic_stat_napstop)
                .setContentTitle(ctx.getString(R.string.notif_alarm_interim_title, name))
                .setContentText(text)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setAutoCancel(true)
                .setContentIntent(TripNotifications.openAppIntent(ctx, REQ_OPEN, null))
                .build()
        notifications.ensureChannels()
        try {
            nm?.notify(request.tripId, TripNotifications.ID_PRE_ALERT, n)
        } catch (e: Exception) {
            Log.w(TAG, "pre-alert failed (${e.javaClass.simpleName})")
        }
    }

    override fun overshoot(tripId: String, pastM: Int) = Unit // the interim notification has no overshoot copy

    override fun ringFacts(tripId: String): RingFacts {
        val f = read(tripId)
        // Contract (designer "sau test" §1): ringing from the moment ring() returned; a ring asked for ≤ 10 s ago counts
        // while the notification / player starts.
        val starting = f.startedAtWallMs?.let { System.currentTimeMillis() - it in 0..STARTING_MS } == true
        val live = f.ringing && (starting || isShowing(tripId))
        return RingFacts(
            ringingNow = live,
            ringingSource = if (live) f.source else null,
            ringStartedAtWallMs = f.startedAtWallMs,
            pendingDismissAtWallMs = f.pendingDismissAtWallMs,
            silencedAtWallMs = f.silencedAtWallMs ?: if (f.ringing && !live) f.startedAtWallMs?.plus(MAX_RING_MS) else null,
            pendingSnoozeAtWallMs = f.pendingSnoozeAtWallMs,
        )
    }

    override fun clearTrip(tripId: String) {
        synchronized(lock) { File(dir, "$tripId.properties").delete() }
    }

    /** Notification action / delete intent, before the runtime gets the event (records pendingDismiss like T16 must). */
    fun onNotificationEvent(tripId: String, kind: RingEventKind, atWallMs: Long) {
        val f = read(tripId)
        when (kind) {
            RingEventKind.DISMISSED -> {
                write(tripId, f.copy(ringing = false, pendingDismissAtWallMs = atWallMs))
                nm?.cancel(tripId, ID_RING)
                stopDirect(tripId)
            }
            RingEventKind.SNOOZED -> {
                // Recorded before the runtime gets RING_EVENT SNOOZED; cleared by stopRinging(SNOOZED).
                write(tripId, f.copy(ringing = false, pendingSnoozeAtWallMs = atWallMs))
                nm?.cancel(tripId, ID_RING)
                stopDirect(tripId)
            }
            RingEventKind.SILENCED -> write(tripId, f.copy(ringing = false, silencedAtWallMs = atWallMs))
            RingEventKind.FALLBACK_RINGING -> Unit
        }
    }

    // ------------------------------------------------------------------ notification

    private fun ensureChannel() {
        val m = nm ?: return
        if (m.getNotificationChannel(CHANNEL) != null) return
        val ch = NotificationChannel(CHANNEL, ctx.getString(R.string.notif_channel_alarm_interim), NotificationManager.IMPORTANCE_HIGH)
        ch.setSound(
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        )
        ch.enableVibration(true)
        ch.setBypassDnd(true) // only honoured if the user allows it for the channel
        m.createNotificationChannel(ch)
    }

    private fun build(r: RingRequest, onlyAlertOnce: Boolean): Notification {
        val name = r.destinationName ?: ctx.getString(R.string.notif_destination_unknown)
        val body =
            when {
                r.source == RingSource.FALLBACK || r.reason == app.napstop.core.trip.AlarmReason.FALLBACK ||
                    r.reason == app.napstop.core.trip.AlarmReason.FALLBACK_MISSED -> ctx.getString(R.string.alarm_reason_fallback, name)
                r.distanceM != null ->
                    ctx.getString(R.string.notif_tracking_distance, NoticeFormatter.distance(r.distanceM!!.toDouble(), notifications.locale()))
                else -> ctx.getString(R.string.notif_tracking_alarming)
            }
        val open = TripNotifications.openAppIntent(ctx, REQ_OPEN, null)
        val b =
            NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_napstop)
                .setContentTitle(ctx.getString(R.string.notif_alarm_interim_title, name))
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setOnlyAlertOnce(onlyAlertOnce)
                .setTimeoutAfter(MAX_RING_MS)
                .setContentIntent(open)
                .setFullScreenIntent(open, true)
                .setDeleteIntent(event(r.tripId, RingEventKind.SILENCED, REQ_DELETE))
                .addAction(0, ctx.getString(R.string.notif_action_dismiss), event(r.tripId, RingEventKind.DISMISSED, REQ_DISMISS))
        if (r.snoozeAllowed) b.addAction(0, ctx.getString(R.string.notif_action_snooze), event(r.tripId, RingEventKind.SNOOZED, REQ_SNOOZE))
        return b.build().apply { flags = flags or Notification.FLAG_INSISTENT }
    }

    private fun event(tripId: String, kind: RingEventKind, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            ctx,
            requestCode,
            Intent(ctx, RingEventReceiver::class.java)
                .setAction(RingEventReceiver.ACTION_RING_EVENT)
                .putExtra(RingEventReceiver.EXTRA_TRIP_ID, tripId)
                .putExtra(RingEventReceiver.EXTRA_KIND, kind.name)
                .putExtra(RingEventReceiver.EXTRA_INTERIM, true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun isShowing(tripId: String): Boolean =
        players[tripId]?.let { runCatching { it.isPlaying }.getOrDefault(false) } == true ||
            try {
                nm?.activeNotifications?.any { it.id == ID_RING && it.tag == tripId } ?: false
            } catch (e: Exception) {
                false
            }

    /**
     * Alarm sound straight on the alarm stream, looping, when no notification can be shown. The default alarm sound may
     * be unset or deleted (review T15 R2-4): then the ringtone, then the notification sound.
     */
    private fun playDirect(tripId: String): Boolean {
        for (type in intArrayOf(RingtoneManager.TYPE_ALARM, RingtoneManager.TYPE_RINGTONE, RingtoneManager.TYPE_NOTIFICATION)) {
            val uri = RingtoneManager.getDefaultUri(type) ?: continue
            val mp = MediaPlayer()
            try {
                mp.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                mp.setDataSource(ctx, uri)
                mp.isLooping = true
                mp.prepare()
                mp.start()
                players.put(tripId, mp)?.release()
                return true
            } catch (e: Exception) {
                mp.release()
                Log.w(TAG, "direct alarm failed (${e.javaClass.simpleName}), type $type")
            }
        }
        return false
    }

    private fun stopDirect(tripId: String) {
        players.remove(tripId)?.let {
            runCatching { it.stop() }
            it.release()
        }
    }

    // ------------------------------------------------------------------ facts file

    private data class Facts(
        val ringing: Boolean = false,
        val source: RingSource? = null,
        val startedAtWallMs: Long? = null,
        val pendingDismissAtWallMs: Long? = null,
        val silencedAtWallMs: Long? = null,
        val pendingSnoozeAtWallMs: Long? = null,
    )

    private fun read(tripId: String): Facts =
        synchronized(lock) {
            val f = File(dir, "$tripId.properties")
            if (!f.exists()) return@synchronized Facts()
            try {
                val p = Properties().apply { f.inputStream().use { load(it) } }
                Facts(
                    ringing = p.getProperty("ringing") == "true",
                    source = p.getProperty("source")?.let { s -> RingSource.entries.firstOrNull { it.name == s } },
                    startedAtWallMs = p.getProperty("startedAtWallMs")?.toLongOrNull(),
                    pendingDismissAtWallMs = p.getProperty("pendingDismissAtWallMs")?.toLongOrNull(),
                    silencedAtWallMs = p.getProperty("silencedAtWallMs")?.toLongOrNull(),
                    pendingSnoozeAtWallMs = p.getProperty("pendingSnoozeAtWallMs")?.toLongOrNull(),
                )
            } catch (e: Exception) {
                Log.w(TAG, "ring facts invalid (${e.javaClass.simpleName})")
                Facts()
            }
        }

    private fun write(tripId: String, facts: Facts) {
        synchronized(lock) {
            try {
                if (!dir.isDirectory) dir.mkdirs()
                val p = Properties()
                p["ringing"] = facts.ringing.toString()
                facts.source?.let { p["source"] = it.name }
                facts.startedAtWallMs?.let { p["startedAtWallMs"] = it.toString() }
                facts.pendingDismissAtWallMs?.let { p["pendingDismissAtWallMs"] = it.toString() }
                facts.silencedAtWallMs?.let { p["silencedAtWallMs"] = it.toString() }
                facts.pendingSnoozeAtWallMs?.let { p["pendingSnoozeAtWallMs"] = it.toString() }
                val tmp = File(dir, "$tripId.properties.tmp")
                tmp.outputStream().use { out ->
                    p.store(out, null)
                    out.fd.sync()
                }
                if (!tmp.renameTo(File(dir, "$tripId.properties"))) throw java.io.IOException("rename")
            } catch (e: Exception) {
                Log.w(TAG, "ring facts write failed (${e.javaClass.simpleName})")
            }
        }
    }

    companion object {
        private const val TAG = "NapStopRuntime"
        const val CHANNEL = "napstop_alarm_interim"
        const val DIR_NAME = "napstop_ring"
        const val ID_RING = 1201
        const val MAX_RING_MS = 5 * 60_000L
        private const val STARTING_MS = 10_000L
        private const val REQ_OPEN = 0x4E5740
        private const val REQ_DISMISS = 0x4E5741
        private const val REQ_SNOOZE = 0x4E5742
        private const val REQ_DELETE = 0x4E5743
    }
}
