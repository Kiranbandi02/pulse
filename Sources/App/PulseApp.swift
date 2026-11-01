import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case cpu = "Processor"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"
    case processes = "Processes"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "arrow.up.arrow.down"
        case .disk: return "internaldrive"
        case .processes: return "list.bullet.rectangle"
        }
    }

    var color: Color {
        switch self {
        case .overview: return .gray
        case .cpu: return Palette.cpu
        case .memory: return Palette.memory
        case .network: return Palette.down
        case .disk: return Palette.disk
        case .processes: return .indigo
        }
    }
}

@main
struct PulseApp: App {
    @StateObject private var monitor = SystemMonitor()
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("useBits") private var useBits = false

    var body: some Scene {
        WindowGroup("Pulse", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Toggle("Show Network Speed in Menu Bar", isOn: $showMenuBar)
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel()
                .environmentObject(monitor)
        } label: {
            let n = monitor.snapshot.network
            Image(nsImage: MenuBarSpeedImage.make(down: n.downBps, up: n.upBps, bits: useBits))
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView() }
    }
}

struct SettingsView: View {
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("useBits") private var useBits = false
    @AppStorage("groupHelpers") private var groupHelpers = true

    var body: some View {
        Form {
            Toggle("Show network speed in the menu bar", isOn: $showMenuBar)
            Toggle("Show speeds in megabits per second (Mbps)", isOn: $useBits)
            Toggle("Combine helper processes with their app", isOn: $groupHelpers)
            Text("Pulse only reads system statistics. It never quits, changes or controls any process.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 240)
    }
}

struct ContentView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @StateObject private var selectionBox = Local(AppSection.overview)
    private var selection: AppSection { selectionBox.value }

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectionBox.value) { section in
                HStack(spacing: 10) {
                    Image(systemName: section.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(section.color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(section.rawValue)
                    Spacer()
                    Text(trailing(section)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .tag(section)
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch selection {
            case .overview: OverviewView(selection: $selectionBox.value)
            case .cpu: CPUView()
            case .memory: MemoryView()
            case .network: NetworkView()
            case .disk: DiskView()
            case .processes: ProcessesView()
            }
        }
    }

    private func trailing(_ s: AppSection) -> String {
        let snap = monitor.snapshot
        switch s {
        case .cpu: return Fmt.percent(snap.cpu.busy)
        case .memory: return Fmt.percent(snap.memory.usedFraction * 100)
        case .network: return Fmt.speed(snap.network.downBps)
        default: return ""
        }
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage("useBits") private var useBits = false
    @AppStorage("showMenuBar") private var showMenuBar = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ring("CPU", s.cpu.busy / 100, Fmt.percent(s.cpu.busy), Palette.load(s.cpu.busy))
                ring("Memory", s.memory.usedFraction, Fmt.percent(s.memory.usedFraction * 100), Palette.memory)
                ring("Disk", s.disk.usedFraction, Fmt.percent(s.disk.usedFraction * 100), Palette.disk)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                SpeedLabel(symbol: "arrow.down", bps: s.network.downBps, color: Palette.down, bits: useBits)
                SpeedLabel(symbol: "arrow.up", bps: s.network.upBps, color: Palette.up, bits: useBits)
            }
            Sparkline(values: monitor.history.suffix(60).map(\.down), color: Palette.down).frame(height: 36)
            Divider()
            Text("Top processor use").font(.caption).foregroundStyle(.secondary)
            TopProcessesList(rows: monitor.top(.cpu, 3), metric: .cpu)
            Divider()
            HStack {
                Button("Open Pulse") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let w = NSApp.windows.first(where: { $0.canBecomeMain }) { w.makeKeyAndOrderFront(nil) } else { openWindow(id: "main") }
                }
                Spacer()
                Button("Hide menu bar item") { showMenuBar = false }.buttonStyle(.link).font(.caption)
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func ring(_ title: String, _ v: Double, _ text: String, _ c: Color) -> some View {
        VStack(spacing: 4) {
            RingGauge(value: v, color: c, lineWidth: 7) {
                Text(text).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 70, height: 70)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Menu bar items only take one line of text, so draw download over upload into a template image.
@MainActor
enum MenuBarSpeedImage {
    static func make(down: Double, up: Double, bits: Bool) -> NSImage {
        let view = VStack(alignment: .trailing, spacing: 0) {
            Text("↓ \(Fmt.speed(down, bits: bits))")
            Text("↑ \(Fmt.speed(up, bits: bits))")
        }
        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.black)
        .frame(width: 66, height: 22, alignment: .trailing)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 66, height: 22))
        image.isTemplate = true     // adapts to light/dark menu bars
        return image
    }
}
