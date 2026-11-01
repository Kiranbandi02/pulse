import SwiftUI
import AppKit

struct ProcessesView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage("groupHelpers") private var groupHelpers = true
    @StateObject private var searchBox = Local("")
    @StateObject private var filterBox = Local<ProcessKind?>(nil)
    @StateObject private var sortBox = Local(ProcessMetric.cpu)

    private var search: String { searchBox.value }
    private var filter: ProcessKind? { filterBox.value }
    private var sort: ProcessMetric { sortBox.value }

    private var rows: [ProcessRow] {
        var r = groupHelpers ? monitor.groupedProcesses : monitor.allProcesses
        if let f = filter { r = r.filter { $0.kind == f } }
        if !search.isEmpty { r = r.filter { $0.name.localizedCaseInsensitiveContains(search) || String($0.id) == search } }
        switch sort {
        case .cpu: r.sort { $0.cpu > $1.cpu }
        case .memory: r.sort { $0.memory > $1.memory }
        case .disk: r.sort { $0.diskBps > $1.diskBps }
        }
        return r
    }

    var body: some View {
        let list = rows
        let maxCPU = max(list.map(\.cpu).max() ?? 1, 1)
        let maxMem = Double(list.map(\.memory).max() ?? 1)
        VStack(spacing: 0) {
            controls(count: list.count)
            Divider()
            columnHeader
            Divider()
            List(list) { r in
                HStack(spacing: 10) {
                    ProcessIcon(row: r, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(r.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    metricCell(Fmt.percent(r.cpu), r.cpu / maxCPU, Palette.cpu, highlight: sort == .cpu)
                    metricCell(Fmt.memory(r.memory), Double(r.memory) / maxMem, Palette.memory, highlight: sort == .memory)
                    Text(r.diskBps > 1 ? Fmt.speed(r.diskBps) : "—")
                        .frame(width: 86, alignment: .trailing)
                        .foregroundStyle(sort == .disk ? .primary : .secondary)
                    Text(r.processCount > 1 ? "\(r.processCount)×" : "\(r.id)")
                        .frame(width: 56, alignment: .trailing)
                        .foregroundStyle(.tertiary)
                }
                .font(.callout.monospacedDigit())
                .help(r.path.isEmpty ? r.name : r.path)
                .contextMenu {
                    if !r.path.isEmpty {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)]) }
                    }
                    Button("Copy Name") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.name, forType: .string) }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Processes")
        .searchable(text: $searchBox.value, placement: .toolbar, prompt: "Search apps and processes")
    }

    private func controls(count: Int) -> some View {
        HStack(spacing: 14) {
            Picker("Show", selection: $filterBox.value) {
                Text("Everything").tag(ProcessKind?.none)
                ForEach(ProcessKind.allCases) { Text($0.rawValue).tag(ProcessKind?.some($0)) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            Toggle("Combine helpers with their app", isOn: $groupHelpers)
                .toggleStyle(.checkbox)
                .help("Browsers and editors run many helper processes. This adds them up under the app that started them.")
            Spacer()
            Text("\(count) shown · read-only").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 40)
            sortButton(.cpu, width: 150)
            sortButton(.memory, width: 150)
            sortButton(.disk, width: 86)
            Text("PID").frame(width: 56, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28).padding(.vertical, 6)
    }

    private func sortButton(_ m: ProcessMetric, width: CGFloat) -> some View {
        Button { sortBox.value = m } label: {
            HStack(spacing: 3) {
                Spacer(minLength: 0)
                Text(m.rawValue)
                if sort == m { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
            }
            .frame(width: width)
            .foregroundStyle(sort == m ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func metricCell(_ text: String, _ frac: Double, _ color: Color, highlight: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(text).foregroundStyle(highlight ? .primary : .secondary)
            UsageBar(fraction: frac, color: color, height: 3).frame(width: 70)
        }
        .frame(width: 150, alignment: .trailing)
    }
}
