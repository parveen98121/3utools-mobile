import SwiftUI
import SwiftData
import Charts
import Observation

/// Measures transfer speed against Cloudflare's public speed-test endpoints.
/// The delegate queue is the main queue, so all state here is touched on the main thread.
final class SpeedTestService: NSObject, URLSessionDataDelegate {
    enum Failure: LocalizedError {
        case noData
        var errorDescription: String? { "No data was transferred before the connection ended." }
    }

    private var session: URLSession?
    private var continuation: CheckedContinuation<Double, Error>?
    private var progress: ((Double) -> Void)?
    private var bytes: Int64 = 0
    private var started = Date()

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }

    private var currentSpeed: Double {
        SpeedMath.megabitsPerSecond(bytes: bytes, seconds: Date().timeIntervalSince(started))
    }

    /// Time for a tiny request to complete, in seconds.
    func latency() async throws -> TimeInterval {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        // The first request includes connection setup, so measure the second one.
        _ = try await URLSession.shared.data(for: request)
        let start = Date()
        _ = try await URLSession.shared.data(for: request)
        return Date().timeIntervalSince(start)
    }

    func download(byteCount: Int = 25_000_000, progress: @escaping (Double) -> Void) async throws -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(byteCount)") else { throw URLError(.badURL) }
        return try await run(progress: progress) { session in
            session.dataTask(with: url)
        }
    }

    func upload(byteCount: Int = 8_000_000, progress: @escaping (Double) -> Void) async throws -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(count: byteCount)
        return try await run(progress: progress) { session in
            session.uploadTask(with: request, from: payload)
        }
    }

    private func run(progress: @escaping (Double) -> Void,
                     makeTask: (URLSession) -> URLSessionTask) async throws -> Double {
        let session = makeSession()
        self.session = session
        self.progress = progress
        bytes = 0
        started = Date()
        let task = makeTask(session)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task.resume()
        }
    }

    // Download progress.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // An upload task also receives a small response body; that is not download data.
        if dataTask is URLSessionUploadTask { return }
        bytes += Int64(data.count)
        progress?(currentSpeed)
    }

    // Upload progress.
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        bytes = totalBytesSent
        progress?(currentSpeed)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let speed = currentSpeed
        let pending = continuation
        continuation = nil
        progress = nil
        session.finishTasksAndInvalidate()
        self.session = nil

        // A timeout after data has flowed still gives a valid measurement of the rate so far.
        if bytes > 0 {
            pending?.resume(returning: speed)
        } else {
            pending?.resume(throwing: error ?? Failure.noData)
        }
    }
}

@MainActor
@Observable
final class SpeedTestViewModel {
    enum Phase: String {
        case idle = "Ready"
        case latency = "Measuring response time"
        case download = "Testing download"
        case upload = "Testing upload"
        case finished = "Finished"
        case failed = "Failed"
    }

    private(set) var phase: Phase = .idle
    private(set) var liveSpeed: Double = 0
    private(set) var latency: TimeInterval?
    private(set) var download: Double?
    private(set) var upload: Double?
    private(set) var errorMessage: String?

    private let service = SpeedTestService()

    var isRunning: Bool { phase == .latency || phase == .download || phase == .upload }

    /// Runs the three measurements and returns a result to store, or nil if the test failed.
    func run() async -> SpeedTestResult? {
        guard !isRunning else { return nil }
        latency = nil
        download = nil
        upload = nil
        errorMessage = nil
        liveSpeed = 0

        guard NetworkMonitor.shared.current.isConnected else {
            phase = .failed
            errorMessage = "The phone is not connected to the internet."
            return nil
        }

        do {
            phase = .latency
            let latencyValue = try await service.latency()
            latency = latencyValue

            phase = .download
            let downloadValue = try await service.download { [weak self] speed in self?.liveSpeed = speed }
            download = downloadValue

            phase = .upload
            liveSpeed = 0
            let uploadValue = try await service.upload { [weak self] speed in self?.liveSpeed = speed }
            upload = uploadValue

            liveSpeed = 0
            phase = .finished
            return SpeedTestResult(downloadMbps: downloadValue, uploadMbps: uploadValue,
                                   latencySeconds: latencyValue,
                                   connection: NetworkMonitor.shared.current.interface)
        } catch {
            phase = .failed
            liveSpeed = 0
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

struct SpeedTestView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SpeedTestResult.date, order: .reverse) private var history: [SpeedTestResult]
    @State private var model = SpeedTestViewModel()

    private var gaugeValue: Double {
        model.isRunning ? model.liveSpeed : (model.download ?? 0)
    }

    /// The ring fills on a logarithmic scale so both 5 Mbps and 500 Mbps are readable.
    private var gaugeProgress: Double {
        guard gaugeValue > 0 else { return 0 }
        return min(log10(gaugeValue + 1) / 3, 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(spacing: 16) {
                    RingGauge(progress: gaugeProgress, lineWidth: 16) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", gaugeValue))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                            Text("Mbps").font(.subheadline).foregroundStyle(.secondary)
                            Text(model.phase.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 210, height: 210)
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        StatTile(title: "Download", value: model.download.map(Format.speed) ?? "–", systemImage: "arrow.down.circle.fill")
                        StatTile(title: "Upload", value: model.upload.map(Format.speed) ?? "–", systemImage: "arrow.up.circle.fill", tint: Theme.brandPurple)
                        StatTile(title: "Response", value: model.latency.map(Format.milliseconds) ?? "–", systemImage: "timer", tint: .teal)
                    }

                    if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }

                    Button(model.isRunning ? "Testing…" : "Start test") {
                        Task {
                            if let result = await model.run() {
                                context.insert(result)
                            }
                        }
                    }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(model.isRunning)
                }
                .cardStyle()

                HStack(alignment: .top) {
                    SourceBadge(source: .estimated)
                    Text("An estimate from one short transfer of about 25 MB down and 8 MB up, which counts against a mobile data allowance. The test contacts Cloudflare's speed-test servers, which see the phone's IP address like any website does.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                historyCard
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Speed test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var historyCard: some View {
        InfoCard(title: "Previous results", systemImage: "clock.arrow.circlepath") {
            if history.isEmpty {
                Text("Results appear here after the first test.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if history.count > 1 {
                    Chart(history.prefix(20).reversed(), id: \.date) { result in
                        BarMark(x: .value("Date", result.date, unit: .minute), y: .value("Mbps", result.downloadMbps))
                            .foregroundStyle(Theme.gradient)
                            .cornerRadius(4)
                    }
                    .frame(height: 140)
                }
                ForEach(history.prefix(10)) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.date, format: .dateTime.day().month().hour().minute())
                                .font(.subheadline.weight(.medium))
                            Text(result.connection).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("↓ \(Format.speed(result.downloadMbps))")
                            Text("↑ \(Format.speed(result.uploadMbps))").foregroundStyle(.secondary)
                        }
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                    }
                }
                Button("Clear results", role: .destructive) {
                    for result in history { context.delete(result) }
                }
                .font(.footnote)
            }
        }
    }
}
