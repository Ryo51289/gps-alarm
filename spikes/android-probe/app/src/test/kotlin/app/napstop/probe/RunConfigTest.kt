package app.napstop.probe

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime

class RunConfigTest {

    private fun cfg(
        kind: String = RunConfig.KIND_S1,
        durationMin: Int = 600,
        densePhaseMin: Int = 60,
        alarmAtEnd: Boolean = true,
        delayMin: Int? = null,
        bootCount: Int = 7,
    ) = RunConfig(
        runId = "r", kind = kind, label = "A", durationMin = durationMin, densePhaseMin = densePhaseMin,
        alarmAtEnd = alarmAtEnd, watchdog = true, delayMin = delayMin, scenario = null,
        startWallMs = 1_000_000L, startElapsed = 50_000L, bootCount = bootCount,
    )

    @Test
    fun `S1 phases switch to dense at duration minus dense phase`() {
        val c = cfg()
        assertEquals(Phase.SPARSE, c.phaseAt(0))
        assertEquals(Phase.SPARSE, c.phaseAt(540 * 60_000L - 1))
        assertEquals(Phase.DENSE, c.phaseAt(540 * 60_000L))
        assertEquals(Phase.DENSE, c.phaseAt(700 * 60_000L))
    }

    @Test
    fun `S2 is dense for the whole run and the deadline is start plus delay`() {
        val c = cfg(kind = RunConfig.KIND_S2, durationMin = 2, densePhaseMin = 2, delayMin = 2)
        assertEquals(Phase.DENSE, c.phaseAt(0))
        assertEquals(1_000_000L + 120_000L, c.deadlineWallMs)
        assertTrue(c.alarmEnabled)
        assertFalse(c.shouldAutoStop(10 * 60_000L))
    }

    @Test
    fun `S1 deadline is the planned end only with alarmAtEnd, otherwise auto stop`() {
        assertEquals(1_000_000L + 600 * 60_000L, cfg().deadlineWallMs)
        val noAlarm = cfg(alarmAtEnd = false)
        assertNull(noAlarm.deadlineWallMs)
        assertFalse(noAlarm.shouldAutoStop(600 * 60_000L - 1))
        assertTrue(noAlarm.shouldAutoStop(600 * 60_000L))
        assertFalse(cfg().shouldAutoStop(700 * 60_000L))
    }

    @Test
    fun `elapsed uses elapsedRealtime in the same boot and wall clock after a reboot`() {
        val c = cfg(bootCount = 7)
        assertEquals(10_000L, c.elapsedMs(nowElapsed = 60_000L, nowWallMs = 9_999_999L, currentBootCount = 7))
        assertEquals(500_000L, c.elapsedMs(nowElapsed = 1_000L, nowWallMs = 1_500_000L, currentBootCount = 8))
        val unknownBoot = cfg(bootCount = -1)
        assertEquals(500_000L, unknownBoot.elapsedMs(nowElapsed = 60_000L, nowWallMs = 1_500_000L, currentBootCount = -1))
    }

    @Test
    fun `phase boundary for the exact alarm`() {
        val c = cfg(bootCount = 7)
        assertTrue(c.hasSparsePhase)
        assertEquals(540 * 60_000L, c.boundaryOffsetMs)
        assertEquals(1_000_000L + 540 * 60_000L, c.boundaryWallMs)
        // Same boot: startElapsed + offset.
        assertEquals(50_000L + 540 * 60_000L, c.boundaryElapsed(nowElapsed = 60_000L, nowWallMs = 1_010_000L, currentBootCount = 7))
        // After a reboot: now + (boundaryWall - nowWall).
        val nowWall = 1_000_000L + 100 * 60_000L
        assertEquals(
            5_000L + 440 * 60_000L,
            c.boundaryElapsed(nowElapsed = 5_000L, nowWallMs = nowWall, currentBootCount = 8),
        )
        assertFalse(cfg(kind = RunConfig.KIND_S2, durationMin = 2, densePhaseMin = 2, delayMin = 2).hasSparsePhase)
        assertFalse(cfg(durationMin = 18, densePhaseMin = 18).hasSparsePhase)
    }

    @Test
    fun `run id format`() {
        val t = LocalDateTime.of(2026, 11, 2, 21, 30, 5)
        assertEquals("20261102-213005-S1-A", RunConfig.makeRunId(t, "S1", "A"))
        assertEquals("20261102-213005-S2-3", RunConfig.makeRunId(t, "S2", "S2-3"))
        assertEquals("20261102-213005-S1-a_b", RunConfig.makeRunId(t, "S1", "a/b"))
    }
}
