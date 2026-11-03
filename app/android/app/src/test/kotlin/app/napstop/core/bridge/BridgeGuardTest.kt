package app.napstop.core.bridge

import kotlin.coroutines.cancellation.CancellationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.fail
import org.junit.Test

/** K05: BridgeGuard (T14 F3, spec T21 §4.5). */
class BridgeGuardTest {
    private fun caught(block: () -> Unit): Throwable {
        try {
            BridgeGuard.call(block)
        } catch (e: Throwable) {
            return e
        }
        fail("no throw")
        error("unreachable")
    }

    @Test
    fun k05ReturnsTheValue() {
        assertEquals(42, BridgeGuard.call { 42 })
    }

    @Test
    fun k05FlutterErrorPassesThrough() {
        val e = FlutterError(BridgeErrors.REQUEST_IN_PROGRESS, null, null)
        assertSame(e, caught { throw e })
    }

    @Test
    fun k05CancellationPassesThrough() {
        val e = CancellationException("cancelled")
        assertSame(e, caught { throw e })
    }

    @Test
    fun k05OtherExceptionsBecomeInternalWithTheClassNameOnly() {
        val e = caught { throw IllegalStateException("secret 21.03,105.85") } as FlutterError
        assertEquals(BridgeErrors.INTERNAL, e.code)
        assertEquals("IllegalStateException", e.message)
        assertNull(e.details)
        assertFalse(e.toString().contains("secret"))
        assertFalse(e.toString().contains("21.03"))
    }

    @Test
    fun k05AnonymousClassReadsThrowable() {
        val e = caught { throw object : RuntimeException("21.0") {} } as FlutterError
        assertEquals(BridgeErrors.INTERNAL, e.code)
        assertEquals("Throwable", e.message)
    }

    @Test
    fun k05ErrorsToo() {
        val e = caught { throw NotImplementedError("TODO") } as FlutterError
        assertEquals(BridgeErrors.INTERNAL, e.code)
        assertEquals("NotImplementedError", e.message)
    }
}
