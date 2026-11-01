package app.napstop.core.bridge

/**
 * Event channel tripUpdates -> TripBackend listener (spec T14 §5.1). Owns the listener
 * of its engine only: cancelling or detaching never removes another engine's listener
 * (review T14 M1). Pigeon calls onListen/onCancel on the main thread.
 */
class TripUpdatesHandler(private val backend: TripBackend) : TripUpdatesStreamHandler() {
    private var handle: ListenerHandle? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<TripUpdateMsg>) {
        handle?.remove()
        handle = backend.addListener { sink.success(it) }
    }

    override fun onCancel(p0: Any?) = detach()

    /** Removes this engine's listener, if attached. */
    fun detach() {
        handle?.remove()
        handle = null
    }
}
