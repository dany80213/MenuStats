import AppKit
import Charts
import SwiftUI

// MARK: - Palette

/// Validated categorical slots (blue, orange, aqua, yellow, magenta), stepped separately for light and dark.
enum Palette {
    static let series: [Color] = [
        dynamic(0x2A78D6, 0x3987E5),
        dynamic(0xEB6834, 0xD95926),
        dynamic(0x1BAF7A, 0x199E70),
        dynamic(0xEDA100, 0xC98500),
        dynamic(0xE87BA4, 0xD55181),
    ]
    static let neutral = Color.primary.opacity(0.18)

    static func color(_ index: Int) -> Color { series[index % series.count] }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Layout pieces

extension View {
    /// Right-click ▸ "Nascondi sezione" on an optional dropdown section (re-enable it in Settings).
    func hideable(_ section: PanelSection) -> some View {
        contextMenu {
            Button("Nascondi “\(section.title)”") { Settings.shared.setShown(section, false) }
            Text("Puoi riattivarla in Impostazioni ▸ \(section.module.name)")
        }
    }
}

struct Card<Content: View>: View {
    var title: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if let trailing {
                        Text(trailing).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.045)))
    }
}

/// Large headline number with a caption.
struct Hero: View {
    var value: String
    var caption: String
    var accent: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                if let accent {
                    RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(width: 3, height: 22)
                }
                Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct StatGrid: View {
    var items: [(String, String)]
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: columns),
                  alignment: .leading, spacing: 5) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    Text(items[index].0).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(items[index].1).monospacedDigit().lineLimit(1)
                }
                .font(.system(size: 11.5))
            }
        }
    }
}

struct UsageBar: View {
    var fraction: Double
    var color: Color = Palette.color(0)
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.neutral)
                Capsule().fill(color).frame(width: max(height, geometry.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

/// Composition bar (e.g. memory) with a 2 pt gap between segments and a legend below.
struct StackedBar: View {
    struct Segment {
        var name: String
        var value: Double
        var color: Color
        var label: String
    }

    var segments: [Segment]

    var body: some View {
        let total = max(segments.map(\.value).reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let available = geometry.size.width - CGFloat(segments.count - 1) * 2
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segments[index].color)
                            .frame(width: max(2, available * CGFloat(segments[index].value / total)))
                    }
                }
            }
            .frame(height: 10)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                ForEach(segments.indices, id: \.self) { index in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(segments[index].color).frame(width: 8, height: 8)
                        Text(segments[index].name).foregroundStyle(.secondary)
                        Spacer(minLength: 2)
                        Text(segments[index].label).monospacedDigit()
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }
}

/// Status badge: icon + label + color, never color alone.
struct StatusBadge: View {
    enum Level { case good, warning, critical }
    var label: String
    var level: Level

    var body: some View {
        let (symbol, color): (String, Color) = switch level {
        case .good: ("checkmark.circle.fill", .green)
        case .warning: ("exclamationmark.triangle.fill", .orange)
        case .critical: ("xmark.octagon.fill", .red)
        }
        Label(label, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.13)))
    }
}

// MARK: - Process list

struct ProcessList: View {
    var rows: [ProcessGroup]
    var count: Int
    var value: (ProcessGroup) -> Double
    var label: (ProcessGroup) -> String
    var color: Color = Palette.color(0)
    var emptyText = "Nessuna attività"

    var body: some View {
        let top = rows.filter { value($0) > 0 }.sorted { value($0) > value($1) }.prefix(count)
        let maximum = max(top.first.map(value) ?? 1, .ulpOfOne)
        VStack(spacing: 2) {
            if top.isEmpty {
                Text(emptyText).font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            }
            ForEach(Array(top)) { row in
                HStack(spacing: 7) {
                    Image(nsImage: IconCache.icon(for: row.iconPath)).resizable().frame(width: 16, height: 16)
                    Text(row.count > 1 ? "\(row.name) (\(row.count))" : row.name)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(label(row)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 5)
                .frame(height: 21)
                .background(alignment: .leading) {
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.12))
                            .frame(width: geometry.size.width * CGFloat(value(row) / maximum))
                    }
                }
            }
            // Keep a stable height so the panel doesn't jump as processes come and go.
            ForEach(0..<max(0, count - max(top.count, 1)), id: \.self) { _ in Color.clear.frame(height: 21) }
        }
    }
}

