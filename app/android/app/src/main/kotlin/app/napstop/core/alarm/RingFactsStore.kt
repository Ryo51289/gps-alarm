package app.napstop.core.alarm

import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Properties

/**
 * The ring book on disk (spec T16 §4.6): `<dir>/<tripId>.properties`, shared by the main process and `:ring`. Every
 * read-modify-write holds `<dir>/.lock` with FileChannel.lock() (cross-process) plus a JVM monitor (FileLock is per
 * process: two threads of one process must not both hold it). Writes: tmp file, fsync when asked, rename. Plain java.io
 * only, so it is JVM-tested (AA4). Called off the main thread.
 */
class RingFactsStore(private val dir: File, private val syncWrites: Boolean = true) : RingFactsSource {
    private val lockFile = File(dir, ".lock")

    override fun read(tripId: String): RingFactsRecord? = locked { readFile(tripId) }

    override fun update(tripId: String, f: (RingFactsRecord?) -> RingFactsRecord?): RingFactsRecord? = update(tripId, syncWrites, f)

    /** [sync] false: heartbeat (losing it on power loss is harmless: another boot count). */
    fun update(tripId: String, sync: Boolean, f: (RingFactsRecord?) -> RingFactsRecord?): RingFactsRecord? =
        locked {
            val old = readFile(tripId)
            val new = f(old)
            if (new == null) {
                file(tripId).delete()
            } else if (new != old || !file(tripId).exists()) {
                writeFile(tripId, new, sync)
            }
            new
        }

    override fun delete(tripId: String) {
        locked { file(tripId).delete() }
    }

    override fun listRinging(): List<RingFactsRecord> =
        locked {
            (dir.listFiles { f -> f.name.endsWith(SUFFIX) } ?: emptyArray())
                .mapNotNull { readFile(it.name.removeSuffix(SUFFIX)) }
                .filter { it.ringing }
        }

    private fun file(tripId: String): File {
        require(TRIP_ID.matches(tripId)) { "tripId" }
        return File(dir, tripId + SUFFIX)
    }

    private fun readFile(tripId: String): RingFactsRecord? {
        val f = file(tripId)
        if (!f.isFile) return null
        return try {
            val p = Properties().apply { f.inputStream().use { load(it) } }
            RingFactsCodec.decode(p)?.takeIf { it.tripId == tripId }
        } catch (e: IOException) {
            null
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    private fun writeFile(tripId: String, r: RingFactsRecord, sync: Boolean) {
        val tmp = File(dir, "$tripId$SUFFIX.tmp")
        tmp.outputStream().use { out ->
            RingFactsCodec.encode(r).store(out, null)
            if (sync) out.fd.sync()
        }
        try {
            // Atomic replace (rename(2) on Android; also replaces an existing file on the Windows JVM of the tests).
            Files.move(tmp.toPath(), file(tripId).toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } catch (e: IOException) {
            tmp.delete()
            throw e
        }
    }

    private inline fun <T> locked(block: () -> T): T =
        synchronized(JVM_LOCK) {
            if (!dir.isDirectory) dir.mkdirs()
            RandomAccessFile(lockFile, "rw").use { raf ->
                raf.channel.lock().use { block() }
            }
        }

    companion object {
        const val DIR_NAME = "napstop_ring"
        private const val SUFFIX = ".properties"
        private val TRIP_ID = Regex("^[A-Za-z0-9_-]{1,64}$")
        private val JVM_LOCK = Any()
    }
}
