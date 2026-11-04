package app.napstop.core.trip.runtime

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class JournalAnalyzerTest {
    @Test
    fun labelsAndSummary() {
        assertEquals("c8", JournalAnalyzer.label(910_000, 2_000_000, 1_000_000))
        assertEquals("c3", JournalAnalyzer.label(2_001_000, 2_000_000, 9_000_000))
        assertEquals("c3-near", JournalAnalyzer.label(1_401_000, 2_000_000, null))
        assertEquals("c4", JournalAnalyzer.label(1_101_000, 2_000_000, null))
        val lines =
            listOf(
                """{"t":0,"w":0,"ev":"step","phase":"TRACKING","gps":"OK","tier":"SPARSE","predicted":2000000,"fb":1000000,"fbStatus":"CONFIRMED","wake":910000,"events":[],"input":"LocationFix"}""",
                """{"t":0,"w":0,"ev":"fix","ageMs":1000,"accM":8.0,"hasSpd":true,"dropped":false}""",
                """{"t":0,"w":0,"ev":"wake_set","at":910000,"mech":"EXACT_IDLE"}""",
                """{"t":980000,"w":980000,"ev":"wake_fire","at":910000,"lateMs":70000}""",
                """{"t":180000,"w":0,"ev":"fix","ageMs":2000,"accM":8.0,"hasSpd":true,"dropped":false}""",
                """{"t":990000,"w":0,"ev":"step","phase":"ALARMING","gps":"LOST","tier":"DENSE","predicted":null,"fb":null,"fbStatus":"NONE","wake":null,"events":["Alarm"],"input":"Tick"}""",
            )
        val text = JournalAnalyzer.analyze(lines)
        assertTrue(text.contains("label=c8") && text.contains("AFTER fb-30s"), text)
        assertTrue(text.contains("SPARSE: 180.0"), text)
        assertTrue(text.contains("first alarm: t=990000"), text)
    }
}
