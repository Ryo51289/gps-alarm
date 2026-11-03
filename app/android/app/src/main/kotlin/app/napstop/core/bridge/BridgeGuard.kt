package app.napstop.core.bridge

import kotlin.coroutines.cancellation.CancellationException

/**
 * Maps unexpected throwables to `internal` + class name (spec T14 §4, test report T14 F3,
 * T21 D6): Pigeon's generated wrapError would send `toString()` and the stack trace to Dart,
 * and an exception message may hold anything (place names, numbers). [FlutterError] and
 * [CancellationException] pass through unchanged.
 */
object BridgeGuard {
    inline fun <T> call(block: () -> T): T =
        try {
            block()
        } catch (e: FlutterError) {
            throw e
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            throw internalError(e)
        }

    /** `internal` with the simple class name, or "Throwable" for anonymous classes. Never the message. */
    fun internalError(e: Throwable): FlutterError =
        FlutterError(BridgeErrors.INTERNAL, e.javaClass.simpleName.ifEmpty { "Throwable" }, null)
}
