package app.napstop.probe

import android.content.Context
import android.os.Process
import android.os.SystemClock
import android.util.Log
import app.napstop.probe.analysis.FlatJson
import app.napstop.probe.analysis.ParsedLog
import app.napstop.probe.analysis.ProbeEventParser
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.FileOutputStream
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * JSON Lines event log (S1 §5.7): `runs/<runId>/events.jsonl`, or `runs/orphan.jsonl` outside a run.
 * Producers enqueue from any thread; a single coroutine on Dispatchers.IO writes. Each line is written with one
 * unbuffered write() (lands in the OS page cache, survives a process kill); fsync after important events and at
 * least every 60 s. Never contains coordinates (privacy rule D4).
 */
object EventLog {
    private const val TAG = "NapStopProbe"
    private const val SYNC_INTERVAL_MS = 60_000L
    private val SYNC_PREFIXES = listOf("run_", "svc_", "alarm_")
    private val SYNC_EVENTS = setOf("exit_info", "self_kill_now")
    private val TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSXXX")

    private sealed interface Record {
        class Line(val runId: String, val text: String, val sync: Boolean) : Record
        class Sync(val done: CompletableDeferred<Unit>) : Record
    }

    private val channel = Channel<Record>(Channel.UNLIMITED)
    private val seq = AtomicLong(0)
    private val started = AtomicBoolean(false)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Run that new events belong to ("" = none → orphan.jsonl). */
    @Volatile
    var currentRunId: String = ""

    @Volatile
    lateinit var runsDir: File
        private set

    fun init(context: Context) {
        if (!started.compareAndSet(false, true)) return
        // getExternalFilesDir is adb-pullable without root; filesDir is the fallback (S1 §5.7).
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        runsDir = File(base, "runs")
        scope.launch { writerLoop() }
    }

    /** Wall-clock ISO-8601 with offset and ms (same format as the `t` field). */
    fun iso(epochMs: Long): String =
        OffsetDateTime.ofInstant(Instant.ofEpochMilli(epochMs), ZoneId.systemDefault()).format(TIME)

    fun log(ev: String, vararg fields: Pair<String, Any?>) = log(ev, fields.toMap())

    fun log(ev: String, fields: Map<String, Any?>) = logTo(currentRunId, ev, fields)

    /** Logs into an explicit run ("" = orphan.jsonl), independent of [currentRunId]. */
    fun logTo(runId: String, ev: String, fields: Map<String, Any?>) {
        val map = LinkedHashMap<String, Any?>(fields.size + 6)
        map["ev"] = ev
        map["t"] = OffsetDateTime.now().format(TIME)
        map["et"] = SystemClock.elapsedRealtime()
        map["run"] = runId
        map["pid"] = Process.myPid()
        map["seq"] = seq.incrementAndGet()
        for ((k, v) in fields) if (k !in map) map[k] = v
        val text = FlatJson.encode(map)
        Log.d(TAG, text)
        val sync = ev in SYNC_EVENTS || SYNC_PREFIXES.any { ev.startsWith(it) }
        channel.trySend(Record.Line(runId, text, sync))
    }

    /**
     * Blocks until everything queued so far is written and fsync'ed (max [timeoutMs]).
     * Only call from a background thread (used right before Process.killProcess).
     */
    fun syncBlocking(timeoutMs: Long = 2_000L) {
        val done = CompletableDeferred<Unit>()
        channel.trySend(Record.Sync(done))
        runBlocking { withTimeoutOrNull(timeoutMs) { done.await() } }
    }

    private suspend fun writerLoop() {
        var openRun: String? = null
        var out: FileOutputStream? = null
        var lastSync = SystemClock.elapsedRealtime()
        for (record in channel) {
            try {
                when (record) {
                    is Record.Line -> {
                        if (out == null || openRun != record.runId) {
                            out?.close()
                            out = FileOutputStream(fileFor(record.runId), true)
                            openRun = record.runId
                        }
                        out.write((record.text + "\n").toByteArray(Charsets.UTF_8))
                        out.flush()
                        val now = SystemClock.elapsedRealtime()
                        if (record.sync || now - lastSync >= SYNC_INTERVAL_MS) {
                            out.fd.sync()
                            lastSync = now
                        }
                    }
                    is Record.Sync -> {
                        out?.fd?.sync()
                        lastSync = SystemClock.elapsedRealtime()
                        record.done.complete(Unit)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "event log write failed: ${e.javaClass.simpleName}")
                runCatching { out?.close() }
                out = null
                if (record is Record.Sync) record.done.complete(Unit)
            }
        }
    }

    private fun fileFor(runId: String): File {
        val file = if (runId.isEmpty()) File(runsDir, "orphan.jsonl") else File(File(runsDir, runId), "events.jsonl")
        file.parentFile?.mkdirs()
        return file
    }

    // ---- reading (SummaryActivity, call off the main thread) ----

    /** Pure parsing of JSON Lines; corrupt lines are skipped and counted (U02). */
    fun parse(lines: Sequence<String>): ParsedLog = ProbeEventParser.parse(lines)

    fun listRuns(): List<String> =
        runsDir.listFiles { f -> f.isDirectory }?.map { it.name }?.sortedDescending() ?: emptyList()

    fun readRun(runId: String): ParsedLog {
        val file = File(File(runsDir, runId), "events.jsonl")
        if (!file.exists()) return ParsedLog(emptyList(), 0)
        return file.bufferedReader(Charsets.UTF_8).useLines { parse(it) }
    }

    fun deleteRun(runId: String): Boolean = File(runsDir, runId).deleteRecursively()
}
