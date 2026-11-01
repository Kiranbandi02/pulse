import SwiftUI
import Charts

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06)))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var maxValue: Double?

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("t", i), y: .value("v", v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", i), y: .value("v", v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(maxValue ?? (values.max() ?? 1) * 1.15, 1))
        .chartLegend(.hidden)
    }
}

struct StatCard: View {
    let title: String
    let symbol: String
    let color: Color
    let value: String
    let caption: String
    let values: [Double]
    var maxValue: Double?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label(title, systemImage: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                    Text(value)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(minHeight: 28, alignment: .topLeading)
                    Sparkline(values: values, color: color, maxValue: maxValue)
                        .frame(height: 54)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct UsageBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color.gradient)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

struct ProcessIcon: View {
    let row: ProcessRow
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let img = IconCache.icon(pid: row.id) {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                Image(systemName: row.kind == .system ? "gearshape.fill" : "terminal.fill")
                    .resizable().scaledToFit().padding(size * 0.2)
                    .foregroundStyle(.secondary)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

enum ProcessMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memory", disk = "Disk"
    var id: String { rawValue }
}

/// Compact list of the top processes for one metric. Read-only.
struct TopProcessesList: View {
    let rows: [ProcessRow]
    let metric: ProcessMetric

    private func value(_ r: ProcessRow) -> Double {
        switch metric {
        case .cpu: return r.cpu
        case .memory: return Double(r.memory)
        case .disk: return r.diskBps
        }
    }

    private func text(_ r: ProcessRow) -> String {
        switch metric {
        case .cpu: return Fmt.percent(r.cpu)
        case .memory: return Fmt.memory(r.memory)
        case .disk: return Fmt.speed(r.diskBps)
        }
    }

    private var color: Color {
        switch metric {
        case .cpu: return Palette.cpu
        case .memory: return Palette.memory
        case .disk: return Palette.disk
        }
    }

    var body: some View {
        let maxV = max(rows.map(value).max() ?? 1, 0.0001)
        VStack(spacing: 10) {
            ForEach(rows) { r in
                HStack(spacing: 10) {
                    ProcessIcon(row: r, size: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.name).font(.callout.weight(.medium)).lineLimit(1)
                        UsageBar(fraction: value(r) / maxV, color: color, height: 4)
                    }
                    Text(text(r))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .trailing)
                }
            }
            if rows.isEmpty {
                Text("Collecting data…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

extension SystemMonitor {
    func top(_ metric: ProcessMetric, _ n: Int) -> [ProcessRow] {
        let rows = groupedProcesses
        let sorted: [ProcessRow]
        switch metric {
        case .cpu: sorted = rows.sorted { $0.cpu > $1.cpu }
        case .memory: sorted = rows.sorted { $0.memory > $1.memory }
        case .disk: sorted = rows.sorted { $0.diskBps > $1.diskBps }
        }
        let filtered = metric == .cpu ? sorted.filter { $0.cpu >= 0.05 } :
                       metric == .memory ? sorted :
                       sorted.filter { $0.diskBps > 0 }
        return Array(filtered.prefix(n))
    }
}

/// Local view state. The command-line toolchain can't expand SwiftUI's `@State` macro, so views keep
/// transient state in a StateObject-backed box instead.
final class Local<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
