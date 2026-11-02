package app.napstop.core.bridge

import app.napstop.core.bridge.BridgeTestData.alarm
import app.napstop.core.bridge.BridgeTestData.config
import app.napstop.core.bridge.BridgeTestData.expectFlutterError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** K01-K03 (spec T14 §6) + V11 (T14.1). */
class TripConfigValidatorTest {
    private val lat = 16.8
    private val lng = 107.1

    private fun validate(
        config: TripConfigMsg = config(),
        destLat: Double = lat,
        destLng: Double = lng,
        simulation: SimulationMsg? = null,
    ) = TripConfigValidator.validate(config, destLat, destLng, simulation)

    private fun assertInvalid(expectedMessage: String, vararg forbidden: String, block: () -> Unit) {
        val e = expectFlutterError(block)
        assertEquals(BridgeErrors.INVALID_CONFIG, e.code)
        assertEquals(expectedMessage, e.message)
        assertEquals(null, e.details)
        for (value in forbidden) {
            assertFalse("message leaks '$value'", e.message.orEmpty().contains(value))
        }
    }

    @Test
    fun k01_validConfigsPass() {
        validate(config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 200))
        validate(config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 10_000))
        validate(config(mode = AlarmModeMsg.TIME, timeThresholdMin = 5))
        validate(config(mode = AlarmModeMsg.TIME, timeThresholdMin = 60))
        validate(config(mode = AlarmModeMsg.SMART))
        validate(config(mode = AlarmModeMsg.SMART, distanceThresholdM = 1000, timeThresholdMin = 15))
        validate(destLat = 90.0, destLng = -180.0)
        validate(destLat = -90.0, destLng = 179.999)
        validate(config(alarm = alarm(volume = 0.0)))
        validate(config(alarm = alarm(volume = 1.0)))
        validate(simulation = SimulationMsg("stub/normal", 1.0))
        validate(simulation = SimulationMsg("stub/normal", 600.0))
        validate(config(tripId = "a".repeat(64)))
        validate(config(tripId = "3f2b-AZ_09"))
        validate(config(destinationName = "x".repeat(200)))
    }

    @Test
    fun k02_eachRuleHasAFixedMessageWithoutValues() {
        assertInvalid("destinationName: empty") { validate(config(destinationName = "  ")) }
        assertInvalid("destinationName: too long") { validate(config(destinationName = "x".repeat(201))) }
        assertInvalid("destLat: out of range", "91.5") { validate(destLat = 91.5) }
        assertInvalid("destLat: out of range", "NaN") { validate(destLat = Double.NaN) }
        assertInvalid("destLat: out of range") { validate(destLat = Double.NEGATIVE_INFINITY) }
        assertInvalid("destLng: out of range", "180") { validate(destLng = 180.0) }
        assertInvalid("destLng: out of range", "-180.5") { validate(destLng = -180.5) }
        assertInvalid("destLng: out of range") { validate(destLng = Double.POSITIVE_INFINITY) }
        assertInvalid("distanceThresholdM: required") { validate(config(mode = AlarmModeMsg.DISTANCE)) }
        assertInvalid("timeThresholdMin: required") { validate(config(mode = AlarmModeMsg.TIME)) }
        assertInvalid("distanceThresholdM: out of range", "199") {
            validate(config(mode = AlarmModeMsg.SMART, distanceThresholdM = 199))
        }
        assertInvalid("distanceThresholdM: out of range", "10001") {
            validate(config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 10_001))
        }
        assertInvalid("timeThresholdMin: out of range", "4") {
            validate(config(mode = AlarmModeMsg.TIME, timeThresholdMin = 4))
        }
        assertInvalid("timeThresholdMin: out of range", "61") {
            validate(config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000, timeThresholdMin = 61))
        }
        assertInvalid("alarm.soundId: empty") { validate(config(alarm = alarm(soundId = ""))) }
        assertInvalid("alarm.volume: out of range", "1.01") { validate(config(alarm = alarm(volume = 1.01))) }
        assertInvalid("alarm.volume: out of range") { validate(config(alarm = alarm(volume = Double.NaN))) }
        assertInvalid("simulation.traceAsset: empty") { validate(simulation = SimulationMsg("", 60.0)) }
        assertInvalid("simulation.speedFactor: out of range", "0.5") {
            validate(simulation = SimulationMsg("stub/normal", 0.5))
        }
        assertInvalid("simulation.speedFactor: out of range", "601") {
            validate(simulation = SimulationMsg("stub/normal", 601.0))
        }
    }

    @Test
    fun k02_firstViolatedRuleWins() {
        // V1 before V3, V3 before V5.
        assertInvalid("tripId: format") { validate(config(tripId = ""), destLat = 99.0) }
        assertInvalid("destLat: out of range") { validate(config(mode = AlarmModeMsg.DISTANCE), destLat = 99.0) }
    }

    @Test
    fun v11_engineParamsJsonLength() {
        val max = TripConfigValidator.MAX_ENGINE_PARAMS_JSON_LENGTH
        assertEquals(16_384, max)
        validate(config(engineParamsJson = null))
        validate(config(engineParamsJson = ""))
        validate(config(engineParamsJson = "{\"smartTargetS\":300.0}"))
        validate(config(engineParamsJson = "x".repeat(max)))
        // UTF-16 code units, like Dart String.length: 8 192 surrogate pairs = 16 384.
        val sleepy = String(Character.toChars(0x1F634))
        assertEquals(2, sleepy.length)
        validate(config(engineParamsJson = sleepy.repeat(max / 2)))
        assertInvalid("engineParamsJson: too long", "{", "xxx") {
            validate(config(engineParamsJson = "{" + "x".repeat(max)))
        }
        assertInvalid("engineParamsJson: too long") {
            validate(config(engineParamsJson = sleepy.repeat(max / 2) + "a"))
        }
    }

    @Test
    fun v11_isCheckedAfterV1ToV10() {
        val tooLong = "x".repeat(20_000)
        assertInvalid("simulation.speedFactor: out of range") {
            validate(config(engineParamsJson = tooLong), simulation = SimulationMsg("stub/normal", 0.5))
        }
        assertInvalid("tripId: format") { validate(config(tripId = "", engineParamsJson = tooLong)) }
    }

    @Test
    fun k03_tripIdFormat() {
        for (id in listOf("", "../x", "a".repeat(65), "a b", "t1\n", "tì")) {
            assertInvalid("tripId: format") { validate(config(tripId = id)) }
        }
    }
}
