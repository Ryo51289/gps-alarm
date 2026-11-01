package app.napstop.core.bridge

/**
 * Trip side of the bridge (spec T14 §5.1). T14 ships StubTripBackend; T15 replaces it
 * with the real engine + foreground service in BridgeRegistrar.
 *
 * Stream contract (§2): per engine Step one TripStateUpdateMsg, then the Step's events
 * in T10 §2.3 order; attaching a listener replays the latest state, never old events;
 * no listener, nothing is sent; nothing for a trip after its TripEndedMsg.
 *
 * The backend lives per process, Flutter engines come and go (two can be attached at
 * once, e.g. MainActivity plus a second instance). Each engine owns one listener and
 * removes only that one through its [ListenerHandle] (review T14 M1).
 *
 * All methods are main-safe; listener calls happen on the main thread.
 */
interface TripBackend {
    suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?)

    suspend fun stopTrip(tripId: String)

    /** The running trip; `simulation` is exactly what startTrip received (null for a real trip). */
    suspend fun currentTrip(): ActiveTripMsg?

    suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg)

    suspend fun dismiss(tripId: String)

    suspend fun snooze(tripId: String)

    suspend fun pendingFinishedTrips(): List<FinishedTripMsg>

    suspend fun ackFinishedTrips(tripIds: List<String>)

    /**
     * Adds a listener (one per attached engine); every attached listener receives every
     * update. Attaching replays the latest state (§2 rule 2) as one Step sent to all
     * listeners. Call on the main thread.
     */
    fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle
}

/** Removes exactly the listener it was returned for. Idempotent; call on the main thread. */
fun interface ListenerHandle {
    fun remove()
}
