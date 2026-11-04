package app.napstop.core.bridge

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Trip backend of the app until T18 (spec T15 D14, §5.13): `simulation.traceAsset` starting with `stub/` keeps the T14
 * [stub] behaviour (UI and integration tests); any other simulation is `simulation-unavailable` until T18; a real trip
 * goes to [real]. At most one trip at a time across both. Commands with a tripId go to the backend that runs a trip
 * (real first); an unknown tripId stays a no-op in both (T14 D10).
 */
class CompositeTripBackend(private val real: TripBackend, private val stub: TripBackend) : TripBackend {
    /** One start at a time across both backends (review T15 #8): a second start while one is pending is trip-active. */
    private val starting = AtomicBoolean(false)

    override suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) {
        if (!starting.compareAndSet(false, true)) throw FlutterError(BridgeErrors.TRIP_ACTIVE, null, null)
        try {
            if (real.currentTrip() != null || stub.currentTrip() != null) throw FlutterError(BridgeErrors.TRIP_ACTIVE, null, null)
            when {
                simulation == null -> real.startTrip(config, destLat, destLng, null)
                simulation.traceAsset.startsWith(STUB_PREFIX) -> stub.startTrip(config, destLat, destLng, simulation)
                else -> throw FlutterError(BridgeErrors.SIMULATION_UNAVAILABLE, "simulation not available yet", null)
            }
        } finally {
            starting.set(false)
        }
    }

    override suspend fun stopTrip(tripId: String) = target().stopTrip(tripId)

    override suspend fun currentTrip(): ActiveTripMsg? = real.currentTrip() ?: stub.currentTrip()

    override suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) = target().setBatteryChoice(tripId, choice)

    override suspend fun dismiss(tripId: String) = target().dismiss(tripId)

    override suspend fun snooze(tripId: String) = target().snooze(tripId)

    override suspend fun pendingFinishedTrips(): List<FinishedTripMsg> =
        (real.pendingFinishedTrips() + stub.pendingFinishedTrips()).sortedWith(compareBy<FinishedTripMsg> { it.endedAtMs }.thenBy { it.tripId })

    override suspend fun ackFinishedTrips(tripIds: List<String>) {
        real.ackFinishedTrips(tripIds)
        stub.ackFinishedTrips(tripIds)
    }

    override fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle {
        val a = real.addListener(listener)
        val b = stub.addListener(listener)
        return ListenerHandle {
            a.remove()
            b.remove()
        }
    }

    private suspend fun target(): TripBackend = if (real.currentTrip() != null) real else stub

    companion object {
        const val STUB_PREFIX = "stub/"
    }
}
