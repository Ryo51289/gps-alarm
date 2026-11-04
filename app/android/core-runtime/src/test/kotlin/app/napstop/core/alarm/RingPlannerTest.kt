package app.napstop.core.alarm

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T16 A01–A07: plan, sounds, vibration, ramp, routing, headphone types, FGS types. */
class RingPlannerTest {
    private val c = AlarmConstants()

    private fun settings(
        volume: Double = 0.8,
        ramp: Boolean = true,
        vibration: String = "medium",
        flash: Boolean = true,
        headphones: Boolean = false,
        dismiss: String = "swipe",
        sound: String = "default",
    ) = RingSettings(sound, volume, ramp, vibration, flash, headphones, dismiss)

    @Test
    fun a01_planFromTheT25Styles() {
        val ring = RingPlanner.plan(settings(), c)
        assertTrue(ring.playSound)
        assertEquals(0.8f, ring.targetVolume)
        assertEquals(30_000L, ring.rampMs)
        assertEquals(VibrationPatterns.MEDIUM, ring.vibration)
        assertTrue(ring.flash)
        assertFalse(ring.headphonesOnly)
        assertEquals("horn", ring.soundId)

        val vib = RingPlanner.plan(settings(volume = 0.0, vibration = "strong"), c)
        assertFalse(vib.playSound)
        assertEquals(VibrationPatterns.STRONG, vib.vibration)

        val hp = RingPlanner.plan(settings(headphones = true), c)
        assertTrue(hp.headphonesOnly)
        assertEquals(0.8f, hp.targetVolume)

        val none = RingPlanner.plan(null, c)
        assertEquals("horn", none.soundId)
        assertEquals(1.0f, none.targetVolume)
        assertEquals(30_000L, none.rampMs)
        assertEquals(VibrationPatterns.STRONG, none.vibration)
        assertEquals(DismissMethod.SWIPE, none.dismissMethod)

        assertEquals(DismissMethod.SWIPE, RingPlanner.plan(settings(dismiss = "x"), c).dismissMethod)
        assertEquals(DismissMethod.MATH, RingPlanner.plan(settings(dismiss = "math"), c).dismissMethod)
        assertEquals(0L, RingPlanner.plan(settings(ramp = false), c).rampMs)
        // Silent and no vibration → strong vibration (never silent by configuration).
        assertEquals(VibrationPatterns.STRONG, RingPlanner.plan(settings(volume = 0.0, vibration = "off"), c).vibration)
        // Sound on and vibration off → no vibration.
        assertNull(RingPlanner.plan(settings(vibration = "off"), c).vibration)
    }

    @Test
    fun a02_vibrationLevels() {
        assertEquals(VibrationSpec(longArrayOf(0, 300, 1200), intArrayOf(0, 90, 0), 0), VibrationPatterns.forLevel("light"))
        assertEquals(VibrationSpec(longArrayOf(0, 600, 600), intArrayOf(0, 170, 0), 0), VibrationPatterns.forLevel("medium"))
        assertEquals(VibrationSpec(longArrayOf(0, 900, 300), intArrayOf(0, 255, 0), 0), VibrationPatterns.forLevel("strong"))
        assertNull(VibrationPatterns.forLevel("off"))
        assertEquals(VibrationPatterns.STRONG, VibrationPatterns.forLevel(null))
        assertEquals(VibrationPatterns.STRONG, VibrationPatterns.forLevel("loud"))
    }

    @Test
    fun a03_soundIds() {
        for (id in listOf("default", "", null, "../x", "horn")) assertEquals("horn", AlarmSounds.resolve(id), "$id")
        assertEquals("bell", AlarmSounds.resolve("bell"))
        assertEquals("beep", AlarmSounds.resolve("beep"))
        assertEquals("system", AlarmSounds.resolve("system"))
        assertNull(AlarmSounds.rawName("system"))
        assertEquals("alarm_bell", AlarmSounds.rawName("bell"))
        assertEquals("alarm_horn", AlarmSounds.rawName("default"))
        assertEquals(listOf("horn", "bell", "beep", "system"), AlarmSounds.catalog)
    }

    @Test
    fun a04_rampCurveAndResume() {
        val p = RingPlanner.plan(settings(), c)
        assertEquals(0.10f, VolumeRamp.fractionAt(p, 0), 1e-4f)
        assertEquals(0.55f, VolumeRamp.fractionAt(p, 15_000), 1e-4f)
        assertEquals(1.0f, VolumeRamp.fractionAt(p, 30_000), 1e-4f)
        assertEquals(1.0f, VolumeRamp.fractionAt(p, 45_000), 1e-4f)
        val seg = VolumeRamp.remaining(p, 10_000)!!
        assertEquals(0.40f, seg.startFraction, 1e-4f)
        assertEquals(20_000L, seg.durationMs)
        assertNull(VolumeRamp.remaining(p, 30_000))
        assertNull(VolumeRamp.remaining(RingPlanner.plan(settings(ramp = false), c), 0))
        assertEquals(1.0f, VolumeRamp.fractionAt(RingPlanner.plan(settings(ramp = false), c), 0))
    }

    @Test
    fun a05_outputRoute() {
        val hp = RingPlanner.plan(settings(headphones = true), c)
        assertEquals(AudioRoute.HEADPHONES, OutputRouter.initial(hp, headphonesConnected = true))
        assertEquals(AudioRoute.SPEAKER, OutputRouter.initial(hp, headphonesConnected = false)) // T25 Q2
        assertEquals(AudioRoute.SPEAKER, OutputRouter.initial(RingPlanner.plan(settings(), c), headphonesConnected = true))
        assertEquals(AudioRoute.VIBRATE_ONLY, OutputRouter.initial(RingPlanner.plan(settings(volume = 0.0), c), headphonesConnected = true))
        assertEquals(AudioRoute.VIBRATE_ONLY, OutputRouter.onHeadphonesGone(AudioRoute.HEADPHONES, hp))
        assertEquals(AudioRoute.SPEAKER, OutputRouter.onHeadphonesGone(AudioRoute.SPEAKER, hp))
    }

    @Test
    fun a06_headphoneTypes() {
        for (t in listOf(3, 4, 7, 8, 22, 23, 26)) assertTrue(HeadphoneTypes.isHeadphone(t), "$t")
        for (t in listOf(1, 2, 0, 27)) assertFalse(HeadphoneTypes.isHeadphone(t), "$t")
    }

    @Test
    fun a07_fgsTypes() {
        for (exact in listOf(true, false)) {
            assertEquals(listOf(FgsType.NONE), FgsTypePolicy.ringTypes(26, exact))
            assertEquals(listOf(FgsType.NONE), FgsTypePolicy.ringTypes(28, exact))
            assertEquals(listOf(FgsType.MEDIA_PLAYBACK), FgsTypePolicy.ringTypes(29, exact))
            assertEquals(listOf(FgsType.MEDIA_PLAYBACK), FgsTypePolicy.ringTypes(33, exact))
        }
        for (sdk in listOf(34, 36)) {
            assertEquals(listOf(FgsType.SYSTEM_EXEMPTED, FgsType.MEDIA_PLAYBACK), FgsTypePolicy.ringTypes(sdk, true))
            assertEquals(listOf(FgsType.MEDIA_PLAYBACK), FgsTypePolicy.ringTypes(sdk, false))
        }
    }
}
