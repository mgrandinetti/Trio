import Charts
import CoreData
import SwiftUI

// Detailed Home chart style (`HomeChartStyle.detailed`). Everything specific to it lives
// here so the stock chart stays as upstream ships it: a glucose card, then active insulin,
// active carbs and basal in their own cards on the same time axis, with zoom buttons and a
// Time in Range pill. Presentation only: it draws data the Home state model already exposes.
//
// One `MainChartView` still drives every card, so pan, pinch, double tap and press-and-hold
// stay in sync: the scrolling canvas fills only the plot column, while card chrome, titles,
// values and y-axis labels sit in a pinned background around it and never overlap a curve.

extension MainChartHelper.Config {
    /// Double-tap cycle and zoom buttons of the detailed style.
    static let detailedZoomPresets: [TimeInterval] = [3 * 3600, 6 * 3600, 12 * 3600, 24 * 3600]
}

/// Colors of the detailed style, one set per appearance; text colors reach 4.5:1 on `card`.
struct DetailedPalette {
    let card: Color
    let border: Color
    let ink: Color
    let muted: Color
    let grid: Color
    let rail: Color
    let glucose: Color
    let insulin: Color
    let carbs: Color
    let basal: Color
    let high: Color
    let low: Color
    let band: Color

    init(_ colorScheme: ColorScheme) {
        func rgb(_ hex: UInt32) -> Color {
            Color(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255
            )
        }
        let dark = colorScheme == .dark
        card = rgb(dark ? 0x172333 : 0xFFFFFF)
        border = rgb(dark ? 0x2A3849 : 0xDFE5EC)
        ink = rgb(dark ? 0xF4F7FB : 0x152234)
        muted = rgb(dark ? 0xA8B5C7 : 0x59687A)
        grid = rgb(dark ? 0x344253 : 0xD9E0E9)
        rail = rgb(dark ? 0x263446 : 0xE0E7EF)
        glucose = rgb(dark ? 0x67DDB0 : 0x11744F)
        insulin = rgb(dark ? 0x70B7FF : 0x175DAF)
        carbs = rgb(dark ? 0xFFAD68 : 0xA74708)
        basal = rgb(dark ? 0xBCA5FF : 0x6C46B5)
        high = rgb(dark ? 0xF4D267 : 0x896407)
        low = rgb(dark ? 0xFF939A : 0xB92E40)
        band = glucose.opacity(dark ? 0.16 : 0.09)
    }
}

extension View {
    /// Card surface of the detailed style.
    func detailedCard(_ palette: DetailedPalette, cornerRadius: CGFloat = 20) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 0.6)
                )
        )
    }
}

extension Home.StateModel {
    /// Rounded y-scales of the lower cards, shared by the charts and their axis labels.
    var detailedIobScale: ClosedRange<Double> {
        let upper = max(ceil((maxValueIobChart as NSDecimalNumber).doubleValue), 1)
        return min((minValueIobChart as NSDecimalNumber).doubleValue, 0) ... upper
    }

    var detailedCobMax: Double {
        max(ceil((maxValueCobChart as NSDecimalNumber).doubleValue / 10) * 10, 10)
    }

    var detailedBasalMax: Double {
        let rates = tempBasals.compactMap { $0.tempBasal?.rate?.doubleValue }
            + basalProfile.map { ($0.rate as NSDecimalNumber).doubleValue }
        return max(ceil(rates.max() ?? 0), 1)
    }
}

/// Card geometry of the detailed stack, in points. Only the glucose plot height varies: Home
/// sizes it so the top of the "Active insulin" card peeks above the bottom controls.
struct DetailedChartLayout: Equatable {
    static let zoomBarHeight: CGFloat = 38
    static let cardSpacing: CGFloat = 12
    /// Screen x where the plot column starts (card inset + card padding).
    static let plotLeading: CGFloat = 32
    /// From the plot's right edge to the screen edge: y-axis labels plus card inset.
    static let axisColumnWidth: CGFloat = 66
    /// y-axis labels end this far from the screen edge.
    static let axisLabelTrailing: CGFloat = 31
    static let glucoseHeaderHeight: CGFloat = 55
    static let glucoseFooterHeight: CGFloat = 39
    static let minGlucosePlotHeight: CGFloat = 150
    static let paneHeaderHeight: CGFloat = 58
    static let panePlotHeight: CGFloat = 70
    static let paneFooterHeight: CGFloat = 36
    static var paneCardHeight: CGFloat { paneHeaderHeight + panePlotHeight + paneFooterHeight }

