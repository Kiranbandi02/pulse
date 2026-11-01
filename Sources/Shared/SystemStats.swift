import Foundation
import Darwin
import IOKit
import IOKit.ps

// MARK: - Models (read-only snapshots of system state)

struct CPUUsage {
    var user = 0.0      // percent of total capacity
    var system = 0.0
    var idle = 100.0
    var perCore: [Double] = []
    var busy: Double { min(100, max(0, user + system)) }
}

enum MemoryPressure: Int {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: return "Healthy"
        case .warning: return "Getting tight"
        case .critical: return "Very low"
        }
    }
}

struct MemoryUsage {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: MemoryPressure = .normal

    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

struct NetworkUsage {
    var downBps = 0.0
    var upBps = 0.0
    var totalIn: UInt64 = 0     // since boot
    var totalOut: UInt64 = 0
    var interfaces: [String] = []
}

struct DiskUsage {
    var total: UInt64 = 0
    var free: UInt64 = 0
    var readBps = 0.0
    var writeBps = 0.0
    var used: UInt64 { total > free ? total - free : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct BatteryStatus {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
    var minutesRemaining: Int?
}

struct SystemSnapshot {
    var date = Date()
    var cpu = CPUUsage()
    var memory = MemoryUsage()
    var network = NetworkUsage()
    var disk = DiskUsage()
    var battery: BatteryStatus?
    var loadAverage: (Double, Double, Double) = (0, 0, 0)
    var thermal: ProcessInfo.ThermalState = .nominal
    var uptime: TimeInterval = 0
    var coreCount = ProcessInfo.processInfo.activeProcessorCount

    static let empty = SystemSnapshot()
}

// MARK: - Sampler

/// Reads system-wide statistics. Not thread-safe: use one instance from one queue.
final class SystemSampler {
    private var prevTicks: [[UInt32]] = []
    private var prevNet: (inB: UInt64, outB: UInt64, t: TimeInterval)?
    private var prevDisk: (r: UInt64, w: UInt64, t: TimeInterval)?

    func sample() -> SystemSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        var snap = SystemSnapshot()
        snap.date = Date()
        snap.uptime = now
        snap.cpu = readCPU()
        snap.memory = Self.readMemory()
        snap.disk = readDisk(now: now)
        snap.network = readNetwork(now: now)
        snap.battery = Self.readBattery()
        var l = [Double](repeating: 0, count: 3)
        getloadavg(&l, 3)
        snap.loadAverage = (l[0], l[1], l[2])
        snap.thermal = ProcessInfo.processInfo.thermalState
        return snap
    }

    // MARK: CPU

    private func readCPU() -> CPUUsage {
        let ticks = Self.readTicks()
        defer { prevTicks = ticks }
        guard !ticks.isEmpty else { return CPUUsage() }
        var tu = 0.0, ts = 0.0, ti = 0.0
        var per: [Double] = []
        for (i, c) in ticks.enumerated() {
            let p = i < prevTicks.count ? prevTicks[i] : [0, 0, 0, 0]
            let u = Double(c[0] &- p[0]), s = Double(c[1] &- p[1])
            let id = Double(c[2] &- p[2]), n = Double(c[3] &- p[3])
            let tot = u + s + id + n
            per.append(tot > 0 ? (u + s + n) / tot * 100 : 0)
            tu += u + n; ts += s; ti += id
        }
        var cpu = CPUUsage()
        let all = tu + ts + ti
        if all > 0 {
            cpu.user = tu / all * 100
            cpu.system = ts / all * 100
            cpu.idle = ti / all * 100
        }
        cpu.perCore = per
        return cpu
    }

    private static func readTicks() -> [[UInt32]] {
        var numCPU: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var out: [[UInt32]] = []
        for i in 0..<Int(numCPU) {
            let b = Int(CPU_STATE_MAX) * i
            out.append([
                UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)]),
            ])
        }
        return out
    }

    // MARK: Memory

    static func readMemory() -> MemoryUsage {
        var m = MemoryUsage()
        m.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            m.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            m.wired = UInt64(stats.wire_count) * page
            m.compressed = UInt64(stats.compressor_page_count) * page
            m.cached = (UInt64(stats.external_page_count) + purgeable) * page
            m.free = UInt64(stats.free_count) * page
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            m.swapUsed = swap.xsu_used
            m.swapTotal = swap.xsu_total
        }

        var level: Int32 = 1
        var lsize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsize, nil, 0) == 0 {
            m.pressure = MemoryPressure(rawValue: Int(level)) ?? .normal
        }
        return m
    }

    // MARK: Network

    private func readNetwork(now: TimeInterval) -> NetworkUsage {
        let c = Self.readNetworkCounters()
        var n = NetworkUsage()
        n.totalIn = c.inBytes
        n.totalOut = c.outBytes
        n.interfaces = c.interfaces
        if let p = prevNet, now > p.t {
            let dt = now - p.t
            n.downBps = c.inBytes >= p.inB ? Double(c.inBytes - p.inB) / dt : 0
            n.upBps = c.outBytes >= p.outB ? Double(c.outBytes - p.outB) / dt : 0
        }
        prevNet = (c.inBytes, c.outBytes, now)
        return n
    }

    /// 64-bit per-interface byte counters via the routing socket (getifaddrs only has 32-bit counters).
    private static func readNetworkCounters() -> (inBytes: UInt64, outBytes: UInt64, interfaces: [String]) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return (0, 0, []) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return (0, 0, []) }

        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        var names: [String] = []
        buf.withUnsafeBytes { raw in
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
                let msgLen = Int(hdr.ifm_msglen)
                if msgLen <= 0 { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, off + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(h2.ifm_index), &nameBuf) != nil {
                        let name = String(cString: nameBuf)
                        let up = (Int32(h2.ifm_flags) & IFF_UP) != 0
                        // Physical links only: Wi-Fi / Ethernet / tethering are enN. Skips lo0, VPN tunnels, bridges.
                        if up, name.hasPrefix("en") {
                            totalIn += h2.ifm_data.ifi_ibytes
                            totalOut += h2.ifm_data.ifi_obytes
                            names.append(name)
                        }
                    }
                }
                off += msgLen
            }
        }
        return (totalIn, totalOut, names)
    }

    // MARK: Disk

    private func readDisk(now: TimeInterval) -> DiskUsage {
        var d = DiskUsage()
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            d.total = UInt64(v.volumeTotalCapacity ?? 0)
            d.free = UInt64(max(0, v.volumeAvailableCapacityForImportantUsage ?? 0))
        }
        let io = Self.readDiskCounters()
        if let p = prevDisk, now > p.t {
            let dt = now - p.t
            d.readBps = io.read >= p.r ? Double(io.read - p.r) / dt : 0
            d.writeBps = io.write >= p.w ? Double(io.write - p.w) / dt : 0
        }
        prevDisk = (io.read, io.write, now)
        return d
    }

    private static func readDiskCounters() -> (read: UInt64, write: UInt64) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iter) }
        var r: UInt64 = 0, w: UInt64 = 0
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let props = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                r += (props["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                w += (props["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return (r, w)
    }

    // MARK: Battery

    static func readBattery() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d["Type"] as? String) == "InternalBattery" else { continue }
            let cur = d["Current Capacity"] as? Int ?? 0
            let max = d["Max Capacity"] as? Int ?? 100
            let charging = d["Is Charging"] as? Bool ?? false
            let onAC = (d["Power Source State"] as? String) == "AC Power"
            var mins: Int?
            if let t = d[charging ? "Time to Full Charge" : "Time to Empty"] as? Int, t > 0 { mins = t }
            return BatteryStatus(percent: max > 0 ? cur * 100 / max : cur, isCharging: charging, onAC: onAC, minutesRemaining: mins)
        }
        return nil
    }
}

// MARK: - Formatting

enum Fmt {
    /// Binary units, like Activity Monitor uses for memory.
    static func memory(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB, .useTB]
        f.zeroPadsFractionDigits = false
        return f.string(fromByteCount: Int64(bytes))
    }

    /// Decimal units, like Finder uses for disk space.
    static func storage(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    static func speed(_ bytesPerSec: Double, bits: Bool = false) -> String {
        let v = bits ? bytesPerSec * 8 : bytesPerSec
        let units = bits ? ["bps", "Kbps", "Mbps", "Gbps"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var x = v
        var i = 0
        while x >= 1000 && i < units.count - 1 { x /= 1000; i += 1 }
        if i == 0 { return "\(Int(x)) \(units[0])" }
        let digits = x >= 100 ? 0 : (x >= 10 ? 1 : 2)
        return "\(String(format: "%.\(digits)f", x)) \(units[i])"
    }

    static func percent(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
