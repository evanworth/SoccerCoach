import SwiftUI

@main
struct SoccerCoachApp: App {
    @StateObject private var store = SoccerCoachStore()
    @StateObject private var accessController = AccessController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(accessController)
        }
    }
}
