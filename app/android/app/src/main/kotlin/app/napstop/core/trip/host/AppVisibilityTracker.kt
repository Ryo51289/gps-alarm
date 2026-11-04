package app.napstop.core.trip.host

import app.napstop.core.trip.runtime.AppVisibility
import java.util.concurrent.atomic.AtomicInteger

/**
 * Whether an activity of the app is visible (between onStart and onStop), for ADR-001 #2: the `location` foreground
 * service may only start then (spec T15 D9). MainActivity is the only activity.
 */
object AppVisibilityTracker : AppVisibility {
    private val started = AtomicInteger(0)

    fun onActivityStarted() {
        started.incrementAndGet()
    }

    fun onActivityStopped() {
        started.updateAndGet { maxOf(0, it - 1) }
    }

    override fun isVisible(): Boolean = started.get() > 0
}
