import Combine
import Darwin
import Foundation

/// An active VPN (or other tunnel) on this Mac, found locally: no network request.
struct VPNStatus: Equatable {
    var interface: String
    /// The tunnel's own address (the VPN IP).
    var address: String
    /// The connection's name from System Settings ▸ VPN, when macOS lists it.
    var name: String?
    /// True when the default route goes through the tunnel (all traffic uses the VPN).
    var fullTunnel: Bool
}

enum VPNDetector {
    private static let tunnelPrefixes = ["utun", "ppp", "ipsec", "tun", "tap", "wg"]

    static func isTunnel(_ name: String) -> Bool { tunnelPrefixes.contains { name.hasPrefix($0) } }

    /// Tunnel interfaces that are up and have a routable IPv4 address (the `utun`s macOS keeps for its own
    /// services only carry IPv6 link-local addresses, so they don't count).
    static func detect(defaultInterface: String?, names: [String]) -> VPNStatus? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var found: [(String, String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            guard isTunnel(name), flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let text = String(cString: host)
            if text.hasPrefix("169.254.") || text.hasPrefix("127.") { continue }
            found.append((name, text))
        }
        guard let pick = found.first(where: { $0.0 == defaultInterface }) ?? found.first else { return nil }
        return VPNStatus(interface: pick.0, address: pick.1, name: names.first, fullTunnel: pick.0 == defaultInterface)
    }

    /// Names of the VPN connections macOS reports as connected (`scutil --nc list`).
    static func connectedNames() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--nc", "list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            guard line.contains("(Connected)"), let open = line.firstIndex(of: "\""),
                  let close = line[line.index(after: open)...].firstIndex(of: "\"") else { return nil }
            return String(line[line.index(after: open)..<close])
        }
    }
}

struct PublicIP: Equatable {
    var address: String
    var country: String?
    var countryCode: String?
    var provider: String?

    /// The country flag as an emoji (regional indicator letters).
    var flag: String? {
        guard let code = countryCode?.uppercased(), code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return String(code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }.map(Character.init))
    }
}

/// The Network tab's "public IP and VPN" data. The VPN part is local. The public IP comes from ipwho.is (free, no
/// account), only when the user turned it on, only while the Network tab is open, at most every 5 minutes or when the
/// connection or VPN changes.
final class PublicNetworkService: ObservableObject {
    @Published private(set) var vpn: VPNStatus?
    @Published private(set) var publicIP: PublicIP?
    @Published private(set) var error: String?
    @Published private(set) var loading = false

    private var vpnNames: [String] = []
    private var lastNamesCheck = Date.distantPast
    private var lastFetch = Date.distantPast
    private var lastSignature = ""
    private var task: URLSessionDataTask?
    private static let staleAfter: TimeInterval = 5 * 60

    /// Called every few seconds while the Network tab is visible.
    func update(defaultInterface: String?, localAddress: String?, publicIPEnabled: Bool, vpnEnabled: Bool) {
        if vpnEnabled {
            if Date().timeIntervalSince(lastNamesCheck) > 30 {
                lastNamesCheck = Date()
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let names = VPNDetector.connectedNames()
                    DispatchQueue.main.async { self?.vpnNames = names }
                }
            }
        }
        let status = (vpnEnabled || publicIPEnabled) ? VPNDetector.detect(defaultInterface: defaultInterface, names: vpnNames) : nil
        if status != vpn { vpn = vpnEnabled ? status : nil }

        guard publicIPEnabled else {
            if publicIP != nil || error != nil { publicIP = nil; error = nil }
            task?.cancel()
            return
        }
        let signature = [defaultInterface ?? "", localAddress ?? "", status?.interface ?? "", status?.address ?? ""].joined(separator: "|")
        if signature != lastSignature || Date().timeIntervalSince(lastFetch) > Self.staleAfter {
            lastSignature = signature
            fetch()
        }
    }

    func fetch() {
        lastFetch = Date()
        var components = URLComponents(string: "https://ipwho.is/")!
        components.queryItems = [.init(name: "fields", value: "ip,success,country,country_code,connection")]
        task?.cancel()
        loading = true
        task = URLSession.shared.dataTask(with: components.url!) { [weak self] data, _, error in
            let parsed = data.flatMap(Self.parse)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                if let parsed {
                    self.publicIP = parsed
                    self.error = nil
                } else if (error as? URLError)?.code != .cancelled {
                    self.error = "IP pubblico non disponibile"
                }
            }
        }
        task?.resume()
    }

    private static func parse(_ data: Data) -> PublicIP? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["success"] as? Bool != false, let ip = root["ip"] as? String else { return nil }
        let connection = root["connection"] as? [String: Any]
        return PublicIP(address: ip, country: root["country"] as? String, countryCode: root["country_code"] as? String,
                        provider: (connection?["isp"] as? String) ?? (connection?["org"] as? String))
    }
}
