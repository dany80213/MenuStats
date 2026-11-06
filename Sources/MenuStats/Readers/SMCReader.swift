import CIOKitPrivate
import Foundation

struct FanInfo: Identifiable {
    var id: Int
    var rpm: Double
    var minimum: Double
    var maximum: Double

    var name: String { "Ventola \(id + 1)" }
    var fraction: Double { maximum > 0 ? min(max(rpm / maximum, 0), 1) : 0 }
}

struct SMCStats {
    var fans: [FanInfo]
    /// Total system power draw in watts (SMC key PSTR).
    var systemPower: Double?
    /// Power delivered by the charger in watts (PDTR); nil or 0 on battery.
    var adapterPower: Double?
    /// Per-core CPU temperatures (°C), in the chip's key order. Empty when the chip isn't in `SMCSensorMap`.
    var cpuCoreTemperatures: [Double] = []
    var gpuTemperatures: [Double] = []

    var cpuTemperature: Double? { cpuCoreTemperatures.isEmpty ? nil : cpuCoreTemperatures.reduce(0, +) / Double(cpuCoreTemperatures.count) }
    var cpuTemperatureMax: Double? { cpuCoreTemperatures.max() }
    var gpuTemperature: Double? { gpuTemperatures.isEmpty ? nil : gpuTemperatures.reduce(0, +) / Double(gpuTemperatures.count) }
}

/// SMC temperature keys per chip. "CPU" is the average of the per-core keys (verified on M3 Pro: these 11 keys
/// track the CPU cluster closely). The HID
/// "PMU tdie" sensors sit elsewhere on the die and read ~5–8 °C lower, so they are only a fallback.
enum SMCSensorMap {
    struct Keys {
        var cpuCores: [String]
        var gpu: [String]
    }

    static let byChip: [String: Keys] = [
        "Apple M3 Pro": Keys(
            cpuCores: ["Tp05", "Tp0D", "Tp0L", "Tp0S", "Tp0V", "Tp0b", "Tp0h", "Tp0n", "Tp0v", "Tp0z", "Tp17"],
            gpu: ["Tg01", "Tg05", "Tg0D", "Tg0L", "Tg0V", "Tg0v", "Tg13", "Tg1B", "Tg1l"]
        ),
        // MacBook Pro (Mac16,8). The per-core `Tp` keys sit at a 40 °C floor while a core idles, so the CPU figure uses
        // the `TfC*` die sensors instead, which follow the load (idle about 35 °C, load about 44 °C on this Mac).
        // GPU: the `Tg` sensors that track the GPU cluster (idle: 46-47 °C).
        "Apple M4 Pro": Keys(
            cpuCores: ["TfC0", "TfC1", "TfC2", "TfC3", "TfC4"],
            gpu: ["Tg05", "Tg0S", "Tg0Y", "Tg0k", "Tg0z", "Tg1V", "Tg1l"]
        ),
    ]

    static var current: Keys? { Sysctl.string("machdep.cpu.brand_string").flatMap { byChip[$0] } }
}

/// Fans and power from the SMC. Reading works without root; writing (fan control) would need a privileged helper.
final class SMCReader {
    private let connection = MSSMCOpen()
    private lazy var fanCount: Int = read("FNum").map { Int($0) } ?? 0
    /// The chip's table entry, or for chips not listed yet (e.g. M5) the `Tf??` die sensors found on this Mac.
    private lazy var sensorKeys = SMCSensorMap.current ?? discoverDieSensors()

    deinit { MSSMCClose(connection) }

    /// True when this chip's CPU temperature comes from SMC per-core keys (so the HID die sensors aren't needed).
    var hasCoreMap: Bool { !(sensorKeys?.cpuCores.isEmpty ?? true) }

    /// Groups of keys that can be refreshed at different rates. Each SMC read is a firmware round trip
    /// (~0.25 ms), so only what is on screen is read every sample; the rest refreshes slowly for history and alerts.
    enum Part: CaseIterable {
        case fans, power, cpuTemperatures, gpuTemperatures

        /// Refresh interval when nothing on screen shows this part.
        var slowInterval: Double {
            switch self {
            case .fans, .power, .cpuTemperatures: 10
            case .gpuTemperatures: 60
            }
        }
    }

    private var last = SMCStats(fans: [])
    private var lastRead: [Part: Double] = [:]
    /// Fan limits are fixed by the hardware: read once.
    private lazy var fanLimits: [(minimum: Double, maximum: Double)] = (0..<min(fanCount, 4)).map {
        (read("F\($0)Mn") ?? 0, read("F\($0)Mx") ?? 0)
    }

