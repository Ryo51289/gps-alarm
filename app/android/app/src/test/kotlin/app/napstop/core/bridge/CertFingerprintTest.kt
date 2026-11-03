package app.napstop.core.bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** T23 TK01: SHA-1 of the signing certificate for `X-Android-Cert`, key placeholder. */
class CertFingerprintTest {
    @Test
    fun sha1HexOfAbc() {
        assertEquals(
            "A9993E364706816ABA3E25717850C26C9CD0D89D",
            CertFingerprint.sha1Hex("abc".toByteArray(Charsets.US_ASCII)),
        )
    }

    @Test
    fun sha1HexIs40UpperCaseHexWithoutColons() {
        val hex = CertFingerprint.sha1Hex(ByteArray(300) { it.toByte() })
        assertEquals(40, hex.length)
        assertEquals(hex, hex.uppercase())
        assertEquals(true, hex.all { it in '0'..'9' || it in 'A'..'F' })
    }

    @Test
    fun usableKey() {
        assertNull(CertFingerprint.usableKey(null))
        assertNull(CertFingerprint.usableKey(""))
        assertNull(CertFingerprint.usableKey("   "))
        assertNull(CertFingerprint.usableKey("DEFAULT_API_KEY"))
        assertNull(CertFingerprint.usableKey(" DEFAULT_API_KEY "))
        assertEquals("k-123", CertFingerprint.usableKey(" k-123 "))
    }
}