    /// Glucose plot height.
    let glucose: CGFloat

    var glucoseCardHeight: CGFloat { Self.glucoseHeaderHeight + glucose + Self.glucoseFooterHeight }
    var canvasHeight: CGFloat { glucoseCardHeight + 3 * (Self.cardSpacing + Self.paneCardHeight) }

    static func plotWidth(screenWidth: CGFloat) -> CGFloat {
        screenWidth - plotLeading - axisColumnWidth
    }

    /// Round values for the glucose grid lines and labels (50 mg/dL or 2 mmol/L apart).
    static func glucoseTicks(in domain: ClosedRange<Decimal>, units: GlucoseUnits) -> [Decimal] {
        let step: Decimal = units == .mgdL ? 50 : 2
        var tick = step * Decimal(Int(truncating: (domain.lowerBound / step) as NSNumber) + 1)
        var ticks: [Decimal] = []
        while tick < domain.upperBound {
            ticks.append(tick)
            tick += step
        }
        return ticks
    }
}

// MARK: - Shell (pinned, never scrolls horizontally)

extension MainChartView {
    var isDetailed: Bool { chartStyle == .detailed }

    var detailedLayout: DetailedChartLayout { DetailedChartLayout(glucose: chartHeight) }

    /// Top of the glucose pane in the stack: below the basal strip in the stock style,
    /// below the glucose card header in the detailed one.
    var glucosePaneTop: CGFloat { isDetailed ? DetailedChartLayout.glucoseHeaderHeight : basalHeight }