    /// `live` parts are read every call; the others when their slow interval has passed.
    func sample(live: Set<Part> = Set(Part.allCases)) -> SMCStats? {
        guard connection != 0 else { return nil }
        let now = uptimeSeconds()
        func due(_ part: Part) -> Bool {
            guard live.contains(part) || now - (lastRead[part] ?? -.infinity) >= part.slowInterval else { return false }
            lastRead[part] = now
            return true
        }
        // Discard unplugged/idle readings outside a plausible range.
        func temperatures(_ keys: [String]) -> [Double] { keys.compactMap(read).filter { $0 > 5 && $0 < 130 } }

        if due(.fans) {
            last.fans = fanLimits.enumerated().compactMap { index, limits in
                read("F\(index)Ac").map { FanInfo(id: index, rpm: $0, minimum: limits.minimum, maximum: limits.maximum) }
            }
        }
        if due(.power) {
            last.systemPower = read("PSTR")
            last.adapterPower = read("PDTR")
        }
        if due(.cpuTemperatures) { last.cpuCoreTemperatures = temperatures(sensorKeys?.cpuCores ?? []) }
        if due(.gpuTemperatures) { last.gpuTemperatures = temperatures(sensorKeys?.gpu ?? []) }
        return last
    }

    /// CPU temperature for chips missing from `SMCSensorMap`: every `Tf??` key that reads a float in a believable
    /// range. Nil (so the HID fallback applies) when the Mac has none. GPU stays on the HID fallback.
    private func discoverDieSensors() -> SMCSensorMap.Keys? {
        guard connection != 0 else { return nil }
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let keys = characters.flatMap { first in characters.map { "Tf\(first)\($0)" } }.filter { key in
            var value = MSSMCValue()
            guard MSSMCRead(connection, key, &value) == 0, fourCC(value.dataType) == "flt ",
                  let degrees = read(key) else { return false }
            return degrees > 20 && degrees < 120
        }
        return keys.isEmpty ? nil : SMCSensorMap.Keys(cpuCores: keys, gpu: [])
    }

    /// Key metadata (size, type) never changes: cache it so each later read is one kernel call instead of two.
    private var keyInfo: [String: (size: UInt32, type: UInt32)] = [:]
    private var missingKeys: Set<String> = []

    /// Reads a key and decodes the common numeric SMC types.
    private func read(_ key: String) -> Double? {
        guard !missingKeys.contains(key) else { return nil }
        if keyInfo[key] == nil {
            var size: UInt32 = 0, type: UInt32 = 0
            guard MSSMCKeyInfo(connection, key, &size, &type) == 0 else { missingKeys.insert(key); return nil }
            keyInfo[key] = (size, type)
        }
        guard let info = keyInfo[key] else { return nil }
        var value = MSSMCValue()
        guard MSSMCReadKnown(connection, key, info.size, info.type, &value) == 0 else { return nil }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(value.dataSize))) }
        guard !bytes.isEmpty else { return nil }

        switch fourCC(value.dataType) {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
        case "ui8 ", "si8 ":
            return Double(bytes[0])
        case "ui16":
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            return Double(bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        case "fpe2":
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    private func fourCC(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .ascii) ?? ""
    }
}

/// What this Mac physically has, so the app can hide modules for missing hardware (fanless MacBook Air, desktops).
enum HardwarePresence {
    /// Fan count from the SMC (`FNum`); fanless Macs report 0 or, like the MacBook Air, don't expose the key at all.
    /// When `FNum` can't be read, the first fan's limits (`F0Mx`) decide; the model name is the last resort.
    static let hasFans: Bool = {
        let connection = MSSMCOpen()
        guard connection != 0 else { return !isMacBookAir }
        defer { MSSMCClose(connection) }
        var value = MSSMCValue()
        if MSSMCRead(connection, "FNum", &value) == 0, value.dataSize > 0 { return value.bytes.0 > 0 }
        var limit = MSSMCValue()
        if MSSMCRead(connection, "F0Mx", &limit) == 0, limit.dataSize > 0 { return true }
        return false
    }()

    private static var isMacBookAir: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { if service != 0 { IOObjectRelease(service) } }
        guard service != 0, let data = IORegistryEntryCreateCFProperty(service, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return false }
        return String(decoding: data, as: UTF8.self).contains("MacBook Air")
    }

    static let hasBattery: Bool = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { if service != 0 { IOObjectRelease(service) } }
        return service != 0
    }()
}
