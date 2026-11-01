import SwiftUI
import Charts

// MARK: - Network

struct NetworkView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage("useBits") private var useBits = false

    var body: some View {
        let n = monitor.snapshot.network
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    PageHeader(title: "Network", subtitle: "Live internet speed, and which apps are using it", symbol: "arrow.up.arrow.down", color: Palette.down)
                    Picker("Units", selection: $useBits) {
                        Text("MB/s").tag(false)
                        Text("Mbps").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .help("Show speeds in megabytes per second (downloads) or megabits per second (what ISPs advertise)")
                }

                HStack(spacing: 16) {
                    bigSpeed("Download", "arrow.down.circle.fill", n.downBps, Palette.down, peak: monitor.peakDown)
                    bigSpeed("Upload", "arrow.up.circle.fill", n.upBps, Palette.up, peak: monitor.peakUp)
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Last 3 minutes").font(.headline)
                            Spacer()
                            legendDot(Palette.down, "Download"); legendDot(Palette.up, "Upload")
                        }
                        Chart {
                            ForEach(monitor.history) { p in
                                AreaMark(x: .value("Time", p.date), y: .value("Speed", p.down), series: .value("S", "Download"))
                                    .interpolationMethod(.monotone)
                                    .foregroundStyle(LinearGradient(colors: [Palette.down.opacity(0.35), Palette.down.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                LineMark(x: .value("Time", p.date), y: .value("Speed", p.down), series: .value("S", "Download"))
                                    .interpolationMethod(.monotone).foregroundStyle(Palette.down)
                                LineMark(x: .value("Time", p.date), y: .value("Speed", p.up), series: .value("S", "Upload"))
                                    .interpolationMethod(.monotone).foregroundStyle(Palette.up)
                            }
                        }
                        .chartYScale(domain: 0...max(monitor.history.map { max($0.down, $0.up) }.max() ?? 1, 100_000) * 1.15)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks { v in
                                AxisGridLine()
                                AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.speed(d, bits: useBits)) } }
                            }
                        }
                        .frame(height: 220)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Data used", systemImage: "chart.bar.fill").font(.headline)
                            totalRow("Since you opened Pulse", down: monitor.sessionIn, up: monitor.sessionOut)
                            Divider()
                            totalRow("Since your Mac restarted", down: n.totalIn, up: n.totalOut)
                            Text("Wi-Fi and Ethernet combined")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Reading these numbers", systemImage: "lightbulb").font(.headline)
                            Text("**Download** is data coming to your Mac (web pages, video, updates). **Upload** is data leaving it (sending files, video calls, backups).")
                            Text("Your internet plan is usually advertised in megabits per second (Mbps). Switch the units above to compare directly. 8 Mbps is about 1 MB/s.")
                            Text("Speeds are measured across Wi-Fi and Ethernet, so a VPN won't be counted twice.")
                        }
                        .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Network")
    }

    private func bigSpeed(_ title: String, _ symbol: String, _ bps: Double, _ color: Color, peak: Double) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                Text(Fmt.speed(bps, bits: useBits))
                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("Peak this session: \(Fmt.speed(peak, bits: useBits))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t).font(.caption).foregroundStyle(.secondary) }
    }

    private func totalRow(_ title: String, down: UInt64, up: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label(Fmt.storage(down), systemImage: "arrow.down").foregroundStyle(Palette.down)
                Label(Fmt.storage(up), systemImage: "arrow.up").foregroundStyle(Palette.up)
            }
            .font(.system(.title3, design: .rounded).weight(.semibold))
        }
    }
}

// MARK: - Disk

struct DiskView: View {
    @EnvironmentObject var monitor: SystemMonitor

    private struct Volume: Identifiable { let id: String; let name: String; let total: UInt64; let free: UInt64 }

    private var volumes: [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity, total > 0 else { return nil }
            return Volume(id: url.path, name: v.volumeName ?? url.lastPathComponent, total: UInt64(total),
                          free: UInt64(max(0, v.volumeAvailableCapacityForImportantUsage ?? 0)))
        }
    }

    var body: some View {
        let d = monitor.snapshot.disk
        ScrollView {
            VStack(spacing: 18) {
                PageHeader(title: "Disk", subtitle: "Storage space and how busy your drive is", symbol: "internaldrive", color: Palette.disk)

                HStack(spacing: 16) {
                    speedCard("Reading", "arrow.down.doc.fill", d.readBps, Palette.down)
                    speedCard("Writing", "arrow.up.doc.fill", d.writeBps, Palette.up)
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Last 3 minutes").font(.headline)
                            Spacer()
                            HStack(spacing: 4) { Circle().fill(Palette.down).frame(width: 8, height: 8); Text("Read").font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 4) { Circle().fill(Palette.up).frame(width: 8, height: 8); Text("Write").font(.caption).foregroundStyle(.secondary) }
                        }
                        Chart {
                            ForEach(monitor.history) { p in
                                LineMark(x: .value("Time", p.date), y: .value("Speed", p.diskRead), series: .value("S", "Read"))
                                    .interpolationMethod(.monotone).foregroundStyle(Palette.down)
                                LineMark(x: .value("Time", p.date), y: .value("Speed", p.diskWrite), series: .value("S", "Write"))
                                    .interpolationMethod(.monotone).foregroundStyle(Palette.up)
                            }
                        }
                        .chartYScale(domain: 0...max(monitor.history.map { max($0.diskRead, $0.diskWrite) }.max() ?? 1, 1_000_000) * 1.15)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks { v in
                                AxisGridLine()
                                AxisValueLabel { if let x = v.as(Double.self) { Text(Fmt.speed(x)) } }
                            }
                        }
                        .frame(height: 180)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Storage", systemImage: "externaldrive").font(.headline)
                        ForEach(volumes) { v in
                            let used = v.total > v.free ? v.total - v.free : 0
                            let frac = Double(used) / Double(v.total)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(v.name).fontWeight(.semibold)
                                    Spacer()
                                    Text("\(Fmt.storage(v.free)) free of \(Fmt.storage(v.total))").font(.callout).foregroundStyle(.secondary)
                                }
                                UsageBar(fraction: frac, color: frac > 0.9 ? Palette.bad : (frac > 0.75 ? Palette.warn : Palette.disk), height: 10)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Busiest apps (read + write)", systemImage: "list.number").font(.headline)
                        TopProcessesList(rows: monitor.top(.disk, 6), metric: .disk)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Disk")
    }

    private func speedCard(_ title: String, _ symbol: String, _ bps: Double, _ color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                Text(Fmt.speed(bps)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}
