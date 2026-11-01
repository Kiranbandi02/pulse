import WidgetKit
import SwiftUI

struct StatsEntry: TimelineEntry {
    let date: Date
    let snapshot: SystemSnapshot

    static let placeholder: StatsEntry = {
        var s = SystemSnapshot()
        s.cpu.user = 18; s.cpu.system = 7; s.cpu.idle = 75
        s.memory.total = 16 << 30; s.memory.app = 7 << 30; s.memory.wired = 2 << 30; s.memory.compressed = 1 << 30
        s.network.downBps = 2_400_000; s.network.upBps = 180_000
        s.disk.total = 500_000_000_000; s.disk.free = 220_000_000_000
        s.battery = BatteryStatus(percent: 82, isCharging: false, onAC: false, minutesRemaining: 300)
        s.uptime = 3 * 86400
        return StatsEntry(date: Date(), snapshot: s)
    }()
}

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
        DispatchQueue.global(qos: .userInitiated).async { completion(Self.measure()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let entry = Self.measure()
            // The Pulse app nudges a reload every minute while it is open; otherwise macOS decides when to refresh.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
        }
    }

    /// Speeds are rates, so take a baseline reading, wait a moment, then read again.
    private static func measure() -> StatsEntry {
        let sampler = SystemSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 1.0)
        return StatsEntry(date: Date(), snapshot: sampler.sample())
    }
}

// MARK: - Views

struct SmallView: View {
    let s: SystemSnapshot

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ring("CPU", s.cpu.busy / 100, Fmt.percent(s.cpu.busy), Palette.load(s.cpu.busy))
                ring("RAM", s.memory.usedFraction, Fmt.percent(s.memory.usedFraction * 100), Palette.memory)
            }
            VStack(alignment: .leading, spacing: 3) {
                SpeedLabel(symbol: "arrow.down", bps: s.network.downBps, color: Palette.down, font: .system(.caption, design: .rounded).weight(.semibold))
                SpeedLabel(symbol: "arrow.up", bps: s.network.upBps, color: Palette.up, font: .system(.caption, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ring(_ t: String, _ v: Double, _ text: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            RingGauge(value: v, color: c, lineWidth: 6) {
                Text(text).font(.system(size: 13, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).monospacedDigit()
            }
            Text(t).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct MediumView: View {
    let s: SystemSnapshot

    var body: some View {
        HStack(spacing: 14) {
            ring("Processor", s.cpu.busy / 100, Fmt.percent(s.cpu.busy), Palette.load(s.cpu.busy))
            ring("Memory", s.memory.usedFraction, Fmt.percent(s.memory.usedFraction * 100), Palette.memory)
            VStack(alignment: .leading, spacing: 8) {
                Label("Network", systemImage: "arrow.up.arrow.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Download").font(.system(size: 10)).foregroundStyle(.secondary)
                    SpeedLabel(symbol: "arrow.down", bps: s.network.downBps, color: Palette.down, font: .system(.title3, design: .rounded).weight(.bold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Upload").font(.system(size: 10)).foregroundStyle(.secondary)
                    SpeedLabel(symbol: "arrow.up", bps: s.network.upBps, color: Palette.up, font: .system(.title3, design: .rounded).weight(.bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ring(_ t: String, _ v: Double, _ text: String, _ c: Color) -> some View {
        VStack(spacing: 4) {
            RingGauge(value: v, color: c, lineWidth: 8) {
                Text(text).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Text(t).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

struct LargeView: View {
    let s: SystemSnapshot

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Pulse", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                Text("Up \(Fmt.duration(s.uptime))").font(.caption).foregroundStyle(.secondary)
            }
            MediumView(s: s)
            Divider()
            VStack(spacing: 10) {
                bar("Memory", "\(Fmt.memory(s.memory.used)) of \(Fmt.memory(s.memory.total))", s.memory.usedFraction, Palette.memory)
                bar("Disk", "\(Fmt.storage(s.disk.free)) free of \(Fmt.storage(s.disk.total))", s.disk.usedFraction, Palette.disk)
                if let b = s.battery {
                    bar("Battery", b.isCharging ? "\(b.percent)% · charging" : "\(b.percent)%", Double(b.percent) / 100, b.percent < 20 ? Palette.bad : Palette.good)
                }
                HStack {
                    Label("Disk read \(Fmt.speed(s.disk.readBps))", systemImage: "arrow.down.doc").foregroundStyle(.secondary)
                    Spacer()
                    Label("write \(Fmt.speed(s.disk.writeBps))", systemImage: "arrow.up.doc").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func bar(_ title: String, _ detail: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.opacity(0.18))
                    Capsule().fill(c).frame(width: max(6, geo.size.width * min(1, max(0, v))))
                }
            }
            .frame(height: 6)
        }
    }
}

struct PulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatsEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(s: entry.snapshot)
            case .systemLarge, .systemExtraLarge: LargeView(s: entry.snapshot)
            default: MediumView(s: entry.snapshot)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct PulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseSystemStats", provider: StatsProvider()) { entry in
            PulseWidgetView(entry: entry)
        }
        .configurationDisplayName("System Pulse")
        .description("Processor, memory, disk and live network speed at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct PulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PulseWidget()
    }
}
