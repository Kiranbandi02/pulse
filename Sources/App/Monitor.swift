import SwiftUI
import AppKit
import WidgetKit

enum ProcessKind: String, CaseIterable, Identifiable {
    case app = "Apps"
    case background = "Background"
    case system = "macOS"
    var id: String { rawValue }
}

struct ProcessRow: Identifiable {
    let id: Int32                 // pid of the process (or of the owning app when grouped)
    let name: String
    let user: String
    let path: String
    let kind: ProcessKind
    var cpu: Double
    var memory: UInt64
    var diskBps: Double
    var processCount: Int

    var subtitle: String {
        if processCount > 1 { return "\(processCount) processes" }
        if let d = ProcessGlossary.describe(name) { return d }
        switch kind {
        case .app: return "App"
        case .background: return "Background helper · \(user)"
        case .system: return "macOS service"
        }
    }
}

struct HistoryPoint: Identifiable {
    let id: Int
    let date: Date
    let cpuUser: Double
    let cpuSystem: Double
    let memFraction: Double
    let down: Double
    let up: Double
    let diskRead: Double
    let diskWrite: Double
}

/// Samples on a background queue; delivers results on the main queue.
/// The (more expensive) process scan only runs while something on screen can show it.
private final class SamplingEngine {
    var onUpdate: ((SystemSnapshot, [RawProcess]?) -> Void)?
    private let queue = DispatchQueue(label: "pulse.sampling", qos: .utility)
    private let system = SystemSampler()
    private let processes = ProcessSampler()
    private var timer: DispatchSourceTimer?
    private var tick = 0
    private var lastProcessTick = Int.min / 2
    private var followUpSoon = false

    private let lock = NSLock()
    private var _wantsProcesses = true
    var wantsProcesses: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _wantsProcesses }
        set { lock.lock(); _wantsProcesses = newValue; lock.unlock() }
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let snap = self.system.sample()
            var procs: [RawProcess]?
            if self.wantsProcesses {
                let gap = self.tick - self.lastProcessTick
                if gap >= (self.followUpSoon ? 1 : 2) {
                    // After a long pause the first reading has no baseline; take another a second later.
                    self.followUpSoon = gap > 4
                    procs = self.processes.sample()
                    self.lastProcessTick = self.tick
                }
            }
            self.tick += 1
            DispatchQueue.main.async { self.onUpdate?(snap, procs) }
        }
        t.resume()
        timer = t
    }
}

