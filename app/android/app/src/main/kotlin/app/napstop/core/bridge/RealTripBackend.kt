package app.napstop.core.bridge

import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.RuntimeListener
import app.napstop.core.trip.runtime.StartOutcome
import app.napstop.core.trip.runtime.TripRuntime

/**
 * [TripBackend] on the real trip runtime (spec T15 §2, §5.1, §5.11). One runtime listener maps every Step to Pigeon
 * messages (TripStateUpdateMsg first) and fans it out through [hub] on the main thread; attaching a Flutter
 * listener asks the runtime for a replay Step. API calls return once the runtime committed their Step.
 */
class RealTripBackend(private val runtime: TripRuntime, private val hub: ListenerHub) : TripBackend {
    init {
        runtime.addListener(RuntimeListener { tripId, view, choice, events -> hub.publish(MsgMapper.updates(tripId, view, choice, events)) })
    }

    /** T18: a simulation runs on the same runtime (bundled trace, trip clock with a speed factor). */
    override suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) {
        when (val r = runtime.start(MsgMapper.meta(config, simulation), destLat, destLng)) {
            StartOutcome.Started -> Unit
            is StartOutcome.Rejected -> throw FlutterError(r.code, r.message, r.details)
        }
    }

    override suspend fun stopTrip(tripId: String) = runtime.userAction(tripId, UserActionKind.STOP_TRIP)

    override suspend fun currentTrip(): ActiveTripMsg? {
        val (meta, view) = runtime.current() ?: return null
        return ActiveTripMsg(
            config = MsgMapper.config(meta),
            state = MsgMapper.state(view, runtime.batteryChoice()),
            simulation = MsgMapper.simulation(meta),
        )
    }

    override suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) = runtime.userAction(tripId, MsgMapper.batteryAction(choice))

    override suspend fun dismiss(tripId: String) = runtime.userAction(tripId, UserActionKind.DISMISS)

    override suspend fun snooze(tripId: String) = runtime.userAction(tripId, UserActionKind.SNOOZE)

    override suspend fun pendingFinishedTrips(): List<FinishedTripMsg> = runtime.pendingFinished().map(MsgMapper::finished)

    override suspend fun ackFinishedTrips(tripIds: List<String>) = runtime.ackFinished(tripIds)

    override fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle {
        val handle = hub.add(listener)
        runtime.requestReplay()
        return handle
    }

    /** True while a trip (real or simulated) runs in this process. */
    suspend fun hasActive(): Boolean = runtime.current() != null
}
