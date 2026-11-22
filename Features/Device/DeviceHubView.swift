import SwiftUI

struct DeviceHubView: View {
    var body: some View {
        List {
            Section {
                hubLink("Device information", "Model, software, hardware and network details", "info.circle.fill") {
                    DeviceInfoView()
                }
                hubLink("Battery", "Level, charging state and recorded history", "battery.75percent") {
                    BatteryView()
                }
                hubLink("Storage", "Used and free space, photos and recommendations", "internaldrive.fill") {
                    StorageView()
                }
                hubLink("Apps", "Known apps found on this phone", "square.grid.2x2.fill") {
                    AppsView()
                }
            }
        }
        .navigationTitle("Device")
    }

    private func hubLink<Destination: View>(_ title: String, _ subtitle: String, _ image: String,
                                            @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: image)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
