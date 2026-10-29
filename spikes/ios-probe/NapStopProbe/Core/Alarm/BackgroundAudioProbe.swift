import AVFoundation
import Foundation

/// S3-14 (H8): can the app start playing audio from the background without the `audio` background mode?
/// Every step is logged as `bg_audio {step, ok, code, msg}`; `msg` is the four-char code ('!int' = cannotInterruptOthers).
final class BackgroundAudioProbe {
    static let shared = BackgroundAudioProbe()

    private var player: AVAudioPlayer?
    private let events = EventLog.shared

    func run(runId: String) {
        let session = AVAudioSession.sharedInstance()
        step("category", runId) { try session.setCategory(.playback, mode: .default, options: []) }
        var active = step("activate", runId) { try session.setActive(true) }
        if !active {
            step("category_mix", runId) { try session.setCategory(.playback, mode: .default, options: [.mixWithOthers]) }
            active = step("activate_mix", runId) { try session.setActive(true) }
        }
        guard active else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: ToneFile.url)
            player.numberOfLoops = 1       // 2 × 29 s ≈ 60 s
            player.volume = 1
            let ok = player.play()
            self.player = player
            events.log(to: runId, "bg_audio", ["step": "play", "ok": .flag(ok), "code": .null, "msg": .null])
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                self?.player?.stop()
                self?.player = nil
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        } catch {
            log(failure: error, step: "play", runId: runId)
        }
    }

    @discardableResult
    private func step(_ name: String, _ runId: String, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            events.log(to: runId, "bg_audio", ["step": .str(name), "ok": true, "code": .null, "msg": .null])
            return true
        } catch {
            log(failure: error, step: name, runId: runId)
            return false
        }
    }

    private func log(failure error: Error, step: String, runId: String) {
        let ns = error as NSError
        events.log(to: runId, "bg_audio", [
            "step": .str(step), "ok": false, "code": .num(ns.code), "msg": .str(FourCC.string(ns.code) ?? ns.domain),
        ])
    }
}
