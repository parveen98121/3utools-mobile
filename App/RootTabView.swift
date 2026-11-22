import SwiftUI
import SwiftData
import UIKit

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { DeviceHubView() }
                .tabItem { Label("Device", systemImage: "iphone") }

            NavigationStack { PhotosView() }
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }

            NavigationStack { LocationView() }
                .tabItem { Label("Location", systemImage: "mappin.and.ellipse") }

            NavigationStack { ToolboxView() }
                .tabItem { Label("Toolbox", systemImage: "wrench.and.screwdriver.fill") }
        }
        .tint(Theme.brandBlue)
        .onAppear(perform: recordBattery)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { recordBattery() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            recordBattery()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            recordBattery()
        }
    }

    /// Battery history only covers the times the app is open; this is where samples are taken.
    private func recordBattery() {
        BatteryRecorder.record(LiveBatteryService().current(), in: context)
    }
}