// MARK: - History chart

struct ChartLine {
    var metric: Metric
    var name: String
    var color: Int
}

enum ChartScale {
    case percent, rate, temperature, rpm, watts, bytes

    func format(_ value: Double, compact: Bool = false) -> String {
        switch self {
        case .percent: Format.percent(value)
        case .rate: Format.rate(value, compact: compact)
        case .temperature: String(format: "%.0f°", value)
        case .rpm: String(format: "%.0f", value)
        case .watts: String(format: "%.0f W", value == 0 ? 0 : value)
        case .bytes: value <= 0 ? "0" : Format.storage(UInt64(value))
        }
    }
}

/// History chart with live / 1 h / 24 h / 7 d ranges (shared picker), gap breaks, hover crosshair and readout.
struct MetricChart: View {
    @ObservedObject var model: AppModel
    var title: String
    var lines: [ChartLine]
    var scale: ChartScale
    var stacked = false
    var height: CGFloat = 86

    @AppStorage("chart.range") private var rangeRaw = HistoryRange.live.rawValue
    @State private var hoverDate: Date?

    private struct Point: Identifiable {
        var id: String { "\(line)-\(date.timeIntervalSince1970)" }
        var date: Date
        var value: Double
        var line: Int
        var segment: Int
    }

    private var range: HistoryRange { HistoryRange(rawValue: rangeRaw) ?? .live }

    private func points() -> [[Point]] {
        let interval = range == .live ? model.settings.refreshInterval : Double(range.bucketMinutes * 60)
        return lines.enumerated().map { index, line in
            let raw: [(Date, Double)] = range == .live
                ? model.livePoints(line.metric).map { ($0.date, $0.value) }
                : model.history.series(line.metric, range: range).map {
                    (Date(timeIntervalSince1970: TimeInterval($0.minute * 60 + range.bucketMinutes * 30)), $0.value)
                }
            var segment = 0
            var previous: Date?
            return raw.map { date, value in
                if let previous, date.timeIntervalSince(previous) > interval * 2.5 { segment += 1 }
                previous = date
                let shown = scale == .temperature ? Format.temperatureValue(value) : value
                return Point(date: date, value: shown, line: index, segment: segment)
            }
        }
    }

    private func domain(_ values: [Double]) -> ClosedRange<Double> {
        switch scale {
        case .percent:
            return 0...1
        case .temperature:
            let low = (values.min() ?? 30) - 4, high = (values.max() ?? 60) + 4
            return (low / 5).rounded(.down) * 5...(high / 5).rounded(.up) * 5
        default:
            let floor: Double = switch scale {
            case .rate: 10_000
            case .rpm: 3000
            case .watts: 10
            case .bytes: 1_073_741_824
            default: 1
            }
            let top = Self.niceCeiling(max(values.max() ?? 0, floor))
            // Battery power is negative while discharging: extend the axis below zero.
            let bottom = (values.min() ?? 0) < 0 ? -Self.niceCeiling(max(-(values.min() ?? 0), floor)) : 0
            return bottom...top
        }
    }

    private static func niceCeiling(_ value: Double) -> Double {
        let magnitude = pow(10, floor(log10(value)))
        return [1, 2, 2.5, 5, 10].map { $0 * magnitude }.first { $0 >= value } ?? value
    }

