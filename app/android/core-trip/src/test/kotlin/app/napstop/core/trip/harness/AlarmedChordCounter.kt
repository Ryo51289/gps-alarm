package app.napstop.core.trip.harness

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripPhase
import java.io.File

/**
 * T10.7 §10 (T12 "T10.7" #7): in a fuzz, the GPS-gap chord fixes taken after an alarm (phase before the Step ALARMING or
 * SNOOZED, from [GapProbe.phase]), the Overshoot events that follow one in the same trip (with / without an Alarm(OVERSHOOT) in
 * the same Step) and the wrong ones: Overshoot with a chord taken after the alarm (`alarmedChordD != null`, T10.7 round 2)
 * while the truth has not passed the destination yet (truth distance > 0, the U116 b definition). Trips are told apart by their
 * tag (fed in order).
 */
internal class AlarmedChordCounter {
    var chordFixes = 0
    var overshootWithAlarm = 0
    var overshootNoAlarm = 0

    /** Overshoot events above whose Step state has `alarmedChordD != null` (T10.7 round 2: nearD may come from the chord). */
    var overshootFromChord = 0
    val wrong = ArrayList<String>()
    private var trip: String? = null
    private var armed = false

    /**
     * One Step on [input]; [truthD] = signed true distance to the destination at the Step (null = unknown). Returns the
     * wrong-wording line when this Step is one (also added to [wrong]).
     */
    fun onFix(tripTag: String, s0: EngineState, input: LocationFix, step: Step, truthD: Double?): String? {
        if (tripTag != trip) {
            trip = tripTag
            armed = false
        }
        val g = GapProbe.of(s0, input, step)
        if (g?.dChord != null && (g.phase == TripPhase.ALARMING || g.phase == TripPhase.SNOOZED)) {
            chordFixes++
            armed = true
        }
        if (!armed || step.events.none { it is Overshoot }) return null
        if (step.events.any { it is Alarm && it.reason == AlarmReason.OVERSHOOT }) overshootWithAlarm++ else overshootNoAlarm++
        if (step.state.alarmedChordD != null) overshootFromChord++
        if (step.state.alarmedChordD != null && truthD != null && truthD > 0.0) {
            val line = "$tripTag at ${step.state.nowMs - step.state.startedAtMs} ms truthD=${truthD.toInt()} " +
                "minD=${step.state.minD?.toInt()} alarmedChordD=${step.state.alarmedChordD?.toInt()}"
            wrong += line
            return line
        }
        return null
    }

    fun line(name: String): String =
        "$name: alarmedChordFixes=$chordFixes overshootAfter(withAlarm=$overshootWithAlarm, noAlarm=$overshootNoAlarm, withAlarmedChordD=$overshootFromChord) " +
            "wrongWording=${wrong.size}${wrong.take(10).joinToString("") { "\n  $it" }}"

    companion object {
        private val LINES = sortedMapOf<String, String>()

        /** Writes `t107-alarmed-chord.txt` with every counter reported so far (any test order). */
        @Synchronized
        fun report(name: String, c: AlarmedChordCounter) {
            LINES[name] = c.line(name)
            File(Suite.outDir.apply { mkdirs() }, "t107-alarmed-chord.txt").writeText(LINES.values.joinToString("\n", postfix = "\n"))
        }
    }
}