    var detailedZoomBar: some View {
        let palette = DetailedPalette(colorScheme)
        return HStack(spacing: 11) {
            HStack(spacing: 0) {
                ForEach(MainChartHelper.Config.detailedZoomPresets, id: \.self) { seconds in
                    let isSelected = abs(visibleSeconds - seconds) < 60
                    Button {
                        selectZoomPreset(seconds)
                    } label: {
                        Text("\(Int(seconds / 3600))" + String(localized: "h", comment: "h"))
                            .font(.subheadline).fontWeight(isSelected ? .semibold : .medium).fontDesign(.rounded)
                            .foregroundStyle(isSelected ? Color.white : palette.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isSelected ? Color.tabBar : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .detailedCard(palette, cornerRadius: 12)

            timeInRangePill(palette)
                .frame(width: 100)
        }
        .frame(height: DetailedChartLayout.zoomBarHeight)
        .padding(.horizontal, 16)
    }

    /// Today's time in range (same figure as the stock stats banner); opens Statistics.
    private func timeInRangePill(_ palette: DetailedPalette) -> some View {
        let distribution = state.todayGlucoseDistribution
        let hasData = distribution.veryLowPct + distribution.lowPct + distribution.inRangePct
            + distribution.highPct + distribution.veryHighPct > 0
        let tirString = hasData
            ? distribution.inRangePct.formatted(.number.precision(.fractionLength(0 ... 1))) + " %"
            : "-- %"

        return Button {
            state.showModal(for: .statistics)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(palette.rail, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: hasData ? CGFloat(distribution.inRangePct / 100) : 0)
                        .stroke(palette.glucose, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)

                Text(tirString)
                    .font(.subheadline).fontWeight(.semibold).fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(palette.card))
            .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time in Range"))
        .accessibilityValue(Text(tirString))
        .accessibilityHint(Text(String(localized: "Opens statistics", comment: "Accessibility hint")))
        .accessibilityAddTraits(.isButton)
    }

    /// Card surfaces, titles, current values and y-axis labels, laid out around the plot
    /// column. Drawn behind the chart stack; nothing here sits inside a plot area.
    var detailedCards: some View {
        let layout = detailedLayout
        let palette = DetailedPalette(colorScheme)
        let iobScale = state.detailedIobScale
        let cob = state.enactedAndNonEnactedDeterminations.first?.cob ?? 0

        return VStack(spacing: DetailedChartLayout.cardSpacing) {
            detailedGlucoseCard(layout, palette)
                .frame(height: layout.glucoseCardHeight)

            detailedPaneCard(
                String(localized: "Active insulin", comment: "Detailed Home chart pane title"),
                value: (Formatter.decimalFormatterWithTwoFractionDigits.string(from: state.currentIOB as NSNumber) ?? "0")
                    + String(localized: " U", comment: "Insulin unit"),
                tint: palette.insulin,
                maxLabel: "\(Int(iobScale.upperBound))" + String(localized: " U", comment: "Insulin unit"),
                zeroFraction: iobScale.upperBound / (iobScale.upperBound - iobScale.lowerBound),
                palette
            )

            detailedPaneCard(
                String(localized: "Active carbs", comment: "Detailed Home chart pane title"),
                value: (Formatter.integerFormatter.string(from: NSNumber(value: cob)) ?? "0")
                    + String(localized: " g", comment: "gram of carbs"),
                tint: palette.carbs,
                maxLabel: "\(Int(state.detailedCobMax))" + String(localized: " g", comment: "gram of carbs"),
                zeroFraction: 1,
                palette
            )

            detailedPaneCard(
                String(localized: "Basal Rate"),
                value: (state.tempBasals.last?.tempBasal?.rate).map {
                    (Formatter.decimalFormatterWithTwoFractionDigits.string(from: $0) ?? "\($0)")
                        + String(localized: " U/hr", comment: "Unit per hour with space")
                } ?? "--",
                tint: palette.basal,
                maxLabel: "\(Int(state.detailedBasalMax))" + String(localized: " U/hr", comment: "Unit per hour with space"),
                zeroFraction: 1,
                palette
            )
        }
        .padding(.horizontal, 16)
        .frame(width: geo.size.width, alignment: .topLeading)
    }

    private func detailedGlucoseCard(_ layout: DetailedChartLayout, _ palette: DetailedPalette) -> some View {
        let domain = paddedGlucoseYDomain
        let span = max(Double(truncating: (domain.upperBound - domain.lowerBound) as NSNumber), 1)
        func y(_ value: Decimal) -> CGFloat {
            let fraction = Double(truncating: (value - domain.lowerBound) as NSNumber) / span
            return DetailedChartLayout.glucoseHeaderHeight + layout.glucose * CGFloat(1 - min(max(fraction, 0), 1))
        }
        func label(_ value: Decimal) -> String {
            units == .mgdL
                ? "\(Int(truncating: value as NSNumber))"
                : value.formatted(.number.precision(.fractionLength(0 ... 1)))
        }

        let high = units == .mgdL ? highGlucose : highGlucose.asMmolL
        let low = units == .mgdL ? lowGlucose : lowGlucose.asMmolL
        let thresholds: [(text: String, y: CGFloat, tint: Color?)] = [
            (label(high), y(high), palette.high),
            (label(low), y(low), palette.low)
        ]
        // a round-value label never crowds a threshold label
        let ticks: [(text: String, y: CGFloat, tint: Color?)] = DetailedChartLayout.glucoseTicks(in: domain, units: units)
            .map { (text: label($0), y: y($0), tint: Color?.none) }
            .filter { tick in thresholds.allSatisfy { abs($0.y - tick.y) >= 14 } }

        let plotWidth = DetailedChartLayout.plotWidth(screenWidth: geo.size.width)
        let nowX = CGFloat(Date.now.timeIntervalSince(scrollPosition) / visibleSeconds) * plotWidth
        let cardWidth = geo.size.width - 32

        return ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Blood glucose", comment: "Detailed Home chart card title"))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(units.rawValue)
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if nowX >= 0, nowX <= plotWidth {
                Text(String(
                    localized: "chart.now",
                    defaultValue: "now",
                    comment: "Detailed Home chart: label of the current time line"
                ))
                    .font(.caption2).fontWeight(.medium)
                    .foregroundStyle(palette.muted)
                    .fixedSize()
                    .position(x: DetailedChartLayout.plotLeading - 16 + nowX, y: 42)
            }

            ForEach(Array((ticks + thresholds).enumerated()), id: \.offset) { _, tick in
                axisLabel(tick.text, tint: tick.tint ?? palette.muted, isEmphasized: tick.tint != nil)
                    .position(x: cardWidth - (DetailedChartLayout.axisLabelTrailing - 16) - 25, y: tick.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .detailedCard(palette)
    }

    /// Lower card: title and current value above the plot, 0 and top-of-scale labels beside it.
    private func detailedPaneCard(
        _ title: String,
        value: String,
        tint: Color,
        maxLabel: String,
        zeroFraction: Double,
        _ palette: DetailedPalette
    ) -> some View {
        let cardWidth = geo.size.width - 32
        let plotTop = DetailedChartLayout.paneHeaderHeight
        let plotHeight = DetailedChartLayout.panePlotHeight
        let labelX = cardWidth - (DetailedChartLayout.axisLabelTrailing - 16) - 25

        return ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(value)
                    .font(.headline).fontWeight(.semibold).fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .accessibilityElement(children: .combine)

            axisLabel(maxLabel, tint: palette.muted, isEmphasized: false)
                .position(x: labelX, y: plotTop)
            axisLabel("0", tint: palette.muted, isEmphasized: false)
                .position(x: labelX, y: plotTop + plotHeight * CGFloat(zeroFraction))
        }
        .frame(height: DetailedChartLayout.paneCardHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .detailedCard(palette)
    }

    private func axisLabel(_ text: String, tint: Color, isEmphasized: Bool) -> some View {
        Text(text)
            .font(.caption).fontWeight(isEmphasized ? .semibold : .medium)
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 50, alignment: .trailing)
            .accessibilityHidden(true)
    }
}

// MARK: - Canvas panes

extension MainChartCanvas {
    @ViewBuilder func detailedPanes() -> some View {
        let palette = DetailedPalette(colorScheme)
        let gap = DetailedChartLayout.cardSpacing + DetailedChartLayout.paneHeaderHeight

        Color.clear.frame(height: DetailedChartLayout.glucoseHeaderHeight)
        mainChart
        detailedHourLabels(palette, height: DetailedChartLayout.glucoseFooterHeight)
        Color.clear.frame(height: gap)
        detailedIobChart(palette).frame(width: canvasWidth, height: DetailedChartLayout.panePlotHeight)
        detailedHourLabels(palette, height: DetailedChartLayout.paneFooterHeight)
        Color.clear.frame(height: gap)
        detailedCobChart(palette).frame(width: canvasWidth, height: DetailedChartLayout.panePlotHeight)
        detailedHourLabels(palette, height: DetailedChartLayout.paneFooterHeight)
        Color.clear.frame(height: gap)
        detailedBasalChart(palette).frame(width: canvasWidth, height: DetailedChartLayout.panePlotHeight)
        detailedHourLabels(palette, height: DetailedChartLayout.paneFooterHeight)
    }

    /// Hour labels under a card's plot, at the same absolute marks as the grid lines.
    private func detailedHourLabels(_ palette: DetailedPalette, height: CGFloat) -> some View {
        let window = max(windowEnd.timeIntervalSince(windowStart), 1)
        return ZStack(alignment: .topLeading) {
            ForEach(hourAxisMarks(over: windowStart ... windowEnd), id: \.self) { date in
                Text(date.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow))))
                    .font(.caption).fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                    .fixedSize()
                    .position(x: CGFloat(date.timeIntervalSince(windowStart) / window) * canvasWidth, y: 18)
            }
        }
        .frame(width: canvasWidth, height: height, alignment: .topLeading)
    }

    /// In-range band, round-value grid lines and dashed high (yellow) / low (red) thresholds.
    @ChartContentBuilder func drawDetailedThresholdLines() -> some ChartContent {
        let palette = DetailedPalette(colorScheme)
        let low = units == .mgdL ? lowGlucose : lowGlucose.asMmolL
        let high = units == .mgdL ? highGlucose : highGlucose.asMmolL

        RectangleMark(
            xStart: .value("Range start", windowStart, unit: .second),
            xEnd: .value("Range end", windowEnd, unit: .second),
            yStart: .value("In range low", low),
            yEnd: .value("In range high", high)
        )
        .foregroundStyle(palette.band)
        ForEach(DetailedChartLayout.glucoseTicks(in: glucoseYDomain, units: units), id: \.self) { tick in
            RuleMark(y: .value("Grid", tick))
                .foregroundStyle(palette.grid)
                .lineStyle(.init(lineWidth: 0.6))
        }
        RuleMark(y: .value("High", high))
            .foregroundStyle(palette.high)
            .lineStyle(.init(lineWidth: 1.2, dash: [4, 4]))
        RuleMark(y: .value("Low", low))
            .foregroundStyle(palette.low)
            .lineStyle(.init(lineWidth: 1.2, dash: [4, 4]))
    }

    /// Grid lines at the bottom and top of a lower card's scale.
    @ChartContentBuilder private func drawPaneGrid(_ scale: ClosedRange<Double>, palette: DetailedPalette) -> some ChartContent {
        RuleMark(y: .value("Zero", 0.0))
            .foregroundStyle(palette.grid)
            .lineStyle(.init(lineWidth: 0.65))
        RuleMark(y: .value("Top", scale.upperBound))
            .foregroundStyle(palette.grid)
            .lineStyle(.init(lineWidth: 0.65))
    }

    /// One determination per `deliverAt`; the newest wins (same rule as the stock COB/IOB pane).
    private var uniqueWindowedDeterminations: [OrefDetermination] {
        var seenDates = Set<Date>()
        return windowedDeterminations.filter { item in
            guard let date = item.deliverAt else { return true }
            return seenDates.insert(date).inserted
        }
    }

    private var projectionStart: Date {
        state.enactedAndNonEnactedDeterminations.first?.deliverAt ?? state.timerDate
    }

    /// Projection points from the latest determination on, joined to its own value so the
    /// dashed curve starts where the history line ends.
    private func projection(_ points: [ProjectionPoint], anchorValue: Double?) -> [ProjectionPoint] {
        let anchor = projectionStart
        let visible = points.filter { $0.date >= anchor && $0.date <= windowEnd }
        guard let first = visible.first, first.date > anchor, let anchorValue else { return visible }
        return [ProjectionPoint(date: anchor, value: anchorValue)] + visible
    }

    private static let paneLine = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)

    func detailedIobChart(_ palette: DetailedPalette) -> some View {
        let latestIob = state.enactedAndNonEnactedDeterminations.first?.iob?.doubleValue
        let points = projection(state.iobProjection, anchorValue: latestIob)
        let scale = state.detailedIobScale

        return Chart {
            drawPaneGrid(scale, palette: palette)
            drawCurrentTimeMarker()
            ForEach(uniqueWindowedDeterminations) { item in
                let date = item.deliverAt ?? Date()
                let amount = item.iob?.doubleValue ?? 0
                AreaMark(
                    x: .value("Time", date),
                    y: .value("Amount", amount),
                    series: .value("Series", "IOB"),
                    stacking: .unstacked
                )
                .foregroundStyle(palette.insulin.opacity(0.2))
                LineMark(x: .value("Time", date), y: .value("Amount", amount), series: .value("Series", "IOB"))
                    .foregroundStyle(palette.insulin)
                    .lineStyle(Self.paneLine)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Amount", point.value),
                    series: .value("Series", "IOBProjection")
                )
                .foregroundStyle(palette.insulin.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: windowStart ... windowEnd)
        .chartXAxis { mainChartXAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: scale)
    }

    func detailedCobChart(_ palette: DetailedPalette) -> some View {
        let latestCob = state.enactedAndNonEnactedDeterminations.first.map { Double($0.cob) }
        let points = projection(state.cobProjection, anchorValue: latestCob)
        let scale = 0 ... state.detailedCobMax

        return Chart {
            drawPaneGrid(scale, palette: palette)
            drawCurrentTimeMarker()
            ForEach(uniqueWindowedDeterminations) { item in
                let date = item.deliverAt ?? Date()
                let amount = Double(item.cob)
                AreaMark(
                    x: .value("Time", date),
                    y: .value("Value", amount),
                    series: .value("Series", "COB"),
                    stacking: .unstacked
                )
                .foregroundStyle(palette.carbs.opacity(0.2))
                LineMark(x: .value("Time", date), y: .value("Value", amount), series: .value("Series", "COB"))
                    .foregroundStyle(palette.carbs)
                    .lineStyle(Self.paneLine)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", "COBProjection")
                )
                .foregroundStyle(palette.carbs.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: windowStart ... windowEnd)
        .chartXAxis { mainChartXAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: scale)
    }

    /// Basal bars standing on the card floor (the stock strip hangs them from the top),
    /// from the same prepared temp basals, profile and suspensions.
    func detailedBasalChart(_ palette: DetailedPalette) -> some View {
        let tempBasals = preparedTempBasals.filter { $0.end >= windowStart && $0.start <= windowEnd }
        let profiles = basalProfiles.filter { ($0.endDate ?? state.endMarker) >= windowStart && $0.startDate <= windowEnd }
        let suspensions = suspensionIntervals().filter { $0.end >= windowStart && $0.start <= windowEnd }
        let scale = 0 ... state.detailedBasalMax

        return Chart {
            drawPaneGrid(scale, palette: palette)
            drawCurrentTimeMarker()
            ForEach(tempBasals, id: \.start) { basal in
                RectangleMark(
                    xStart: .value("start", basal.start),
                    xEnd: .value("end", basal.end),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", basal.rate)
                )
                .foregroundStyle(palette.basal.opacity(0.2))
                .opacity(basal.isScheduled ? 0.5 : 1)

                LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                    .lineStyle(Self.paneLine).foregroundStyle(palette.basal)
                    .opacity(basal.isScheduled ? 0.5 : 1)
                LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                    .lineStyle(Self.paneLine).foregroundStyle(palette.basal)
                    .opacity(basal.isScheduled ? 0.5 : 1)
            }
            ForEach(profiles, id: \.self) { profile in
                LineMark(
                    x: .value("Start Date", profile.startDate),
                    y: .value("Amount", profile.amount),
                    series: .value("profile", "profile")
                ).lineStyle(.init(lineWidth: 1.5, dash: [2, 4])).foregroundStyle(palette.basal)
                LineMark(
                    x: .value("End Date", profile.endDate ?? state.endMarker),
                    y: .value("Amount", profile.amount),
                    series: .value("profile", "profile")
                ).lineStyle(.init(lineWidth: 1.5, dash: [2, 4])).foregroundStyle(palette.basal)
            }
            ForEach(suspensions, id: \.start) { interval in
                RectangleMark(
                    xStart: .value("start", interval.start),
                    xEnd: .value("end", interval.end),
                    yStart: .value("suspend-start", 0),
                    yEnd: .value("suspend-end", interval.height)
                )
                .foregroundStyle(Color.loopGray.opacity(colorScheme == .dark ? 0.3 : 0.8))
            }
        }
        .onAppear {
            calculateBasals()
        }
        .onChange(of: state.tempBasals) {
            calculateBasals()
            calculateTempBasals()
        }
        .onChange(of: state.maxBasal) {
            calculateBasals()
        }
        .chartLegend(.hidden)
        .chartXScale(domain: windowStart ... windowEnd)
        .chartXAxis { mainChartXAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: scale)
    }
}

// MARK: - Treatment marks

/// Boluses and carbs as small marks without numbers: boluses along the top of the glucose
/// pane, carbs (and fat/protein equivalents) along the bottom. Values are read by pressing
/// and holding the chart.
struct DetailedTreatmentMarks: ChartContent {
    let insulinData: [PumpEventStored]
    let carbData: [CarbEntryStored]
    let fpuData: [CarbEntryStored]
    let yDomain: ClosedRange<Decimal>
    let palette: DetailedPalette

    private var bolusY: Decimal { yDomain.upperBound - (yDomain.upperBound - yDomain.lowerBound) * 0.04 }
    private var carbY: Decimal { yDomain.lowerBound + (yDomain.upperBound - yDomain.lowerBound) * 0.04 }

    var body: some ChartContent {
        ForEach(insulinData) { insulin in
            let amount = insulin.bolus?.amount ?? 0 as NSDecimalNumber
            if amount != 0, let date = insulin.timestamp {
                PointMark(
                    x: .value("Time", date, unit: .second),
                    y: .value("Value", bolusY)
                )
                .symbol {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.insulin)
                }
            }
        }

        ForEach(carbData) { carb in
            if let date = carb.date {
                PointMark(
                    x: .value("Time", date, unit: .second),
                    y: .value("Value", carbY)
                )
                .symbol {
                    Circle()
                        .fill(palette.carbs)
                        .frame(width: 8, height: 8)
                }
            }
        }

        ForEach(fpuData, id: \.id) { fpu in
            if let date = fpu.date {
                PointMark(
                    x: .value("Time", date, unit: .second),
                    y: .value("Value", carbY)
                )
                .symbol {
                    Circle()
                        .fill(Color.brown)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
