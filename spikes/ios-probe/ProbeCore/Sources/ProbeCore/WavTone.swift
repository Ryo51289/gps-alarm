import Foundation

/// The probe alarm tone (S3 §6.7): written to `Library/Sounds/probe_alarm.wav` at first launch, so no binary file is
/// committed. Notification sounds must be shorter than 30 s, hence 29 s by default.
public enum WavTone {
    public static let headerSize = 44

    /// PCM 16-bit mono little-endian. Each 1 s cycle = 500 ms sine at `freq` (10 ms fade in/out) + 500 ms silence.
    public static func make(seconds: Int = 29, sampleRate: Int = 44_100, freq: Double = 880, amplitude: Double = 0.8) -> Data {
        let totalSamples = max(0, seconds) * sampleRate
        let dataSize = totalSamples * 2
        var bytes: [UInt8] = []
        bytes.reserveCapacity(headerSize + dataSize)

        appendASCII(&bytes, "RIFF")
        appendUInt32(&bytes, UInt32(36 + dataSize))
        appendASCII(&bytes, "WAVE")
        appendASCII(&bytes, "fmt ")
        appendUInt32(&bytes, 16)                      // fmt chunk size
        appendUInt16(&bytes, 1)                       // PCM
        appendUInt16(&bytes, 1)                       // mono
        appendUInt32(&bytes, UInt32(sampleRate))
        appendUInt32(&bytes, UInt32(sampleRate * 2))  // byte rate
        appendUInt16(&bytes, 2)                       // block align
        appendUInt16(&bytes, 16)                      // bits per sample
        appendASCII(&bytes, "data")
        appendUInt32(&bytes, UInt32(dataSize))

        let half = sampleRate / 2
        let fade = max(1, sampleRate / 100)           // 10 ms
        let amp = min(1.0, max(0.0, amplitude))
        let step = 2.0 * Double.pi * freq / Double(sampleRate)
        for i in 0..<totalSamples {
            let pos = i % sampleRate
            var value: Int16 = 0
            if pos < half {
                let gain = min(1.0, Double(pos) / Double(fade), Double(half - 1 - pos) / Double(fade))
                let sample = sin(step * Double(pos)) * amp * gain * 32_767.0
                value = Int16(max(-32_767.0, min(32_767.0, sample.rounded())))
            }
            let u = UInt16(bitPattern: value)
            bytes.append(UInt8(u & 0xFF))
            bytes.append(UInt8(u >> 8))
        }
        return Data(bytes)
    }

    private static func appendASCII(_ bytes: inout [UInt8], _ s: String) {
        bytes.append(contentsOf: Array(s.utf8))
    }

    private static func appendUInt16(_ bytes: inout [UInt8], _ v: UInt16) {
        bytes.append(UInt8(v & 0xFF))
        bytes.append(UInt8(v >> 8))
    }

    private static func appendUInt32(_ bytes: inout [UInt8], _ v: UInt32) {
        for shift in [0, 8, 16, 24] {
            bytes.append(UInt8((v >> UInt32(shift)) & 0xFF))
        }
    }
}
