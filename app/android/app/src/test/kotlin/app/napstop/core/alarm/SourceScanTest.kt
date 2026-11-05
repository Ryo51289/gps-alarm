package app.napstop.core.alarm

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T16 AA5 (+ A39 for :app): the interim alarm is gone; `:ring` code stays apart; the manifest has the ring components.
 * T28 K05: every native display string goes through [AppLocale].
 */
class SourceScanTest {
    private val main = File("src/main")
    private val kotlinFiles = File(main, "kotlin").walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    @Test
    fun aa5_interimPortIsGone() {
        assertTrue(kotlinFiles.size > 20)
        for (f in kotlinFiles) {
            val src = f.readText()
            assertFalse(f.path, src.contains("InterimAlarmPort"))
            assertFalse(f.path, src.contains("EXTRA_INTERIM"))
            if (src.contains("napstop_alarm_interim")) assertEquals(f.path, "AlarmChannels.kt", f.name)
        }
        assertFalse(File(main, "kotlin/app/napstop/core/alarm/InterimAlarmPort.kt").exists())
        assertFalse(File(main, "kotlin/app/napstop/core/bridge/AlarmHostApiStub.kt").exists())
        // The channel is deleted on ensure.
        assertTrue(File(main, "kotlin/app/napstop/core/alarm/AlarmChannels.kt").readText().contains("deleteNotificationChannel(INTERIM_REMOVED)"))
    }

    @Test
    fun ringProcessCodeImportsNothingOfTheMainRuntime() {
        val ring = kotlinFiles.filter { it.path.replace('\\', '/').contains("/core/alarm/ring/") }
        assertTrue(ring.size >= 10)
        for (f in ring) {
            val src = f.readText()
            for (banned in listOf("RuntimeHost", "import io.flutter", "import com.google.firebase", "println(", "printStackTrace")) {
                assertFalse("${f.name}: $banned", src.contains(banned))
            }
        }
    }

    @Test
    fun manifestDeclaresTheRingProcess() {
        val m = File(main, "AndroidManifest.xml").readText()
        for (name in listOf(".core.alarm.ring.AlarmRingService", ".core.alarm.ring.AlarmActivity", ".core.alarm.ring.RingCommandReceiver")) {
            val i = m.indexOf("android:name=\"$name\"")
            assertTrue(name, i > 0)
            val tag = m.substring(i, m.indexOf("/>", i))
            assertTrue("$name in :ring", tag.contains("android:process=\":ring\""))
            assertTrue("$name not exported", tag.contains("android:exported=\"false\""))
        }
        assertTrue(m.contains("android:foregroundServiceType=\"systemExempted|mediaPlayback\""))
        assertTrue(m.contains("FOREGROUND_SERVICE_SYSTEM_EXEMPTED") && m.contains("FOREGROUND_SERVICE_MEDIA_PLAYBACK"))
        for (never in listOf("ACCESS_BACKGROUND_LOCATION", "SYSTEM_ALERT_WINDOW", "ACCESS_NOTIFICATION_POLICY", "android.permission.CAMERA")) {
            assertFalse(never, m.contains(never))
        }
    }

    @Test
    fun soundsAreSmall() {
        for (n in listOf("alarm_horn", "alarm_bell", "alarm_beep")) {
            val f = File(main, "res/raw/$n.wav")
            assertTrue(n, f.isFile && f.length() in 1..200_000)
        }
    }

    /** Source without comments (KDoc may name AppLocale without using it). */
    private fun code(f: File): String =
        f.readText().replace(Regex("/\\*.*?\\*/", RegexOption.DOT_MATCHES_ALL), "").replace(Regex("//[^\n]*"), "")

    @Test
    fun k05_nativeStringsGoThroughAppLocale() {
        // Resolvers that only read strings from the Context their caller localized (no applicationContext of their own).
        val resolvers = setOf("AlarmChannels.kt", "RingStrings.kt", "RingNotifications.kt")
        var withStrings = 0
        for (f in kotlinFiles) {
            val src = code(f)
            if (!src.contains("getString(R.string.") && !src.contains("getString(id")) continue
            withStrings++
            if (f.name in resolvers) {
                assertFalse("${f.name}: strings of its own app context", src.contains("applicationContext.getString("))
                continue
            }
            assertTrue("${f.name} reads strings without AppLocale", src.contains("AppLocale."))
        }
        assertTrue(withStrings >= 7)
        for (f in kotlinFiles) {
            val src = code(f)
            if (f.name != "AppLocale.kt") {
                assertFalse("${f.name}: locale of the resources instead of AppLocale", src.contains("configuration.locales[0]"))
            }
            for (banned in listOf("LocaleManager", "setApplicationLocales")) assertFalse("${f.name}: $banned (T28 D9)", src.contains(banned))
        }
        assertFalse(File(main, "AndroidManifest.xml").readText().contains("localeConfig"))
    }

    @Test
    fun k05_ringProcessNeverReadsTheLanguageFile() {
        val ring = kotlinFiles.filter { it.path.replace('\\', '/').contains("/core/alarm/ring/") }
        assertTrue(ring.size >= 10)
        for (f in ring) {
            val src = code(f)
            for (banned in listOf("AppLocale.FILE", "AppLocale.tag(", "AppLocale.localized(", "AppLocale.locale(", "AppLocale.set(", "LocaleFile")) {
                assertFalse("${f.name}: $banned", src.contains(banned))
            }
        }
        // The backup ring notifier runs in both processes: it uses the tag of its RingStart only.
        val backup = code(File(main, "kotlin/app/napstop/core/alarm/BackupRingNotifier.kt"))
        assertTrue(backup.contains("AppLocale.localizedWith(ctx, s.localeTag)"))
        assertFalse(backup.contains("AppLocale.localized("))
    }
}
