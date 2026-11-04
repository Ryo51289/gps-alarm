package app.napstop.core.alarm

/**
 * One in-memory slot for the action MainActivity was opened with (spec T16 §4.5): `overshootRoute` from "Xem đường quay
 * lại". T27 reads it on the Flutter side (Pigeon T14.x); T16 only stores it.
 */
object LaunchActions {
    const val EXTRA_LAUNCH = "napstop.launch"
    const val EXTRA_TRIP_ID = "napstop.tripId"
    const val OVERSHOOT_ROUTE = "overshootRoute"

    data class Action(val action: String, val tripId: String?) {
        override fun toString(): String = "Action($action, tripId=$tripId)"
    }

    private var slot: Action? = null

    @Synchronized
    fun set(action: String, tripId: String?) {
        slot = Action(action, tripId)
    }

    /** Returns and clears the slot. */
    @Synchronized
    fun consume(): Action? = slot.also { slot = null }
}
