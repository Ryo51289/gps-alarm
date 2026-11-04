package app.napstop.core.alarm.ring

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.util.Log

/**
 * Blinking torch (spec T16 D15, §5.7): CameraManager.setTorchMode without opening the camera. No flash, camera busy or
 * any error → no flash for this session; nothing else is affected. Runs on the ring thread ([handler]).
 */
class RingTorch(context: Context, private val handler: Handler, private val onMs: Long, private val offMs: Long) {
    private val ctx = context.applicationContext
    private val cm: CameraManager? get() = ctx.getSystemService(CameraManager::class.java)
    private var cameraId: String? = null
    private var lit = false
    private var running = false
    private var disabled = false

    private val callback =
        object : CameraManager.TorchCallback() {
            override fun onTorchModeUnavailable(id: String) {
                if (id == cameraId && running) disable("unavailable")
            }
        }

    private val tick =
        object : Runnable {
            override fun run() {
                if (!running) return
                lit = !lit
                if (!set(lit)) return
                handler.postDelayed(this, if (lit) onMs else offMs)
            }
        }

    fun start() {
        if (running || disabled) return
        val id = findCamera() ?: return disable("none")
        cameraId = id
        running = true
        try {
            cm?.registerTorchCallback(callback, handler)
        } catch (e: Exception) {
            Log.w(TAG, "torch callback failed (${e.javaClass.simpleName})")
        }
        lit = false
        handler.post(tick)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(tick)
        try {
            cm?.unregisterTorchCallback(callback)
        } catch (e: Exception) {
            // ignore
        }
        cameraId?.let {
            try {
                cm?.setTorchMode(it, false)
            } catch (e: Exception) {
                // ignore (§5.7: StopFlash always tries, errors ignored)
            }
        }
        lit = false
    }

    private fun set(on: Boolean): Boolean {
        val id = cameraId ?: return false
        return try {
            cm?.setTorchMode(id, on)
            true
        } catch (e: Exception) {
            disable(e.javaClass.simpleName)
            false
        }
    }

    private fun disable(why: String) {
        Log.w(TAG, "flash off for this ring ($why)")
        disabled = true
        stop()
    }

    private fun findCamera(): String? =
        try {
            val m = cm ?: return null
            val withFlash = m.cameraIdList.filter { m.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true }
            withFlash.firstOrNull { m.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK }
                ?: withFlash.firstOrNull()
        } catch (e: Exception) {
            null
        }

    private companion object {
        const val TAG = "NapStopRing"
    }
}
