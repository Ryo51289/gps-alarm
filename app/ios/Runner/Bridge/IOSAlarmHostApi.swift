import AVFoundation
import Foundation
import TripRuntime
import os

/// Plays one bundled alarm file for "Nghe thử" (spec T17.2 D11). Main thread only (synchronous Pigeon calls arrive there).
protocol SoundPreviewing: AnyObject {
  /// Replaces a running preview; stops by itself after `maxMs`. Never throws (errors: type name in the log).
  func play(file: String, maxMs: Int64)
  func stop()
  var isPlaying: Bool { get }
}

/// `AlarmHostApi` on iOS (spec T17.2 §4): sound preview with AVFoundation, the route-back launch action, no native alarm
/// screen (AlarmKit's UI is the lock-screen UI; screen 5 Flutter shows when the app is open, T27 D1), and the native
/// language (`napstop.appLocale`, read by NativeCopy when an alarm is scheduled). PRIVACY: no coordinates; the launch
/// action carries a trip id and a distance only and is never logged.
final class IOSAlarmHostApi: AlarmHostApi {
  private let launchActions: @Sendable () async -> LaunchActionRec?
  private let routeBackInFlight: @Sendable () -> Bool
  private let alarmAlerting: () -> Bool
  private let preview: SoundPreviewing
  private let constants: RuntimeConstants
  private let sleep: @Sendable (Int64) async -> Void

  /// `launchActions` takes launch_action.json once (RuntimeHost → TripRuntime.consumeLaunchAction).
  init(
    launchActions: @escaping @Sendable () async -> LaunchActionRec?,
    routeBackInFlight: @escaping @Sendable () -> Bool,
    alarmAlerting: @escaping () -> Bool,
    preview: SoundPreviewing = AVSoundPreview(),
    constants: RuntimeConstants = .default,
    sleep: @escaping @Sendable (Int64) async -> Void = { ms in
      try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
    }
  ) {
    self.launchActions = launchActions
    self.routeBackInFlight = routeBackInFlight
    self.alarmAlerting = alarmAlerting
    self.preview = preview
    self.constants = constants
    self.sleep = sleep
  }

  /// D11, Q4 = A: `volume` is ignored (AlarmKit has no volume; the preview plays at 1.0 like the real ring). `system`
  /// plays nothing (no public API for AlarmKit's default sound, Q5 = A). Nothing while an alarm rings (T16 AE11).
  func previewSound(soundId: String, volume: Double) throws {
    guard let file = AlarmSoundCatalog.fileName(soundId) else {
      preview.stop()
      return
    }
    if alarmAlerting() { return }
    preview.play(file: file, maxMs: constants.previewMaxMs)
    watchGeneration += 1
    watchAlarms(watchGeneration)
  }

  /// Review T17.2 nit #5: an alarm that starts ringing during the (≤ 10 s) preview stops the preview. Polls once a second
  /// on main while this preview plays; a newer preview or a stop ends the loop.
  private var watchGeneration = 0
  private func watchAlarms(_ generation: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
      guard let self, generation == self.watchGeneration, self.preview.isPlaying else { return }
      if self.alarmAlerting() {
        self.preview.stop()
        return
      }
      self.watchAlarms(generation)
    }
  }

  func stopPreview() throws {
    preview.stop()
  }

  /// D8: the launch action once; when none yet and a route-back intent is running, wait up to LAUNCH_ACTION_WAIT_MS.
  func consumeLaunchAction() async throws -> LaunchActionMsg? {
    let read = launchActions
    let inFlight = routeBackInFlight
    let sleep = self.sleep
    let waitMs = constants.launchActionWaitMs
    return try await CoreBridgeStub.guarded {
      let r = await LaunchActionWait.consume(
        waitMs: waitMs, pollMs: 100, inFlight: inFlight, read: read, sleep: sleep)
      return r.map { Self.msg($0) }
    }
  }

  static func msg(_ r: LaunchActionRec) -> LaunchActionMsg {
    LaunchActionMsg(kind: .overshootRoute, tripId: r.tripId, pastM: r.pastM.map(Int64.init))
  }

  /// D9: no native alarm screen on iOS.
  func showAlarmScreen(tripId: String) async throws -> Bool {
    false
  }

  /// UserDefaults key read by NativeCopy for AlarmKit / notification strings (T28 §6.3).
  static let appLocaleKey = "napstop.appLocale"

  /// T28: 'vi' | 'en' is stored; nil or any other value removes the key (= device language). Takes effect from the next
  /// alarm scheduled (AlarmKit cannot change a scheduled alarm, T17.2 D12).
  func setAppLocale(languageTag: String?) throws {
    let tag = languageTag?.trimmingCharacters(in: .whitespaces)
    if tag == "vi" || tag == "en" {
      UserDefaults.standard.set(tag, forKey: Self.appLocaleKey)
    } else {
      UserDefaults.standard.removeObject(forKey: Self.appLocaleKey)
    }
  }
}

/// [AV-PLAYER] + [AV-SESSION]: category `.playback` so the preview is heard with the Ring/Silent switch on, like the
/// alarm itself; the session is deactivated (notifying others) when the preview stops.
final class AVSoundPreview: SoundPreviewing {
  private static let logger = Logger(subsystem: "app.napstop", category: "preview")
  private let bundle: Bundle
  private(set) var player: AVAudioPlayer?
  private var stopItem: DispatchWorkItem?
  /// The session was activated by a preview and not yet given back (review T17.2 nit #4).
  private var sessionActive = false

  init(bundle: Bundle = .main) {
    self.bundle = bundle
  }

  var isPlaying: Bool { player?.isPlaying ?? false }

  func play(file: String, maxMs: Int64) {
    stop()
    let name = (file as NSString).deletingPathExtension
    let ext = (file as NSString).pathExtension
    guard let url = bundle.url(forResource: name, withExtension: ext) else {
      Self.logger.error("preview: sound file missing")
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
      sessionActive = true
      let p = try AVAudioPlayer(contentsOf: url)
      p.volume = 1.0
      p.numberOfLoops = 0  // the file is 28–29.5 s, longer than PREVIEW_MAX_MS
      p.prepareToPlay()
      p.play()
      player = p
      let item = DispatchWorkItem { [weak self] in self?.stop() }
      stopItem = item
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(maxMs)), execute: item)
    } catch {
      Self.logger.error("preview failed (\(String(describing: type(of: error)), privacy: .public))")
      stop()
    }
  }

  func stop() {
    stopItem?.cancel()
    stopItem = nil
    player?.stop()
    player = nil
    // Also when the player could not be created after the session was activated: give other apps' audio back.
    if sessionActive {
      sessionActive = false
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }
}
