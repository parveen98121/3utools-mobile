import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

struct FileDetails: Equatable {
    var name: String
    var size: Int64?
    var type: String?
    var modified: Date?
}

/// Opens files chosen with Apple's document picker. Access to each file is granted by the user's choice.
enum FileAccess {
    enum Failure: LocalizedError {
        case noAccess
        case stale
        var errorDescription: String? {
            switch self {
            case .noAccess: return "iOS did not grant access to this file."
            case .stale: return "This file has moved or been deleted. Pick it again."
            }
        }
    }

    /// Copies the picked file into the app's temporary folder so it can be previewed,
    /// and returns the copy together with the file's details.
    static func importCopy(of url: URL) throws -> (copy: URL, details: FileDetails, bookmark: Data?) {
        guard url.startAccessingSecurityScopedResource() else { throw Failure.noAccess }
        defer { url.stopAccessingSecurityScopedResource() }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .contentModificationDateKey])
        let details = FileDetails(name: url.lastPathComponent,
                                  size: values?.fileSize.map { Int64($0) },
                                  type: values?.contentType?.localizedDescription,
                                  modified: values?.contentModificationDate)
        let bookmark = try? url.bookmarkData()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Previews", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: url, to: copy)
        return (copy, details, bookmark)
    }

    static func resolve(_ bookmark: Data) throws -> URL {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else {
            throw Failure.stale
        }
        return url
    }
}

struct FilesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecentFile.date, order: .reverse) private var recents: [RecentFile]

    @State private var showPicker = false
    @State private var previewURL: URL?
    @State private var details: FileDetails?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label("Open a file", systemImage: "folder.badge.plus")
                }
            } footer: {
                Text("Uses Apple's file picker, so you can open anything from Files, iCloud Drive or other storage apps. This app only sees the files you choose.")
            }

            if let details {
                Section("Last opened") {
                    InfoRow("Name", details.name)
                    InfoRow("Size", details.size.map(Format.bytes))
                    InfoRow("Type", details.type)
                    InfoRow("Modified", details.modified?.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("Recent files") {
                if recents.isEmpty {
                    Text("Files you open are listed here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recents) { recent in
                        Button {
                            reopen(recent)
                        } label: {
                            HStack {
                                Image(systemName: "doc.fill").foregroundStyle(Theme.gradient)
                                VStack(alignment: .leading) {
                                    Text(recent.name).foregroundStyle(.primary)
                                    Text(recent.date, format: .dateTime.day().month().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(recents[index]) }
                    }
                }
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { open(url, remember: true) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .quickLookPreview($previewURL)
        .alert("Could not open the file", isPresented: Binding(get: { errorMessage != nil },
                                                               set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func open(_ url: URL, remember: Bool) {
        do {
            let imported = try FileAccess.importCopy(of: url)
            details = imported.details
            previewURL = imported.copy
            if remember, let bookmark = imported.bookmark {
                for old in recents where old.name == imported.details.name { context.delete(old) }
                context.insert(RecentFile(name: imported.details.name, bookmark: bookmark))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reopen(_ recent: RecentFile) {
        do {
            let url = try FileAccess.resolve(recent.bookmark)
            recent.date = Date()
            open(url, remember: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