final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.empty
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var groupedProcesses: [ProcessRow] = []
    @Published private(set) var allProcesses: [ProcessRow] = []
    @Published private(set) var processCount = 0
    @Published private(set) var peakDown = 0.0
    @Published private(set) var peakUp = 0.0
    @Published private(set) var sessionIn: UInt64 = 0
    @Published private(set) var sessionOut: UInt64 = 0

    static let historyLength = 180

    private let engine = SamplingEngine()
    private var counter = 0
    private var lastWidgetReload = Date()
    private var userNames: [UInt32: String] = [:]

    init() {
        engine.onUpdate = { [weak self] snap, procs in self?.apply(snap, procs) }
        engine.start()
    }

    private func apply(_ snap: SystemSnapshot, _ procs: [RawProcess]?) {
        snapshot = snap
        counter += 1
        peakDown = max(peakDown, snap.network.downBps)
        peakUp = max(peakUp, snap.network.upBps)
        sessionIn += UInt64(max(0, snap.network.downBps))
        sessionOut += UInt64(max(0, snap.network.upBps))

        history.append(HistoryPoint(id: counter, date: snap.date, cpuUser: snap.cpu.user, cpuSystem: snap.cpu.system,
                                    memFraction: snap.memory.usedFraction, down: snap.network.downBps, up: snap.network.upBps,
                                    diskRead: snap.disk.readBps, diskWrite: snap.disk.writeBps))
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }

        if let procs { updateProcesses(procs) }

        // Only scan processes while a window (or the menu bar panel) is actually on screen.
        engine.wantsProcesses = NSApp.windows.contains {
            $0.isVisible && $0.canBecomeKey && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }

        // Keep desktop widgets fresh while the app is running.
        if Date().timeIntervalSince(lastWidgetReload) > 60 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Processes

    private func userName(_ uid: UInt32) -> String {
        if let n = userNames[uid] { return n }
        let n = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? "\(uid)"
        userNames[uid] = n
        return n
    }

    private func updateProcesses(_ raw: [RawProcess]) {
        processCount = raw.count

        var apps: [Int32: NSRunningApplication] = [:]
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular {
            apps[a.processIdentifier] = a
        }
        let byPid = Dictionary(uniqueKeysWithValues: raw.map { ($0.pid, $0) })

        func kind(of p: RawProcess) -> ProcessKind {
            if apps[p.pid] != nil { return .app }
            if p.uid == 0 || p.path.hasPrefix("/System/") || p.path.hasPrefix("/usr/") || p.path.hasPrefix("/sbin/")
                || p.path.hasPrefix("/Library/Apple/") { return .system }
            return .background
        }

        func ownerApp(of p: RawProcess) -> Int32? {
            var cur = p
            for _ in 0..<8 {
                if apps[cur.pid] != nil { return cur.pid }
                guard cur.ppid > 1, let parent = byPid[cur.ppid] else { return nil }
                cur = parent
            }
            return nil
        }

        var individual: [ProcessRow] = []
        var groups: [Int32: ProcessRow] = [:]
        var standalone: [ProcessRow] = []

        for p in raw {
            let k = kind(of: p)
            let displayName = apps[p.pid]?.localizedName ?? p.name
            let row = ProcessRow(id: p.pid, name: displayName, user: userName(p.uid), path: p.path, kind: k,
                                 cpu: p.cpu, memory: p.memory, diskBps: p.diskReadBps + p.diskWriteBps, processCount: 1)
            individual.append(row)

            if let owner = ownerApp(of: p), let app = apps[owner] {
                if var g = groups[owner] {
                    g.cpu += row.cpu; g.memory += row.memory; g.diskBps += row.diskBps; g.processCount += 1
                    groups[owner] = g
                } else {
                    groups[owner] = ProcessRow(id: owner, name: app.localizedName ?? p.name, user: row.user,
                                               path: app.bundleURL?.path ?? p.path, kind: .app, cpu: row.cpu,
                                               memory: row.memory, diskBps: row.diskBps, processCount: 1)
                }
            } else {
                standalone.append(row)
            }
        }
        allProcesses = individual
        groupedProcesses = standalone + groups.values
    }

    // MARK: Plain-English health summary

    struct Health {
        enum Level { case good, busy, stressed }
        let level: Level
        let title: String
        let detail: String
    }

    var health: Health {
        let s = snapshot
        let topCPU = groupedProcesses.max(by: { $0.cpu < $1.cpu })
        let topMem = groupedProcesses.max(by: { $0.memory < $1.memory })
        let cpuPerCore = Double(s.coreCount)

        if s.memory.pressure == .critical {
            return Health(level: .stressed, title: "Your Mac is running low on memory",
                          detail: "\(topMem.map { "\($0.name) is using the most (\(Fmt.memory($0.memory)))." } ?? "") Closing apps you aren't using will help.")
        }
        if s.cpu.busy > 85 {
            return Health(level: .stressed, title: "Your Mac is working very hard",
                          detail: topCPU.map { "\($0.name) is the biggest user of processing power right now." } ?? "The processor is almost fully busy.")
        }
        if s.thermal == .serious || s.thermal == .critical {
            return Health(level: .stressed, title: "Your Mac is running hot",
                          detail: "macOS is slowing things down to cool off. Check which apps are busy below.")
        }
        if s.memory.pressure == .warning {
            return Health(level: .busy, title: "Memory is getting tight",
                          detail: "macOS is compressing memory to keep up\(s.memory.swapUsed > 0 ? " and using \(Fmt.memory(s.memory.swapUsed)) of disk as extra memory" : "").")
        }
        if s.cpu.busy > 60 || s.loadAverage.0 > cpuPerCore {
            return Health(level: .busy, title: "Your Mac is fairly busy",
                          detail: topCPU.map { "\($0.name) is using \(Fmt.percent($0.cpu)) of one processor core." } ?? "Several things are running at once.")
        }
        return Health(level: .good, title: "Everything looks healthy",
                      detail: "CPU, memory and disk have plenty of room. Nothing needs your attention.")
    }
}

// MARK: - App icons

enum IconCache {
    private static var cache: [Int32: NSImage] = [:]

    static func icon(pid: Int32) -> NSImage? {
        if let i = cache[pid] { return i }
        guard let i = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        cache[pid] = i
        return i
    }
}

// MARK: - "What is this process?"

enum ProcessGlossary {
    static func describe(_ name: String) -> String? {
        table[name] ?? table[name.lowercased()]
    }

    private static let table: [String: String] = [
        "kernel_task": "macOS core · also manages heat",
        "WindowServer": "Draws everything on your screen",
        "launchd": "Starts and supervises all other processes",
        "mds": "Spotlight search index",
        "mds_stores": "Spotlight search index",
        "mdworker_shared": "Spotlight indexing files",
        "backupd": "Time Machine backup",
        "bluetoothd": "Bluetooth",
        "coreaudiod": "Sound system",
        "airportd": "Wi-Fi",
        "cfprefsd": "Stores app settings",
        "Finder": "Files and desktop",
        "Dock": "The Dock and Mission Control",
        "SystemUIServer": "Menu bar items",
        "ControlCenter": "Control Center",
        "loginwindow": "Login and session manager",
        "trustd": "Certificate checks (security)",
        "syspolicyd": "Gatekeeper security checks",
        "XProtect": "Built-in malware protection",
        "logd": "System logging",
        "powerd": "Power and sleep management",
        "diskarbitrationd": "Mounts and unmounts disks",
        "fseventsd": "Watches file changes",
        "photoanalysisd": "Photos scanning faces and objects",
        "photolibraryd": "Photos library",
        "cloudd": "iCloud sync",
        "bird": "iCloud Drive sync",
        "nsurlsessiond": "Background downloads",
        "softwareupdated": "macOS software updates",
        "sharingd": "AirDrop and Handoff",
        "rapportd": "Connects with your other Apple devices",
        "apsd": "Apple push notifications",
        "mDNSResponder": "Finds devices on your network",
        "com.apple.WebKit.WebContent": "Web page (Safari or an app)",
        "com.apple.WebKit.Networking": "Web networking",
        "distnoted": "System notifications between apps",
        "notifyd": "System notifications between apps",
        "usernoted": "Notification banners",
        "corespotlightd": "Spotlight suggestions",
        "suggestd": "Siri suggestions",
        "spotlightknowledged": "Spotlight suggestions",
    ]
}
