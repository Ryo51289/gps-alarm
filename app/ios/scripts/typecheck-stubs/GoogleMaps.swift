// typecheck-only stub, never linked. Used by app/ios/scripts/typecheck-wsl.sh (docs/specs/T01.2.md §8) because the WSL
// toolchain has no GoogleMaps SDK. Declares only what Runner uses; when Runner calls more GoogleMaps API, add it here.
// The real SDK comes from the Swift package of google_maps_flutter on the CI build.

public enum GMSServices {
  @discardableResult
  public static func provideAPIKey(_ key: String) -> Bool { true }
}
