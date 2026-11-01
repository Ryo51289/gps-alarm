package app.napstop.core.bridge

import android.util.Log

/** Sound preview stub; T16 plays the sound with USAGE_ALARM (spec T14 §5.5). */
class AlarmHostApiStub : AlarmHostApi {
    override fun previewSound(soundId: String, volume: Double) {
        Log.d(TAG, "previewSound stub: $soundId")
    }

    override fun stopPreview() {
        Log.d(TAG, "stopPreview stub")
    }

    private companion object {
        const val TAG = "NapStopBridge"
    }
}
