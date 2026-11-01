package app.napstop.core.bridge

import kotlin.coroutines.cancellation.CancellationException

/**
 * TripHostApi -> TripBackend (spec T14 §4, §5.1). Validates startTrip and maps every
 * unexpected Throwable to `internal` with its class name only: Pigeon's own
 * wrapError would send toString() and the stack trace, which may contain trip data.
 */
class TripHostApiImpl(private val backend: TripBackend) : TripHostApi {
    override suspend fun startTrip(
        config: TripConfigMsg,
        destLat: Double,
        destLng: Double,
        simulation: SimulationMsg?,
    ) = guard {
        TripConfigValidator.validate(config, destLat, destLng, simulation)
        backend.startTrip(config, destLat, destLng, simulation)
    }

    override suspend fun stopTrip(tripId: String) = guard { backend.stopTrip(tripId) }

    override suspend fun currentTrip(): ActiveTripMsg? = guard { backend.currentTrip() }

    override suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) =
        guard { backend.setBatteryChoice(tripId, choice) }

    override suspend fun dismiss(tripId: String) = guard { backend.dismiss(tripId) }

    override suspend fun snooze(tripId: String) = guard { backend.snooze(tripId) }

    override suspend fun pendingFinishedTrips(): List<FinishedTripMsg> = guard { backend.pendingFinishedTrips() }

    override suspend fun ackFinishedTrips(tripIds: List<String>) = guard { backend.ackFinishedTrips(tripIds) }

    private inline fun <T> guard(block: () -> T): T =
        try {
            block()
        } catch (e: FlutterError) {
            throw e
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Errors too (e.g. NotImplementedError from a TODO()): Pigeon's wrapError would
            // send their toString() and stack trace to Dart (review T14 N1).
            throw internalError(e)
        }

    companion object {
        /** `internal` FlutterError carrying only the exception class name (§4). */
        fun internalError(e: Throwable): FlutterError = FlutterError(BridgeErrors.INTERNAL, e.javaClass.simpleName, null)
    }
}
