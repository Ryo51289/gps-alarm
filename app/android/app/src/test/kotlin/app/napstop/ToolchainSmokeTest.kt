package app.napstop

import org.junit.Assert.assertEquals
import org.junit.Test

class ToolchainSmokeTest {
    @Test
    fun jvmUnitTestPipelineRuns() {
        assertEquals(4, 2 + 2)
    }
}