    var body: some View {
        let series = points()
        let all = series.flatMap { $0 }
        let stackedTotals: [Double] = stacked
            ? Dictionary(grouping: all, by: \.date).values.map { $0.map(\.value).reduce(0, +) } : []
        let yDomain = domain(stacked ? stackedTotals : all.map(\.value))
        let end = Date()
        let start = end.addingTimeInterval(-Double(range.spanMinutes * 60))
        let hovered = hoverDate.map { date in
            series.compactMap { line in line.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
        } ?? []

        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if let hoverDate, !hovered.isEmpty {
                    Text(Self.timeFormatter(range).string(from: hoverDate) + "  " +
                         hovered.map { scale.format($0.value) }.joined(separator: " · "))
                        .font(.system(size: 10.5)).monospacedDigit()
                } else if lines.count == 1, let latest = series.first?.last {
                    Text(scale.format(latest.value)).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
                }
            }

            Chart {
                ForEach(all) { point in
                    if stacked {
                        AreaMark(x: .value("Ora", point.date), y: .value("Valore", point.value), stacking: .standard)
                            .foregroundStyle(by: .value("Serie", lines[point.line].name))
                            .interpolationMethod(.monotone)
                    } else {
                        if lines.count == 1 {
                            AreaMark(x: .value("Ora", point.date),
                                     yStart: .value("Base", max(yDomain.lowerBound, min(0, yDomain.upperBound))), yEnd: .value("Valore", point.value),
                                     series: .value("Segmento", "\(point.line)-\(point.segment)"))
                                .foregroundStyle(LinearGradient(colors: [Palette.color(lines[0].color).opacity(0.28),
                                                                         Palette.color(lines[0].color).opacity(0.03)],
                                                                startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                        }
                        LineMark(x: .value("Ora", point.date), y: .value("Valore", point.value),
                                 series: .value("Segmento", "\(point.line)-\(point.segment)"))
                            .foregroundStyle(Palette.color(lines[point.line].color))
                            .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                if let hoverDate, !hovered.isEmpty {
                    RuleMark(x: .value("Ora", hoverDate)).foregroundStyle(Color.primary.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1))
                    if !stacked {
                        ForEach(hovered) { point in
                            PointMark(x: .value("Ora", point.date), y: .value("Valore", point.value))
                                .foregroundStyle(Palette.color(lines[point.line].color))
                                .symbolSize(36)
                        }
                    }
                }
            }
            .chartForegroundStyleScale(domain: lines.map(\.name), range: lines.map { Palette.color($0.color) })
            .chartLegend(.hidden)
            .chartXScale(domain: start...end)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel(format: Self.axisFormat(range)).font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Double.self) { Text(scale.format(number, compact: true)).font(.system(size: 9)) }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let origin = geometry[proxy.plotAreaFrame].origin
                                hoverDate = proxy.value(atX: location.x - origin.x, as: Date.self)
                            case .ended:
                                hoverDate = nil
                            }
                        }
                }
            }
            .chartPlotStyle { $0.clipped() } // keep marks inside the plot without cutting the axis labels
            .frame(height: height)
            .overlay {
                if all.isEmpty {
                    Text("Raccolta dati in corso…").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }

            if lines.count > 1 {
                HStack(spacing: 14) {
                    ForEach(lines.indices, id: \.self) { index in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1.5).fill(Palette.color(lines[index].color)).frame(width: 10, height: 3)
                            Text(lines[index].name).foregroundStyle(.secondary)
                            if let latest = series[index].last {
                                Text(scale.format(latest.value)).monospacedDigit()
                            }
                        }
                    }
                }
                .font(.system(size: 10.5))
            }
        }
    }

    private static func axisFormat(_ range: HistoryRange) -> Date.FormatStyle {
        switch range {
        case .live, .hour: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        case .day: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        case .week: .dateTime.weekday(.abbreviated)
        }
    }

    private static func timeFormatter(_ range: HistoryRange) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = switch range {
        case .live: "HH:mm:ss"
        case .hour, .day: "HH:mm"
        case .week: "EEE HH:mm"
        }
        return formatter
    }
}
