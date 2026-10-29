package app.napstop.probe

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioGroup
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.net.toUri
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import app.napstop.probe.analysis.RunAnalyzer
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDateTime
import kotlin.math.roundToInt

/** Main probe screen (S1 §5.5): device, permissions, S1/S2 start, running run, results. */
class MainActivity : ComponentActivity() {

    private lateinit var store: RunStore
    private var bootCount = -1
    private lateinit var permContainer: LinearLayout
    private lateinit var runStatus: TextView
    private lateinit var btnStartS1: Button
    private lateinit var btnStartS2: Button
    private lateinit var btnStopRun: Button
    private lateinit var btnSelfKill: Button

    // Lint InvalidFragmentVersionForActivityResult is a false positive here: fragment 1.0.0 only comes in
    // transitively (play-services-base) and this is a ComponentActivity, not a FragmentActivity.
    @SuppressLint("InvalidFragmentVersionForActivityResult")
    private val requestLocation =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { refreshPermissions() }
    @SuppressLint("InvalidFragmentVersionForActivityResult")
    private val requestSingle =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { refreshPermissions() }

    private class Row(val title: String, val status: String, val actions: List<Pair<String, () -> Unit>> = emptyList())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.scroll).applySystemBarsPadding()
        store = RunStore(this)
        bootCount = DeviceSnapshot.bootCount(this)
        permContainer = findViewById(R.id.permContainer)
        runStatus = findViewById(R.id.runStatus)
        btnStartS1 = findViewById(R.id.btnStartS1)
        btnStartS2 = findViewById(R.id.btnStartS2)
        btnStopRun = findViewById(R.id.btnStopRun)
        btnSelfKill = findViewById(R.id.btnSelfKill)

        showDeviceInfo()
        btnStartS1.setOnClickListener { startS1() }
        btnStartS2.setOnClickListener { startS2() }
        btnStopRun.setOnClickListener { confirmStop() }
        btnSelfKill.setOnClickListener {
            startService(ProbeService.selfKillIntent(this))
            Toast.makeText(this, R.string.self_kill_sent, Toast.LENGTH_LONG).show()
        }
        findViewById<Button>(R.id.btnResults).setOnClickListener {
            startActivity(Intent(this, SummaryActivity::class.java))
        }

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.RESUMED) {
                while (true) {
                    refreshRun()
                    delay(1_000L)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshPermissions()
    }

    private fun showDeviceInfo() {
        val d = DeviceSnapshot.device(this)
        findViewById<TextView>(R.id.deviceInfo).text = getString(
            R.string.device_info,
            d["manufacturer"], d["brand"], d["model"], d["release"], Build.VERSION.SDK_INT,
            d["display"], d["secPatch"], d["gms"],
        )
    }

    // ---- permissions & power ----

    private fun refreshPermissions() {
        val st = DeviceSnapshot.permState(this)
        val rows = ArrayList<Row>()

        rows += Row(
            getString(R.string.perm_fine),
            when {
                st.fine -> getString(R.string.status_granted)
                st.coarse -> getString(R.string.status_coarse_only)
                else -> getString(R.string.status_denied)
            },
            listOf(getString(R.string.btn_grant) to {
                requestLocation.launch(
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                )
            }),
        )

        rows += if (Build.VERSION.SDK_INT >= 29) {
            val label = if (Build.VERSION.SDK_INT >= 30) {
                "\n" + getString(R.string.perm_bg_label, packageManager.backgroundPermissionOptionLabel)
            } else {
                ""
            }
            Row(
                getString(R.string.perm_bg),
                grantedText(st.bg == true) + label,
                // API 29: runtime dialog; API 30+: the same request sends the user to the settings page [A10].
                listOf(getString(R.string.btn_open_settings) to {
                    requestSingle.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                }),
            )
        } else {
            Row(getString(R.string.perm_bg), getString(R.string.status_na))
        }

        val notifStatus = when {
            st.notif == false -> getString(R.string.status_denied)
            !st.notifEnabled -> if (st.notif == true) getString(R.string.status_notif_blocked) else getString(R.string.status_denied)
            else -> getString(R.string.status_granted)
        }
        rows += Row(
            getString(R.string.perm_notif),
            notifStatus,
            listOf(getString(R.string.btn_grant) to {
                if (Build.VERSION.SDK_INT >= 33 && st.notif == false) {
                    requestSingle.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    openSettings(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                    )
                }
            }),
        )

        rows += if (Build.VERSION.SDK_INT >= 34) {
            Row(
                getString(R.string.perm_fsi),
                grantedText(st.fsi == true),
                listOf(getString(R.string.btn_open_settings) to {
                    openSettings(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri()))
                }),
            )
        } else {
            Row(getString(R.string.perm_fsi), getString(R.string.status_na_always))
        }

        rows += Row(
            getString(R.string.perm_exact),
            st.exact?.let { grantedText(it) } ?: getString(R.string.status_na),
        )

        rows += Row(
            getString(R.string.perm_battery),
            getString(if (st.ignBatOpt) R.string.status_battery_exempt else R.string.status_battery_optimized),
            listOf(
                getString(R.string.btn_request_exempt) to { requestBatteryExemption() },
                getString(R.string.btn_exempt_list) to {
                    openSettings(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                },
            ),
        )

        rows += Row(
            getString(R.string.perm_bg_restricted),
            st.bgRestricted?.let { getString(if (it) R.string.status_yes else R.string.status_no) }
                ?: getString(R.string.status_na),
        )
        rows += Row(getString(R.string.perm_bucket), st.bucket ?: getString(R.string.status_na))
        rows += Row(
            getString(R.string.perm_power_save),
            getString(if (st.powerSave) R.string.status_on else R.string.status_off),
        )
        rows += Row(getString(R.string.perm_alarm_volume), getString(R.string.status_volume, st.alarmVol, st.alarmVolMax))
        rows += Row(
            getString(R.string.perm_app_settings),
            "",
            listOf(getString(R.string.btn_open_app_page) to {
                openSettings(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri()))
            }),
        )

        renderRows(rows)
    }

    private fun renderRows(rows: List<Row>) {
        permContainer.removeAllViews()
        for (row in rows) {
            val view = layoutInflater.inflate(R.layout.row_perm, permContainer, false)
            view.findViewById<TextView>(R.id.permTitle).text = row.title
            view.findViewById<TextView>(R.id.permStatus).apply {
                text = row.status
                visibility = if (row.status.isEmpty()) View.GONE else View.VISIBLE
            }
            val actions = view.findViewById<LinearLayout>(R.id.permActions)
            for ((label, action) in row.actions) {
                val button = Button(this).apply {
                    text = label
                    isAllCaps = false
                    textSize = 16f
                    minHeight = (48 * resources.displayMetrics.density).roundToInt()
                    setOnClickListener { action() }
                }
                actions.addView(button, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            }
            permContainer.addView(view)
        }
    }

    private fun grantedText(granted: Boolean) = getString(if (granted) R.string.status_granted else R.string.status_denied)

    private fun packageUri() = "package:$packageName".toUri()

    // Probe only: direct request so the battery step is one tap; production follows S5 (Play restricts this) [A4].
    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption() {
        openSettings(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, packageUri()))
    }

    private fun openSettings(intent: Intent) {
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri()))
        }
    }

    // ---- start / stop ----

    private fun startS1() {
        val st = DeviceSnapshot.permState(this)
        if (!st.hasLocation) return showMessage(getString(R.string.err_no_location))
        val hours = findViewById<EditText>(R.id.s1Duration).text.toString().replace(',', '.').toDoubleOrNull()
        val dense = findViewById<EditText>(R.id.s1Dense).text.toString().toIntOrNull()
        val durationMin = hours?.let { (it * 60).roundToInt() }
        if (durationMin == null || durationMin <= 0 || dense == null || dense < 0 || dense > durationMin) {
            return showMessage(getString(R.string.err_bad_numbers))
        }
        val label = when (findViewById<RadioGroup>(R.id.s1Label).checkedRadioButtonId) {
            R.id.s1LabelB -> "B"
            R.id.s1LabelR1 -> "R1"
            R.id.s1LabelR2 -> "R2"
            R.id.s1LabelOther -> "X"
            else -> "A"
        }
        val cfg = newConfig(
            kind = RunConfig.KIND_S1,
            label = label,
            durationMin = durationMin,
            densePhaseMin = dense,
            alarmAtEnd = findViewById<CheckBox>(R.id.s1AlarmAtEnd).isChecked,
            watchdog = findViewById<CheckBox>(R.id.s1Watchdog).isChecked,
            delayMin = null,
            scenario = null,
        )
        startRun(cfg, st)
    }

    private fun startS2() {
        val st = DeviceSnapshot.permState(this)
        if (!st.hasLocation) return showMessage(getString(R.string.err_no_location))
        val scenario = "S2-${findViewById<Spinner>(R.id.s2Scenario).selectedItemPosition + 1}"
        val delay = when (findViewById<RadioGroup>(R.id.s2Delay).checkedRadioButtonId) {
            R.id.s2Delay1 -> 1
            R.id.s2Delay5 -> 5
            R.id.s2Delay30 -> 30
            else -> 2
        }
        // S2: dense phase (HIGH_ACCURACY, 10 s) for the whole run, alarm at start + delay (S2 §5.1).
        val cfg = newConfig(
            kind = RunConfig.KIND_S2,
            label = scenario,
            durationMin = delay,
            densePhaseMin = delay,
            alarmAtEnd = true,
            watchdog = findViewById<CheckBox>(R.id.s2Watchdog).isChecked,
            delayMin = delay,
            scenario = scenario,
        )
        startRun(cfg, st)
    }

    private fun newConfig(
        kind: String,
        label: String,
        durationMin: Int,
        densePhaseMin: Int,
        alarmAtEnd: Boolean,
        watchdog: Boolean,
        delayMin: Int?,
        scenario: String?,
    ) = RunConfig(
        runId = RunConfig.makeRunId(LocalDateTime.now(), kind, label),
        kind = kind,
        label = label,
        durationMin = durationMin,
        densePhaseMin = densePhaseMin,
        alarmAtEnd = alarmAtEnd,
        watchdog = watchdog,
        delayMin = delayMin,
        scenario = scenario,
        startWallMs = System.currentTimeMillis(),
        startElapsed = SystemClock.elapsedRealtime(),
        bootCount = DeviceSnapshot.bootCount(this),
    )

    /** Called from a click, so the activity is visible (while-in-use FGS start [A2]). */
    private fun startRun(cfg: RunConfig, st: PermState) {
        if (store.activeRun() != null) return
        ProbeService.startRun(this, cfg)
        refreshRun()
        val missing = buildList {
            if (st.bg == false) add(getString(R.string.perm_bg))
            if (!st.notifEnabled || st.notif == false) add(getString(R.string.perm_notif))
            if (st.fsi == false) add(getString(R.string.perm_fsi))
            if (st.exact == false) add(getString(R.string.perm_exact))
        }
        if (missing.isNotEmpty()) {
            AlertDialog.Builder(this)
                .setTitle(R.string.warn_missing_title)
                .setMessage(getString(R.string.warn_missing_message, missing.joinToString(", ")))
                .setPositiveButton(R.string.ok, null)
                .show()
        }
    }

    private fun confirmStop() {
        AlertDialog.Builder(this)
            .setTitle(R.string.confirm_stop_title)
            .setMessage(R.string.confirm_stop_message)
            .setPositiveButton(R.string.confirm_yes) { _, _ -> startService(ProbeService.stopIntent(this)) }
            .setNegativeButton(R.string.confirm_cancel, null)
            .show()
    }

    private fun showMessage(message: String) {
        AlertDialog.Builder(this).setMessage(message).setPositiveButton(R.string.ok, null).show()
    }

    // ---- running run ----

    private fun refreshRun() {
        val cfg = store.activeRun()
        btnStartS1.isEnabled = cfg == null
        btnStartS2.isEnabled = cfg == null
        btnStopRun.isEnabled = cfg != null
        // Only while the service runs: otherwise startService would create a non-foreground sticky service (S1 5.5).
        btnSelfKill.isEnabled = cfg != null && ProbeService.running
        if (cfg == null) {
            runStatus.setText(R.string.run_none)
            return
        }
        val now = System.currentTimeMillis()
        val elapsedMs = cfg.elapsedMs(SystemClock.elapsedRealtime(), now, bootCount)
        val lastFix = store.lastFixWallMs?.let {
            getString(R.string.run_last_fix_ago, RunAnalyzer.fmtDur((now - it) / 1000L))
        } ?: getString(R.string.run_last_fix_none)
        val phase = getString(if (cfg.phaseAt(elapsedMs) == Phase.DENSE) R.string.phase_dense else R.string.phase_sparse)
        val alarm = cfg.deadlineWallMs?.let { ProbeService.clock(it) } ?: getString(R.string.run_alarm_none)
        runStatus.text = getString(
            R.string.run_status,
            cfg.runId,
            cfg.kind,
            cfg.label,
            RunAnalyzer.fmtHms(elapsedMs / 1000L),
            RunAnalyzer.fmtHms(cfg.durationMin * 60L),
            store.fixCount,
            lastFix,
            phase,
            alarm,
        )
    }
}

/** Target SDK 35+ enforces edge-to-edge: pad the root by the system bar insets. */
fun View.applySystemBarsPadding() {
    val start = paddingLeft
    val top = paddingTop
    val end = paddingRight
    val bottom = paddingBottom
    ViewCompat.setOnApplyWindowInsetsListener(this) { v, insets ->
        val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
        v.updatePadding(left = start + bars.left, top = top + bars.top, right = end + bars.right, bottom = bottom + bars.bottom)
        insets
    }
}
