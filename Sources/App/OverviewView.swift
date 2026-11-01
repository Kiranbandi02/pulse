import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage("useBits") private var useBits = false
    @Binding var selection: AppSection

    var body: some View {
        let s = monitor.snapshot
        let h = monitor.history
        ScrollView {
            VStack(spacing: 18) {
                healthBanner

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    StatCard(title: "Processor", symbol: "cpu", color: Palette.cpu,
                             value: Fmt.percent(s.cpu.busy),
                             caption: "Apps \(Fmt.percent(s.cpu.user)) · macOS \(Fmt.percent(s.cpu.system)) · \(s.coreCount) cores",
                             values: h.map { $0.cpuUser + $0.cpuSystem }, maxValue: 100) { selection = .cpu }

                    StatCard(title: "Memory", symbol: "memorychip", color: Palette.memory,
                             value: Fmt.memory(s.memory.used),
                             caption: "of \(Fmt.memory(s.memory.total)) · pressure: \(s.memory.pressure.label.lowercased())",
                             values: h.map { $0.memFraction * 100 }, maxValue: 100) { selection = .memory }

                    StatCard(title: "Network", symbol: "arrow.up.arrow.down", color: Palette.down,
                             value: "↓ " + Fmt.speed(s.network.downBps, bits: useBits),
                             caption: "↑ \(Fmt.speed(s.network.upBps, bits: useBits)) upload",
                             values: h.map { $0.down }) { selection = .network }

                    StatCard(title: "Disk", symbol: "internaldrive", color: Palette.disk,
                             value: Fmt.storage(s.disk.free) + " free",
                             caption: "of \(Fmt.storage(s.disk.total)) · read \(Fmt.speed(s.disk.readBps)) · write \(Fmt.speed(s.disk.writeBps))",
                             values: h.map { $0.diskRead + $0.diskWrite }) { selection = .disk }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Using the most processor", systemImage: "cpu").font(.headline)
                            TopProcessesList(rows: monitor.top(.cpu, 5), metric: .cpu)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Using the most memory", systemImage: "memorychip").font(.headline)
                            TopProcessesList(rows: monitor.top(.memory, 5), metric: .memory)
                        }
                    }
                }

                systemFooter(s)
            }
            .padding(24)
        }
        .navigationTitle("Overview")
    }

    private var healthBanner: some View {
        let h = monitor.health
        let color: Color = h.level == .good ? Palette.good : (h.level == .busy ? Palette.warn : Palette.bad)
        let symbol = h.level == .good ? "checkmark.seal.fill" : (h.level == .busy ? "gauge.with.dots.needle.67percent" : "exclamationmark.triangle.fill")
        return HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(color)
                .frame(width: 56, height: 56)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(h.title).font(.title2.weight(.bold))
                Text(h.detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(color.opacity(0.25)))
        .animation(.easeInOut, value: h.title)
    }

    private func systemFooter(_ s: SystemSnapshot) -> some View {
        HStack(spacing: 12) {
            if let b = s.battery {
                pill(b.isCharging ? "battery.100.bolt" : "battery.75", "Battery \(b.percent)%",
                     b.isCharging ? "Charging" : (b.onAC ? "Plugged in" : (b.minutesRemaining.map { "\($0 / 60)h \($0 % 60)m left" } ?? "On battery")))
            }
            pill("thermometer.medium", "Temperature", thermalText(s.thermal))
            pill("clock", "Up for", Fmt.duration(s.uptime))
            pill("square.stack.3d.up", "Processes", "\(monitor.processCount) running")
            Spacer(minLength: 0)
        }
    }

    private func thermalText(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "Normal"
        case .fair: return "Slightly warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        @unknown default: return "Unknown"
        }
    }

    private func pill(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.background.secondary, in: Capsule())
    }
}
