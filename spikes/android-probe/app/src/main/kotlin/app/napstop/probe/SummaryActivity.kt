package app.napstop.probe

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import app.napstop.probe.analysis.RunAnalyzer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/** Run list (newest first) + RunAnalyzer text summary; share as plain text only (no files), delete (S1 §5.5). */
class SummaryActivity : ComponentActivity() {

    private lateinit var runList: LinearLayout
    private lateinit var summaryText: TextView
    private lateinit var btnShare: Button
    private lateinit var btnDelete: Button
    private var selectedRun: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_summary)
        findViewById<View>(R.id.scroll).applySystemBarsPadding()
        runList = findViewById(R.id.runList)
        summaryText = findViewById(R.id.summaryText)
        btnShare = findViewById(R.id.btnShare)
        btnDelete = findViewById(R.id.btnDelete)
        btnShare.setOnClickListener { share() }
        btnDelete.setOnClickListener { confirmDelete() }
        loadRuns()
    }

    private fun loadRuns() {
        lifecycleScope.launch {
            val runs = withContext(Dispatchers.IO) { EventLog.listRuns() }
            runList.removeAllViews()
            if (runs.isEmpty()) {
                runList.addView(TextView(this@SummaryActivity).apply {
                    setText(R.string.summary_empty)
                    textSize = 16f
                })
            }
            for (runId in runs) {
                val button = Button(this@SummaryActivity).apply {
                    text = runId
                    isAllCaps = false
                    textSize = 16f
                    minHeight = (48 * resources.displayMetrics.density).roundToInt()
                    setOnClickListener { showRun(runId) }
                }
                runList.addView(button, LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            }
        }
    }

    private fun showRun(runId: String) {
        lifecycleScope.launch {
            val text = withContext(Dispatchers.IO) {
                val parsed = EventLog.readRun(runId)
                val running = RunStore(this@SummaryActivity).activeRun()?.runId == runId
                val summary = RunAnalyzer.analyze(parsed.events, nowMs = System.currentTimeMillis(), active = running)
                val body = RunAnalyzer.render(summary)
                buildString {
                    if (running) {
                        append(getString(R.string.summary_running)).append('\n')
                    }
                    append(body)
                    if (parsed.corruptLines > 0) append('\n').append(getString(R.string.summary_corrupt, parsed.corruptLines))
                }
            }
            selectedRun = runId
            summaryText.text = text
            btnShare.isEnabled = true
            btnDelete.isEnabled = RunStore(this@SummaryActivity).activeRun()?.runId != runId
        }
    }

    private fun share() {
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, summaryText.text.toString())
        startActivity(Intent.createChooser(send, getString(R.string.share_chooser)))
    }

    private fun confirmDelete() {
        val runId = selectedRun ?: return
        AlertDialog.Builder(this)
            .setTitle(R.string.confirm_delete_title)
            .setMessage(getString(R.string.confirm_delete_message, runId))
            .setPositiveButton(R.string.confirm_delete_yes) { _, _ ->
                lifecycleScope.launch {
                    withContext(Dispatchers.IO) { EventLog.deleteRun(runId) }
                    selectedRun = null
                    summaryText.setText(R.string.summary_pick)
                    btnShare.isEnabled = false
                    btnDelete.isEnabled = false
                    loadRuns()
                }
            }
            .setNegativeButton(R.string.confirm_cancel, null)
            .show()
    }
}
