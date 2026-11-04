package app.napstop.core.alarm

/** From AudioManager.mode: MODE_RINGTONE / MODE_IN_CALL / MODE_IN_COMMUNICATION → IN_CALL. */
enum class CallState { NONE, IN_CALL }

enum class FocusState { GRANTED, DELAYED, FAILED, LOST }

/** Audio focus rule of spec T16 D12. Pure. */
object FocusPolicy {
    /**
     * GRANTED / FAILED → play (another app never mutes the alarm); DELAYED (phone call) → vibrate + screen only until
     * the gain; LOST → pause only during a call.
     */
    fun shouldPlay(focus: FocusState, call: CallState): Boolean =
        when (focus) {
            FocusState.GRANTED, FocusState.FAILED -> true
            FocusState.DELAYED -> false
            FocusState.LOST -> call != CallState.IN_CALL
        }
}
