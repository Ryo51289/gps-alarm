package app.napstop.core.alarm

/** Where the ring sound goes (spec T16 D13, T25 Q2). Pure. */
object OutputRouter {
    fun initial(plan: RingPlan, headphonesConnected: Boolean): AudioRoute =
        when {
            !plan.playSound -> AudioRoute.VIBRATE_ONLY
            // "Chỉ tai nghe" without headphones rings on the speaker like "Chuông + rung" (T25 Q2, PO 02/11).
            plan.headphonesOnly && headphonesConnected -> AudioRoute.HEADPHONES
            else -> AudioRoute.SPEAKER
        }

    /** Headphones unplugged while ringing: HEADPHONES → VIBRATE_ONLY (PRD §4); any other route stays. */
    fun onHeadphonesGone(current: AudioRoute, plan: RingPlan): AudioRoute =
        if (current == AudioRoute.HEADPHONES && plan.headphonesOnly) AudioRoute.VIBRATE_ONLY else current
}

/** AudioDeviceInfo.TYPE_* values copied as Int so the rule is JVM-testable (android.media.AudioDeviceInfo). */
object HeadphoneTypes {
    const val TYPE_BUILTIN_EARPIECE = 1
    const val TYPE_BUILTIN_SPEAKER = 2
    const val TYPE_WIRED_HEADSET = 3
    const val TYPE_WIRED_HEADPHONES = 4
    const val TYPE_BLUETOOTH_SCO = 7
    const val TYPE_BLUETOOTH_A2DP = 8
    const val TYPE_USB_HEADSET = 22
    const val TYPE_HEARING_AID = 23
    const val TYPE_BLE_HEADSET = 26

    private val HEADPHONES =
        setOf(
            TYPE_WIRED_HEADSET, TYPE_WIRED_HEADPHONES, TYPE_BLUETOOTH_SCO, TYPE_BLUETOOTH_A2DP, TYPE_USB_HEADSET,
            TYPE_HEARING_AID, TYPE_BLE_HEADSET,
        )

    fun isHeadphone(type: Int): Boolean = type in HEADPHONES
}
