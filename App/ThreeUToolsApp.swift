import SwiftUI
import SwiftData

@main
struct ThreeUToolsApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [
            BatterySample.self,
            SavedLocation.self,
            SpeedTestResult.self,
            RecentFile.self
        ])
    }
}
