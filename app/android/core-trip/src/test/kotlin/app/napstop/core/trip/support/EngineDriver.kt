package app.napstop.core.trip.support

import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineParamsFactory
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackScheduled
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripView
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.VehicleKind

/** Trip start time used by unit tests (any fixed epoch). */
const val S: Long = 1_800_000_000_000L

fun cfg(
    mode: AlarmMode = AlarmMode.DISTANCE,
    thr: Int? = if (mode == AlarmMode.DISTANCE) 1000 else null,
    thrMin: Int? = if (mode == AlarmMode.TIME) 15 else null,
    preAlert: Boolean = true,
    hint: VehicleKind = VehicleKind.TRAIN,
    dest: LatLng = DEST,
): TripConfig = TripConfig("trip-1", dest.lat, dest.lng, mode, thr, thrMin, preAlert, hint)

fun params(json: String): EngineParams {
    val p = EngineParamsFactory.parseOverrides(json)
    check(!p.malformed && p.rejected.isEmpty()) { "test params rejected: ${p.rejected}" }
    return p.params
}

/** Unit-test trip builder: times in seconds from [startMs]; fixes due south of [DEST] at distance d. */
class EngineDriver(val config: TripConfig = cfg(), val p: EngineParams = EngineParams(), val startMs: Long = S) {
    val steps = ArrayList<Step>()
    lateinit var state: EngineState

    init {
        push(TripEngine.start(config, p, startMs))
    }

    fun ms(t: Double): Long = startMs + Math.round(t * 1000.0)

    fun ms(t: Int): Long = startMs + t * 1000L

    private fun push(s: Step): Step {
        steps += s
        state = s.state
        return s
    }

    fun feed(x: EngineInput): Step = push(TripEngine.reduce(state, x))

    fun fix(t: Int, d: Double, acc: Double = 8.0, spd: Double? = null, eastM: Double = 0.0, ageMs: Long = 0): Step {
        val p0 = TestGeo.pointOnMeridian(DEST, d)
        val pt = if (eastM == 0.0) p0 else TestGeo.jitter(p0, eastM, 0.0)
        return feed(LocationFix(ms(t), ms(t) - ageMs, pt.lat, pt.lng, acc, spd))
    }

    fun fixAt(t: Int, pt: LatLng, acc: Double = 8.0, spd: Double? = null): Step =
        feed(LocationFix(ms(t), ms(t), pt.lat, pt.lng, acc, spd))

    fun tick(t: Int): Step = feed(Tick(ms(t)))

    fun tickMs(atMs: Long): Step = feed(Tick(atMs))

    fun user(t: Int, a: UserActionKind): Step = feed(UserAction(ms(t), a))

    fun battery(t: Int, level: Int, charging: Boolean = false): Step = feed(BatterySample(ms(t), level, charging))

    fun avail(t: Int, c: AvailabilityCause): Step = feed(LocationAvailability(ms(t), c))

    fun scheduled(t: Int, atMs: Long, ok: Boolean): Step = feed(FallbackScheduled(ms(t), atMs, ok))

    fun fired(t: Int, firedAtMs: Long): Step = feed(FallbackFired(ms(t), firedAtMs))

    fun silenced(t: Int): Step = feed(AlarmSilenced(ms(t), ms(t)))

    fun restore(t: Int, info: RestoreInfo, roundTrip: Boolean = true): Step {
        val st = if (roundTrip) TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(state)) else state
        return push(TripEngine.restore(st, ms(t), info))
    }

    val view: TripView get() = steps.last().view

    val last: Step get() = steps.last()

    fun events(): List<TripEvent> = steps.flatMap { it.events }

    inline fun <reified T : TripEvent> all(): List<T> = events().filterIsInstance<T>()

    /** Ticks from..to (inclusive) every [every] s until [stop] returns true; returns the Step that stopped or null. */
    fun ticksUntil(from: Int, to: Int, every: Int, stop: (Step) -> Boolean): Pair<Int, Step>? {
        var t = from
        while (t <= to) {
            val s = tick(t)
            if (stop(s)) return t to s
            t += every
        }
        return null
    }
}
