import SwiftUI

@main
struct SoccerCoachApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SoccerCoachStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.preferredColorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            store.handleScenePhaseChange(newPhase)
        }
    }
}
