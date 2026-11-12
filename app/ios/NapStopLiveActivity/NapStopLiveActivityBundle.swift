import ActivityKit
import SwiftUI
import WidgetKit

/// NapStop widget extension (docs/specs/T23.6.md §5.8). Spike B0: one static Live Activity for NapStopB0Attributes, no
/// home screen widget, no entitlements, no UserDefaults, no network, no location. B3 replaces the views.
@main
struct NapStopLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    B0LiveActivity()
  }
}

/// White on black: contrast 21:1.
struct B0LiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: NapStopB0Attributes.self) { context in
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.title).font(.headline)
        Text(context.state.label).font(.subheadline)
      }
      .foregroundStyle(Color.white)
      .padding()
      .activityBackgroundTint(Color.black)
      .activitySystemActionForegroundColor(Color.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.center) {
          Text(context.attributes.title).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.label).lineLimit(1)
        }
      } compactLeading: {
        Image(systemName: "moon.zzz.fill").accessibilityHidden(true)
      } compactTrailing: {
        Text(verbatim: "B0").monospacedDigit()
      } minimal: {
        Image(systemName: "moon.zzz.fill").accessibilityHidden(true)
      }
    }
  }
}
