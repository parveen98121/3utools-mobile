import SwiftUI

struct DiagnosticsView: View {
    @State private var model = DiagnosticsViewModel()
    @State private var microphoneMessage: String?

    var body: some View {
        List {
            Section {
                summary
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            ForEach(DiagnosticCheck.Category.allCases, id: \.self) { category in
                let items = model.checks(in: category)
                if !items.isEmpty {
                    Section(category.rawValue) {
                        ForEach(items) { check in
                            row(check)
                        }
                        if category == .permissions, PermissionService.microphone() == .notDetermined {
                            Button("Ask for microphone access now") {
                                Task {
                                    _ = await PermissionService.requestMicrophone()
                                    model.run()
                                }
                            }
                        }
                    }
                }
            }

            Section {
                RestrictedFeatureView(
                    title: "What this screen cannot do",
                    message: "iOS does not let apps test the screen, speakers, buttons or sensors, or read battery health. The hardware rows above only show whether iOS reports each part as present."
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { model.run() }
                } label: {
                    Label("Run again", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { model.run() }
    }

    private var summary: some View {
        let counts = model.summary
        return HStack(spacing: 12) {
            StatTile(title: "Passed", value: "\(counts.passed)", systemImage: "checkmark.circle.fill", tint: Theme.passed)
            StatTile(title: "Warnings", value: "\(counts.warnings)", systemImage: "exclamationmark.triangle.fill", tint: Theme.warning)
            StatTile(title: "Not available", value: "\(counts.notAvailable)", systemImage: "minus.circle.fill", tint: Theme.unavailable)
        }
    }

    private func row(_ check: DiagnosticCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.systemImage)
                .frame(width: 28)
                .foregroundStyle(Theme.gradient)
            VStack(alignment: .leading, spacing: 4) {
                Text(check.title)
                Text(check.result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusBadge(status: check.result.status)
        }
        .padding(.vertical, 2)
    }
}
