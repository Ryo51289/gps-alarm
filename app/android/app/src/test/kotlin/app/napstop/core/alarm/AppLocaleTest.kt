package app.napstop.core.alarm

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** T28 K01, K02: language tag parsing and the language file. */
class AppLocaleTest {
    @Test
    fun k01_parse() {
        assertEquals("vi", AppLocale.parse("vi"))
        assertEquals("en", AppLocale.parse(" en "))
        for (other in listOf("fr", "", "  ", null, "vi-VN", "EN", "en_US")) {
            assertNull(other, AppLocale.parse(other))
        }
    }

    @Test
    fun k02_fileRoundTrip() {
        val dir = Files.createTempDirectory("napstop-locale").toFile()
        try {
            val f = LocaleFile(dir)
            assertNull("no file = device", f.read())
            f.write("en")
            assertEquals("en", f.read())
            assertEquals("en", File(dir, AppLocale.FILE).readText())
            f.write("vi")
            assertEquals("vi", f.read())
            assertFalse("no temp file left", File(dir, "${AppLocale.FILE}.tmp").exists())
            f.write(null)
            assertFalse(File(dir, AppLocale.FILE).exists())
            assertNull(f.read())
            // Unsupported values are not stored.
            f.write("fr")
            assertFalse(File(dir, AppLocale.FILE).exists())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun k02_garbageOrLargeFileReadsAsDevice() {
        val dir = Files.createTempDirectory("napstop-locale").toFile()
        try {
            val file = File(dir, AppLocale.FILE)
            file.writeText("xx")
            assertNull(LocaleFile(dir).read())
            file.writeText("en" + " ".repeat(20))
            assertTrue(file.length() > LocaleFile.MAX_BYTES)
            assertNull(LocaleFile(dir).read())
            file.writeBytes(byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0x00))
            assertNull(LocaleFile(dir).read())
            // A directory where the file should be: read is null, never throws.
            file.delete()
            file.mkdirs()
            assertNull(LocaleFile(dir).read())
        } finally {
            dir.deleteRecursively()
        }
    }
}
