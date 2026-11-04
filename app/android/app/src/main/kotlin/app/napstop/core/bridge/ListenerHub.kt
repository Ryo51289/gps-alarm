package app.napstop.core.bridge

/**
 * Listeners of a trip backend (spec T15 §5.11, D13; test report T14 F1, review T14 R2-3). Each listener gets every
 * update of a Step in order; each call runs in its own try/catch, so a listener that throws never starves another
 * listener and never fails an API call whose Step was committed. Errors are logged with the class name only.
 * Main thread only (add, remove, publish).
 */
class ListenerHub(private val warn: (String) -> Unit) {
    /** Identity wrapper: the same lambda added twice is two listeners, each removed by its own handle. */
    private class Entry(val onUpdate: (TripUpdateMsg) -> Unit)

    private val entries = ArrayList<Entry>()

    val isEmpty: Boolean get() = entries.isEmpty()

    val size: Int get() = entries.size

    /** [onRemoved] runs after the listener was removed (once; the handle is idempotent). */
    fun add(listener: (TripUpdateMsg) -> Unit, onRemoved: () -> Unit = {}): ListenerHandle {
        val e = Entry(listener)
        entries += e
        return ListenerHandle { if (entries.remove(e)) onRemoved() }
    }

    fun publish(updates: List<TripUpdateMsg>) {
        if (updates.isEmpty()) return
        for (e in entries.toList()) {
            for (u in updates) {
                try {
                    e.onUpdate(u)
                } catch (t: Exception) {
                    warn("listener failed (${t.javaClass.simpleName.ifEmpty { "Exception" }})")
                }
            }
        }
    }
}
