#if canImport(ActivityKit)
  import ActivityKit

  /// Spike T23.6-B0 only (docs/spikes/T23.6.md): the smallest ActivityAttributes shared by Runner (DiagLiveActivityIntent)
  /// and the NapStopLiveActivity extension, so that H3 can be checked on the iPhone. Compiled into both targets.
  /// B1 replaces it with NapStopTripAttributes in the LiveTrip package target (docs/specs/T23.6.md §5.2).
  /// No coordinates, no trip data: a fixed title and a label.
  @available(iOS 16.1, *)
  struct NapStopB0Attributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
      var label: String
    }

    var title: String
  }
#endif
