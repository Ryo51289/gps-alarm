package app.napstop.core.trip.runtime

import java.io.File
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Properties

/**
 * [RuntimeStore] on plain files (spec T15 §5.7). Production [dir] = noBackupFilesDir/napstop_trip, which Auto Backup
 * and device transfer always exclude [A-BAK]. Every write is tmp + fsync + atomic rename (as the T14 StubStore).
 * Blocking: call on an IO dispatcher. [warn] receives error codes only, never file content.
 */
class FileRuntimeStore(private val dir: File, private val warn: (String) -> Unit) : RuntimeStore {
    private val activeFile get() = File(dir, ACTIVE_FILE)
    private val ledgerFile get() = File(dir, LEDGER_FILE)
    private val ringConfigFile get() = File(dir, RING_CONFIG_FILE)
    private val finishedDir get() = File(dir, FINISHED_DIR)

    override fun readActive(): StoredTrip? {
        val file = activeFile
        if (!file.exists()) return null
        return try {
            RuntimeCodec.decodeTrip(load(file))
        } catch (e: Exception) {
            // Corrupt or unknown version: drop it (T10 RK8); the ledger keeps the fallback alarm.
            warn("snapshot invalid (${e.javaClass.simpleName})")
            file.delete()
            null
        }
    }

    override fun writeActive(t: StoredTrip) = writeAtomic(activeFile, RuntimeCodec.encodeTrip(t))

    override fun deleteActive() {
        activeFile.delete()
    }

    override fun readLedger(): FallbackLedger {
        val file = ledgerFile
        if (!file.exists()) return FallbackLedger.EMPTY
        return try {
            RuntimeCodec.decodeLedger(load(file))
        } catch (e: Exception) {
            warn("ledger invalid (${e.javaClass.simpleName})")
            file.delete()
            FallbackLedger.EMPTY
        }
    }

    override fun writeLedger(l: FallbackLedger) = writeAtomic(ledgerFile, RuntimeCodec.encodeLedger(l))

    override fun writeRingConfig(c: RingConfig) = writeAtomic(ringConfigFile, RuntimeCodec.encodeRingConfig(c))

    override fun readRingConfig(): RingConfig? {
        val file = ringConfigFile
        if (!file.exists()) return null
        return try {
            RuntimeCodec.decodeRingConfig(load(file))
        } catch (e: Exception) {
            warn("ring config invalid (${e.javaClass.simpleName})")
            null
        }
    }

    override fun deleteRingConfig() {
        ringConfigFile.delete()
    }

    override fun writeFinished(r: FinishedRecord) {
        require(SAFE_ID.matches(r.tripId)) { "tripId" }
        writeAtomic(File(finishedDir, r.tripId + SUFFIX), RuntimeCodec.encodeFinished(r))
    }

    override fun readFinished(): List<FinishedRecord> {
        val files = finishedDir.listFiles { f -> f.isFile && f.name.endsWith(SUFFIX) } ?: return emptyList()
        return files.mapNotNull { file ->
            try {
                RuntimeCodec.decodeFinished(load(file))
            } catch (e: Exception) {
                warn("finished record invalid (${e.javaClass.simpleName})")
                file.delete()
                null
            }
        }.sortedWith(compareBy<FinishedRecord> { it.endedAtMs }.thenBy { it.tripId })
    }

    override fun deleteFinished(ids: List<String>) {
        for (id in ids) {
            // Ids come from Dart: only plain file names inside finished/.
            if (SAFE_ID.matches(id)) File(finishedDir, id + SUFFIX).delete()
        }
    }

    private fun load(file: File): Properties = Properties().apply { file.inputStream().use { load(it) } }

    private fun writeAtomic(target: File, p: Properties) {
        val parent = target.parentFile ?: throw IOException("no parent")
        if (!parent.isDirectory && !parent.mkdirs()) throw IOException("mkdirs failed")
        val tmp = File(parent, target.name + ".tmp")
        tmp.outputStream().use { out ->
            p.store(out, null)
            out.fd.sync()
        }
        try {
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    companion object {
        const val DIR_NAME = "napstop_trip"
        const val ACTIVE_FILE = "active_trip.properties"
        const val LEDGER_FILE = "fallback_ledger.properties"
        const val RING_CONFIG_FILE = "ring_config.properties"
        const val FINISHED_DIR = "finished"
        private const val SUFFIX = ".properties"
        private val SAFE_ID = Regex("^[A-Za-z0-9_-]{1,64}$")
    }
}
