import SwiftUI
import Charts

// MARK: - CPU

struct CPUView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        let s = monitor.snapshot
        ScrollView {
            VStack(spacing: 18) {
                PageHeader(title: "Processor", subtitle: "How hard your Mac's brain is working", symbol: "cpu", color: Palette.cpu)

                HStack(spacing: 16) {
                    Card {
                        HStack(spacing: 20) {
                            RingGauge(value: s.cpu.busy / 100, color: Palette.load(s.cpu.busy), lineWidth: 14) {
                                VStack(spacing: 0) {
                                    Text(Fmt.percent(s.cpu.busy)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                                    Text("busy").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 130, height: 130)
                            VStack(alignment: .leading, spacing: 8) {
                                legendRow(Palette.cpu, "Apps", Fmt.percent(s.cpu.user), "Work done by you and your apps")
                                legendRow(.orange, "macOS", Fmt.percent(s.cpu.system), "Work done by the system itself")
                                legendRow(.gray, "Idle", Fmt.percent(s.cpu.idle), "Spare capacity")
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Load average").font(.headline)
                            Text("How many tasks were waiting for a core, over the last 1 / 5 / 15 minutes. Staying below \(s.coreCount) is healthy.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 18) {
                                loadStat("1 min", s.loadAverage.0, cores: s.coreCount)
                                loadStat("5 min", s.loadAverage.1, cores: s.coreCount)
                                loadStat("15 min", s.loadAverage.2, cores: s.coreCount)
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Last 3 minutes").font(.headline)
                        Chart {
                            ForEach(monitor.history) { p in
                                AreaMark(x: .value("Time", p.date), y: .value("Usage", p.cpuUser), stacking: .standard)
                                    .foregroundStyle(by: .value("Type", "Apps"))
                                    .interpolationMethod(.monotone)
                                AreaMark(x: .value("Time", p.date), y: .value("Usage", p.cpuSystem), stacking: .standard)
                                    .foregroundStyle(by: .value("Type", "macOS"))
                                    .interpolationMethod(.monotone)
                            }
                        }
                        .chartForegroundStyleScale(["Apps": Palette.cpu, "macOS": Color.orange])
                        .chartYScale(domain: 0...100)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                                AxisGridLine()
                                AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)%") } }
                            }
                        }
                        .frame(height: 200)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Each processor core").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                            ForEach(Array(s.cpu.perCore.enumerated()), id: \.offset) { i, v in
                                VStack(spacing: 4) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .bottom) {
                                            RoundedRectangle(cornerRadius: 6).fill(Palette.cpu.opacity(0.12))
                                            RoundedRectangle(cornerRadius: 6).fill(Palette.load(v).gradient)
                                                .frame(height: max(3, geo.size.height * v / 100))
                                        }
                                    }
                                    .frame(height: 56)
                                    Text("\(i + 1)").font(.caption2).foregroundStyle(.secondary)
                                }
                                .animation(.easeOut(duration: 0.4), value: v)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Using the most processor", systemImage: "list.number").font(.headline)
                        Text("100% = one full core. Apps that use several cores can go above 100%.")
                            .font(.caption).foregroundStyle(.secondary)
                        TopProcessesList(rows: monitor.top(.cpu, 8), metric: .cpu)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Processor")
    }

    private func legendRow(_ color: Color, _ name: String, _ value: String, _ hint: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text(name).fontWeight(.semibold); Text(value).monospacedDigit().foregroundStyle(.secondary) }
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func loadStat(_ label: String, _ v: Double, cores: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.2f", v))
                .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(v > Double(cores) ? Palette.bad : .primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Memory

struct MemoryView: View {
    @EnvironmentObject var monitor: SystemMonitor

    private struct Segment: Identifiable {
        let id: String; let name: String; let hint: String; let bytes: UInt64; let color: Color
    }

    var body: some View {
        let m = monitor.snapshot.memory
        let segments = [
            Segment(id: "app", name: "Apps", hint: "Memory your open apps are using", bytes: m.app, color: Palette.memory),
            Segment(id: "wired", name: "Locked by macOS", hint: "Essential system memory that can't be freed", bytes: m.wired, color: .orange),
            Segment(id: "comp", name: "Compressed", hint: "Squeezed to save space — a sign memory is getting full", bytes: m.compressed, color: .pink),
            Segment(id: "cache", name: "Cached files", hint: "Recent files kept handy; released instantly if needed", bytes: m.cached, color: Palette.cpu.opacity(0.7)),
            Segment(id: "free", name: "Free", hint: "Completely unused", bytes: m.free, color: .gray.opacity(0.5)),
        ]
        ScrollView {
            VStack(spacing: 18) {
                PageHeader(title: "Memory", subtitle: "Where your \(Fmt.memory(m.total)) of RAM is going", symbol: "memorychip", color: Palette.memory)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Fmt.memory(m.used)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("in use of \(Fmt.memory(m.total))").foregroundStyle(.secondary)
                            Spacer()
                            pressureBadge(m.pressure)
                        }
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(segments) { seg in
                                    let w = m.total > 0 ? geo.size.width * Double(seg.bytes) / Double(m.total) : 0
                                    RoundedRectangle(cornerRadius: 4).fill(seg.color.gradient).frame(width: max(0, w - 2))
                                }
                            }
                        }
                        .frame(height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .animation(.easeOut(duration: 0.4), value: m.used)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .topLeading)], spacing: 12) {
                            ForEach(segments) { seg in
                                HStack(alignment: .top, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 3).fill(seg.color).frame(width: 12, height: 12).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack { Text(seg.name).fontWeight(.semibold); Text(Fmt.memory(seg.bytes)).monospacedDigit().foregroundStyle(.secondary) }
                                        Text(seg.hint).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Memory pressure", systemImage: "gauge.with.dots.needle.50percent").font(.headline)
                            Text(pressureExplanation(m.pressure)).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Swap used", systemImage: "arrow.left.arrow.right.circle").font(.headline)
                            Text(Fmt.memory(m.swapUsed)).font(.system(size: 26, weight: .bold, design: .rounded))
                            Text(m.swapUsed == 0 ? "Not needed right now. Great."
                                 : "macOS is borrowing disk space as extra memory. A lot of swap can make your Mac feel slow.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Last 3 minutes").font(.headline)
                        Chart(monitor.history) { p in
                            AreaMark(x: .value("Time", p.date), y: .value("Used", p.memFraction * 100))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(LinearGradient(colors: [Palette.memory.opacity(0.4), Palette.memory.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Time", p.date), y: .value("Used", p.memFraction * 100))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Palette.memory)
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(values: [0, 50, 100]) { v in
                                AxisGridLine()
                                AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)%") } }
                            }
                        }
                        .frame(height: 150)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Using the most memory", systemImage: "list.number").font(.headline)
                        TopProcessesList(rows: monitor.top(.memory, 8), metric: .memory)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Memory")
    }

    private func pressureBadge(_ p: MemoryPressure) -> some View {
        let c: Color = p == .normal ? Palette.good : (p == .warning ? Palette.warn : Palette.bad)
        return Text("Pressure: \(p.label)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(c.opacity(0.18), in: Capsule())
            .foregroundStyle(c)
    }

    private func pressureExplanation(_ p: MemoryPressure) -> String {
        switch p {
        case .normal: return "macOS has plenty of memory to go around. Nothing to do."
        case .warning: return "Memory is getting tight. macOS is compressing data to cope. Consider closing apps you aren't using."
        case .critical: return "Memory is nearly exhausted and your Mac will feel slow. Close big apps (see the list below)."
        }
    }
}
