import SwiftUI

enum Palette {
    static let cpu = Color(red: 0.27, green: 0.52, blue: 1.00)
    static let memory = Color(red: 0.62, green: 0.40, blue: 0.95)
    static let down = Color(red: 0.12, green: 0.78, blue: 0.62)
    static let up = Color(red: 1.00, green: 0.58, blue: 0.20)
    static let disk = Color(red: 0.96, green: 0.38, blue: 0.58)
    static let good = Color(red: 0.20, green: 0.78, blue: 0.40)
    static let warn = Color(red: 1.00, green: 0.72, blue: 0.15)
    static let bad = Color(red: 0.97, green: 0.30, blue: 0.30)

    /// Green → amber → red as a percentage climbs.
    static func load(_ percent: Double) -> Color {
        percent < 60 ? good : (percent < 85 ? warn : bad)
    }
}

struct RingGauge<Content: View>: View {
    let value: Double          // 0...1
    var color: Color
    var lineWidth: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.003, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content()
        }
        .padding(lineWidth / 2)
    }
}

struct SpeedLabel: View {
    let symbol: String
    let bps: Double
    let color: Color
    var bits = false
    var font: Font = .system(.callout, design: .rounded).weight(.semibold)

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(Fmt.speed(bps, bits: bits)).monospacedDigit()
        }
        .font(font)
    }
}
