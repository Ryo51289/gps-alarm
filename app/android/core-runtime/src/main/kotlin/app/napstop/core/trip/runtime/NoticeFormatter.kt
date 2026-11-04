package app.napstop.core.trip.runtime

import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripView
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor

/**
 * Templates of the ongoing notification, from res/values{,-en}/strings.xml (same text as the ARB keys, spec T15 §8).
 * Placeholders are Android positional `%1$s`, `%2$s`.
 */
data class NoticeTemplates(
    /** notif_tracking_title: "Đang theo dõi tới %1$s" */
    val title: String,
    val acquiring: String,
    /** notif_tracking_distance_eta: distance, minutes */
    val distanceEta: String,
    val distance: String,
    val estimating: String,
    val alarming: String,
    /** notif_tracking_snoozed: time */
    val snoozed: String,
    /** notif_destination_unknown */
    val destinationUnknown: String,
)

/** Text of the ongoing notification (spec T15 §5.10). Pure; same rounding as the Dart `formatDistanceShort` (T22/T23). */
object NoticeFormatter {
    /** What is shown: 10 m steps below 1 km, 100 m steps from 1 km (half up). */
    fun roundedDistanceM(m: Double): Int {
        val r10 = floor(m / 10.0 + 0.5).toInt() * 10
        return if (r10 < 1000) r10 else floor(m / 100.0 + 0.5).toInt() * 100
    }

    /** "850 m"; "1,2 km" (vi) / "1.2 km" (en); "1 km" without a trailing zero. */
    fun distance(m: Double, locale: Locale): String {
        val shown = roundedDistanceM(m)
        if (shown < 1000) return "$shown m"
        val f = DecimalFormat("#,##0.#", DecimalFormatSymbols.getInstance(locale))
        f.roundingMode = RoundingMode.HALF_UP
        return f.format(shown / 1000.0) + " km"
    }

    /** ceil(etaS / 60), at least 1. */
    fun minutes(etaS: Int): Int = maxOf(1, ceil(etaS / 60.0).toInt())

    /** Coarsened to what is shown, so notices compare equal exactly when their text does. */
    fun notice(meta: TripMeta, view: TripView): TrackingNotice =
        TrackingNotice(
            tripId = meta.tripId,
            destinationName = meta.destinationName,
            phase = view.phase,
            distanceM = view.distanceM?.let { roundedDistanceM(it.toDouble()) },
            etaS = view.etaS?.let { minutes(it) * 60 },
            isEstimated = view.isEstimated,
            snoozeUntilMs = view.snoozeUntilMs,
        )

    fun title(destinationName: String?, t: NoticeTemplates): String =
        t.title.fmt(destinationName?.takeIf { it.isNotBlank() } ?: t.destinationUnknown)

    fun body(n: TrackingNotice, t: NoticeTemplates, locale: Locale, formatTime: (Long) -> String): String =
        when (n.phase) {
            TripPhase.ACQUIRING, TripPhase.ENDED -> t.acquiring
            TripPhase.TRACKING -> {
                val d = n.distanceM
                when {
                    d == null -> t.acquiring
                    n.isEstimated -> t.estimating.fmt(distance(d.toDouble(), locale))
                    n.etaS != null -> t.distanceEta.fmt(distance(d.toDouble(), locale), minutes(n.etaS).toString())
                    else -> t.distance.fmt(distance(d.toDouble(), locale))
                }
            }
            TripPhase.ALARMING, TripPhase.OVERSHOT -> t.alarming
            TripPhase.SNOOZED -> n.snoozeUntilMs?.let { t.snoozed.fmt(formatTime(it)) } ?: t.alarming
        }

    private fun String.fmt(vararg args: String): String = String.format(Locale.ROOT, this, *args)
}
