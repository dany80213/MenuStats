import Darwin
import Foundation

struct ProcessUsage {
    var pid: pid_t
    var name: String
    /// Executable path; empty when the process is not ours to inspect.
    var path: String
    /// Fraction of one core, like Activity Monitor (can exceed 1 for multithreaded processes).
    var cpu: Double
    /// Physical footprint, the "Memory" column in Activity Monitor.
    var memory: UInt64
    var diskReadRate: Double
    var diskWriteRate: Double
    /// Watts, from the energy macOS counts for each process (CPU and GPU work it causes).
    var power: Double = 0
}

/// Per-process CPU, memory and disk I/O from proc_pid_rusage.
/// Without root this only covers the current user's processes; system daemons are skipped.
final class ProcessReader {
    private struct Counters {
        var cpuNanoseconds: UInt64
        var bytesRead: UInt64
        var bytesWritten: UInt64
        var energyNanojoules: UInt64
    }

    /// Screenshot runs (`--render-ui`) hide themselves: rendering is CPU-heavy and isn't what the app costs.
    static var hideOwnProcess = false

    private var previous: [pid_t: Counters] = [:]
    private var previousTime: Double?
    private var identities: [pid_t: (name: String, path: String)] = [:]
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    func sample() -> [ProcessUsage] {
        let now = uptimeSeconds()
        let elapsed = previousTime.map { now - $0 } ?? 0
        defer { previousTime = now }

        var current: [pid_t: Counters] = [:]
        var result: [ProcessUsage] = []
        let ownPID = getpid()
        for pid in allPIDs() where pid > 0 && !(Self.hideOwnProcess && pid == ownPID) {
            guard let usage = rusage(of: pid) else { continue }
            // rusage CPU times are in Mach absolute time units (not nanoseconds on Apple Silicon).
            let counters = Counters(
                cpuNanoseconds: (usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom,
                bytesRead: usage.ri_diskio_bytesread,
                bytesWritten: usage.ri_diskio_byteswritten,
                energyNanojoules: usage.ri_energy_nj
            )
            current[pid] = counters

            let identity = identity(of: pid)
            var process = ProcessUsage(pid: pid, name: identity.name, path: identity.path, cpu: 0, memory: usage.ri_phys_footprint,
                                       diskReadRate: 0, diskWriteRate: 0)
            if elapsed > 0, let old = previous[pid] {
                process.cpu = Double(counters.cpuNanoseconds &- old.cpuNanoseconds) / 1e9 / elapsed
                process.diskReadRate = Double(counters.bytesRead &- old.bytesRead) / elapsed
                process.diskWriteRate = Double(counters.bytesWritten &- old.bytesWritten) / elapsed
                process.power = Double(counters.energyNanojoules &- old.energyNanojoules) / 1e9 / elapsed
                // A reused PID shows up as counters going backwards.
                if counters.cpuNanoseconds < old.cpuNanoseconds { process.cpu = 0 }
                if counters.bytesRead < old.bytesRead { process.diskReadRate = 0 }
                if counters.bytesWritten < old.bytesWritten { process.diskWriteRate = 0 }
                if counters.energyNanojoules < old.energyNanojoules { process.power = 0 }
            }
            result.append(process)
        }

        previous = current
        identities = identities.filter { current[$0.key] != nil }
        return result
    }

    private func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return count > 0 ? Array(pids.prefix(Int(count))) : []
    }

    /// Version 6 (macOS 12+) adds the energy counter.
    private func rusage(of pid: pid_t) -> rusage_info_v6? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        return result == 0 ? info : nil
    }

    private func identity(of pid: pid_t) -> (name: String, path: String) {
        if let cached = identities[pid] { return cached }
        var name = "", path = ""
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            path = String(cString: buffer)
            name = (path as NSString).lastPathComponent
        }
        if name.isEmpty {
            var short = [CChar](repeating: 0, count: 256)
            proc_name(pid, &short, UInt32(short.count))
            name = String(cString: short)
        }
        if name.isEmpty { name = "PID \(pid)" }
        identities[pid] = (name, path)
        return (name, path)
    }
}

extension Array where Element == ProcessUsage {
    func top(_ count: Int, by key: (ProcessUsage) -> Double) -> [ProcessUsage] {
        filter { key($0) > 0 }.sorted { key($0) > key($1) }.prefix(count).map { $0 }
    }
}
