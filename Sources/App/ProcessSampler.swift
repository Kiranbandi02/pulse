import Foundation
import Darwin

/// One process as read from the kernel. Purely observational.
struct RawProcess {
    let pid: Int32
    let ppid: Int32
    let uid: UInt32
    let name: String
    let path: String
    let cpu: Double          // percent of one core (can exceed 100)
    let memory: UInt64       // physical footprint, same figure Activity Monitor shows
    let diskReadBps: Double
    let diskWriteBps: Double
}

final class ProcessSampler {
    private struct Static { let startTime: UInt64; let ppid: Int32; let uid: UInt32; let name: String; let path: String }

    private var prev: [Int32: (cpu: UInt64, read: UInt64, write: UInt64)] = [:]
    private var statics: [Int32: Static] = [:]
    private var prevTime: TimeInterval = 0
    private var prevPS: [Int32: Double] = [:]      // cumulative CPU seconds for processes only `ps` can see
    private var timebase = mach_timebase_info_data_t()

    init() { mach_timebase_info(&timebase) }

    func sample() -> [RawProcess] {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = (prevTime > 0 && now - prevTime < 6) ? now - prevTime : 0   // stale baseline → report zeros once

        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 64)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let n = max(0, Int(got)) / MemoryLayout<pid_t>.size

        var result: [RawProcess] = []
        result.reserveCapacity(n)
        var nextPrev: [Int32: (UInt64, UInt64, UInt64)] = [:]
        var nextStatics: [Int32: Static] = [:]

        for pid in pids[0..<n] where pid > 0 {
            var ru = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &ru) { p in
                p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard rc == 0 else { continue }

            let st: Static
            if let s = statics[pid], s.startTime == ru.ri_proc_start_abstime {
                st = s
            } else {
                st = Self.readStatic(pid: pid, startTime: ru.ri_proc_start_abstime)
            }
            nextStatics[pid] = st

            let cpuNs = (ru.ri_user_time &+ ru.ri_system_time) &* UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
            var cpu = 0.0, rd = 0.0, wr = 0.0
            if dt > 0, let p = prev[pid] {
                if cpuNs >= p.cpu { cpu = Double(cpuNs - p.cpu) / (dt * 1e9) * 100 }
                if ru.ri_diskio_bytesread >= p.read { rd = Double(ru.ri_diskio_bytesread - p.read) / dt }
                if ru.ri_diskio_byteswritten >= p.write { wr = Double(ru.ri_diskio_byteswritten - p.write) / dt }
            }
            nextPrev[pid] = (cpuNs, ru.ri_diskio_bytesread, ru.ri_diskio_byteswritten)

            result.append(RawProcess(pid: pid, ppid: st.ppid, uid: st.uid, name: st.name, path: st.path,
                                     cpu: cpu, memory: ru.ri_phys_footprint, diskReadBps: rd, diskWriteBps: wr))
        }

        result += readRestrictedProcesses(skipping: Set(nextPrev.keys), dt: dt)

        prev = nextPrev
        statics = nextStatics
        prevTime = now
        return result
    }

    /// Root-owned processes (WindowServer, launchd, …) can't be inspected by an unprivileged app through libproc.
    /// The system `ps` tool is setuid and may read them, so use it (read-only) to fill the gaps.
    private func readRestrictedProcesses(skipping seen: Set<Int32>, dt: TimeInterval) -> [RawProcess] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,uid=,rss=,time=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var out: [RawProcess] = []
        var nextPS: [Int32: Double] = [:]
        for line in text.split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard f.count == 6, let pid = Int32(f[0]), !seen.contains(pid), pid > 0,
                  let ppid = Int32(f[1]), let uid = UInt32(f[2]), let rssKB = UInt64(f[3]) else { continue }
            let cpuSeconds = Self.parseCPUTime(String(f[4]))
            nextPS[pid] = cpuSeconds
            var cpu = 0.0
            if dt > 0, let before = prevPS[pid], cpuSeconds >= before { cpu = (cpuSeconds - before) / dt * 100 }
            let path = String(f[5])
            let name = (path as NSString).lastPathComponent
            out.append(RawProcess(pid: pid, ppid: ppid, uid: uid, name: name.isEmpty ? "pid \(pid)" : name, path: path,
                                  cpu: cpu, memory: rssKB * 1024, diskReadBps: 0, diskWriteBps: 0))
        }
        prevPS = nextPS
        return out
    }

    /// "1:02:03.45", "02:03.45" or "1-02:03:04" → seconds.
    private static func parseCPUTime(_ s: String) -> Double {
        var days = 0.0
        var rest = Substring(s)
        if let dash = s.firstIndex(of: "-") {
            days = Double(s[..<dash]) ?? 0
            rest = s[s.index(after: dash)...]
        }
        var secs = 0.0
        for part in rest.split(separator: ":") { secs = secs * 60 + (Double(part) ?? 0) }
        return days * 86400 + secs
    }

    private static func readStatic(pid: Int32, startTime: UInt64) -> Static {
        var bsd = proc_bsdinfo()
        let sz = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size))
        let ppid = sz > 0 ? Int32(bitPattern: bsd.pbi_ppid) : 0
        let uid = sz > 0 ? bsd.pbi_uid : 0

        var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let plen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        let path = plen > 0 ? String(cString: pathBuf) : ""

        var name = path.isEmpty ? "" : (path as NSString).lastPathComponent
        if name.isEmpty {
            var nameBuf = [CChar](repeating: 0, count: 64)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            name = String(cString: nameBuf)
        }
        if name.isEmpty { name = "pid \(pid)" }
        return Static(startTime: startTime, ppid: ppid, uid: uid, name: name, path: path)
    }
}
