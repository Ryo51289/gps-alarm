package app.napstop.core.bridge.permission

import android.app.Activity
import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.FlutterError
import kotlinx.coroutines.CompletableDeferred

/** Shows the system permission dialog (spec T21 §4.3). Main thread only. */
interface PermissionPrompter {
    /** True while a prompt is shown (between prompt() and its result / detach()). */
    val busy: Boolean

    /** True when an activity is attached. */
    fun canPrompt(): Boolean

    /**
     * Shows the system dialog; returns after onRequestPermissionsResult or detach().
     * Throws FlutterError(request-in-progress) when one is pending.
     */
    suspend fun prompt(permissions: List<String>)

    /** activity.shouldShowRequestPermissionRationale; null = no activity. */
    fun rationale(permission: String): Boolean?
}

/**
 * [PermissionPrompter] on `Activity.requestPermissions` (FlutterActivity is not a
 * ComponentActivity, so no ActivityResult API, T21 D4). MainActivity forwards
 * onRequestPermissionsResult; the result arrays are ignored (empty when cancelled, A-REQ):
 * the caller reads the state again.
 */
class ActivityPermissionPrompter(
    requestPermissions: (Array<String>, Int) -> Unit,
    shouldShowRationale: (String) -> Boolean,
    activity: Activity? = null,
) : PermissionPrompter {
    /** Production: the activity's own calls (review T21 #2: the logic is tested with functions). */
    constructor(activity: Activity) : this(
        { permissions, code -> activity.requestPermissions(permissions, code) },
        { permission -> activity.shouldShowRequestPermissionRationale(permission) },
        activity,
    )

    private var requestPermissions: ((Array<String>, Int) -> Unit)? = requestPermissions
    private var shouldShowRationale: ((String) -> Boolean)? = shouldShowRationale

    /** The attached activity (settings pages); null after [detach] or when built from functions. */
    var activity: Activity? = activity
        private set

    private var pending: CompletableDeferred<Unit>? = null

    override val busy: Boolean get() = pending != null

    override fun canPrompt(): Boolean = requestPermissions != null

    override suspend fun prompt(permissions: List<String>) {
        if (pending != null) throw FlutterError(BridgeErrors.REQUEST_IN_PROGRESS, null, null)
        val request = requestPermissions ?: return
        val deferred = CompletableDeferred<Unit>()
        pending = deferred
        try {
            request(permissions.toTypedArray(), REQUEST_CODE)
            deferred.await()
        } finally {
            if (pending === deferred) pending = null
        }
    }

    override fun rationale(permission: String): Boolean? = shouldShowRationale?.invoke(permission)

    /** True when [requestCode] is ours; completes the pending prompt. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.complete(Unit)
        return true
    }

    /** The engine is going away: forget the activity, let a waiting prompt return. */
    fun detach() {
        requestPermissions = null
        shouldShowRationale = null
        activity = null
        pending?.complete(Unit)
    }

    companion object {
        /** 20048, outside the ranges plugins usually use. */
        const val REQUEST_CODE = 0x4E50
    }
}
