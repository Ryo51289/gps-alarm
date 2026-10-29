import AlarmKit
import Foundation

/// Metadata attached to every AlarmKit alarm of the probe. `kind`: now | prearm | test.
struct ProbeAlarmMetadata: AlarmMetadata {
    var runId: String
    var kind: String
}
