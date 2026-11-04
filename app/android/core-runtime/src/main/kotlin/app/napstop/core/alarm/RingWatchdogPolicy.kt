package app.napstop.core.alarm

/** What the main-process watchdog does at one tick (spec T16 §5.3, D6). */
sealed interface WatchAction {
    data object None : WatchAction

    data object StopWatching : WatchAction

    data class Restart(val restartNo: Int) : WatchAction

    data object Backup : WatchAction

    data class Silence(val atWallMs: Long) : WatchAction
}

object RingWatchdogPolicy {
    fun decide(r: RingFactsRecord?, starting: StartingMarker?, env: LivenessEnv, c: AlarmConstants): WatchAction {
        if (starting != null && (r == null || r.ringSeq < starting.ringSeq)) {
            // :ring has not confirmed this ring yet.
            if (r?.stopSeq != null && r.stopSeq >= starting.ringSeq) return WatchAction.StopWatching
            if (env.nowElapsedMs - starting.atElapsedMs <= c.ringConfirmMs) return WatchAction.None
            return restartOrBackup(r?.restarts ?: 0, c)
        }
        if (r == null || !r.ringing || r.pendingDismissAtWallMs != null) return WatchAction.StopWatching
        if (RingLiveness.alive(r, env, c)) return WatchAction.None
        if (env.nowWallMs >= r.startedAtWallMs + c.ringMaxMs) return WatchAction.Silence(r.startedAtWallMs + c.ringMaxMs)
        // The backup notification is gone (swiped / cancelled by the system).
        if (r.mode == RingMode.BACKUP) return WatchAction.Silence(env.nowWallMs)
        return restartOrBackup(r.restarts, c)
    }

    private fun restartOrBackup(n: Int, c: AlarmConstants): WatchAction = if (n < c.ringRestartMax) WatchAction.Restart(n + 1) else WatchAction.Backup
}
