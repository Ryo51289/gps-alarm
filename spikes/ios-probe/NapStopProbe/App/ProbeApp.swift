import SwiftUI

@main
struct ProbeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            RunController.shared.scenePhaseChanged(Self.name(newPhase))
        }
    }

    private static func name(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}
