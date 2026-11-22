import Foundation
import Network
import Observation

struct NetworkStatus: Equatable {
    var isConnected: Bool
    var interface: String
    var isExpensive: Bool
    var isConstrained: Bool
    var supportsIPv4: Bool
    var supportsIPv6: Bool

    static let unknown = NetworkStatus(isConnected: false, interface: "Unknown", isExpensive: false,
                                       isConstrained: false, supportsIPv4: false, supportsIPv6: false)

    init(isConnected: Bool, interface: String, isExpensive: Bool, isConstrained: Bool, supportsIPv4: Bool, supportsIPv6: Bool) {
        self.isConnected = isConnected
        self.interface = interface
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.supportsIPv4 = supportsIPv4
        self.supportsIPv6 = supportsIPv6
    }

    init(path: NWPath) {
        isConnected = path.status == .satisfied
        if path.usesInterfaceType(.wifi) {
            interface = "Wi-Fi"
        } else if path.usesInterfaceType(.cellular) {
            interface = "Mobile data"
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = "Ethernet"
        } else if path.status == .satisfied {
            interface = "Other"
        } else {
            interface = "None"
        }
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        supportsIPv4 = path.supportsIPv4
        supportsIPv6 = path.supportsIPv6
    }
}

/// Live view of the phone's network path.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var status = NetworkStatus.unknown

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = NetworkStatus(path: path)
            DispatchQueue.main.async { self?.status = status }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }

    /// The path right now, without waiting for the next update.
    var current: NetworkStatus { NetworkStatus(path: monitor.currentPath) }
}

enum NetworkTools {
    /// IPv4 addresses by interface name. "en0" is Wi-Fi and "pdp_ip0" is mobile data on iPhone.
    static func localAddresses() -> [String: String] {
        var result: [String: String] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return result }
        defer { freeifaddrs(pointer) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(address, socklen_t(address.pointee.sa_len),
                                     &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            if status == 0 {
                result[String(cString: interface.ifa_name)] = String(cString: host)
            }
        }
        return result
    }

    static func wifiAddress() -> String? { localAddresses()["en0"] }
    static func cellularAddress() -> String? { localAddresses()["pdp_ip0"] }

    /// Time to resolve a host name, in seconds. Nil when the lookup fails.
    static func dnsLookupTime(host: String) async -> TimeInterval? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_socktype = SOCK_STREAM
                var info: UnsafeMutablePointer<addrinfo>?
                let start = Date()
                let status = getaddrinfo(host, nil, &hints, &info)
                let elapsed = Date().timeIntervalSince(start)
                if info != nil { freeaddrinfo(info) }
                continuation.resume(returning: status == 0 ? elapsed : nil)
            }
        }
    }

    /// Time for one HTTPS request to complete, in seconds.
    static func httpsRoundTrip(host: String, timeout: TimeInterval = 10) async throws -> TimeInterval {
        guard let url = URL(string: "https://\(host)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        let start = Date()
        _ = try await URLSession.shared.data(for: request)
        return Date().timeIntervalSince(start)
    }
}
