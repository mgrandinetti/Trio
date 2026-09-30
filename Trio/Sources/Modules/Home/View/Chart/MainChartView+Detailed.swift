import Charts
import CoreData
import SwiftUI

// Detailed Home chart style (`HomeChartStyle.detailed`). Everything specific to it lives
// here so the stock chart stays as upstream ships it: one card with zoom buttons and a Time in
// Range pill, the glucose plot, then active insulin, active carbs and basal strips on the same
// time axis. Presentation only: it draws data the Home state model already exposes.
//
// One `MainChartView` still drives glucose and strips, so pan, pinch, double tap and
// press-and-hold stay in sync: the scrolling canvas fills only the plot column, while titles,
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

/// Geometry of the detailed chart card, in points: zoom buttons and Time in Range on top, a
/// thin event band (boluses, "now", unit), the glucose plot, three strips (active insulin,
/// active carbs, basal) and the hour labels once at the bottom. Only the glucose plot height
/// varies: Home gives it whatever the screen leaves, so the whole Home fits without scrolling.
struct DetailedChartLayout: Equatable {
    /// Screen x where the plot column starts (card inset + card padding).
    static let plotLeading: CGFloat = 32
    /// From the plot's right edge to the screen edge: y-axis labels plus card inset.
    static let axisColumnWidth: CGFloat = 66
    /// y-axis labels and strip values end this far from the screen edge.
    static let axisLabelTrailing: CGFloat = 30
    /// Zoom buttons and Time in Range pill.
    static let headerHeight: CGFloat = 44
    static let controlHeight: CGFloat = 28
    /// Bolus marks, the "now" label and the glucose unit, above the glucose plot.
    static let eventBandHeight: CGFloat = 18
    /// Between the glucose plot and the first strip.
    static let stripSeparation: CGFloat = 8
    /// Separator line, then the strip name and current value on one row.
    static let stripTitleHeight: CGFloat = 24
    static let stripPlotHeight: CGFloat = 36
    /// Below each strip's plot.
    static let stripGap: CGFloat = 6
    static let hourRowHeight: CGFloat = 22
    static let minGlucosePlotHeight: CGFloat = 120
    static var stripHeight: CGFloat { stripTitleHeight + stripPlotHeight + stripGap }
    /// Card height without the glucose plot.
    static var fixedHeight: CGFloat {
        headerHeight + eventBandHeight + stripSeparation + 3 * stripHeight + hourRowHeight
    }

    /// Glucose plot height.
    let glucose: CGFloat

    /// Height of the scrolling canvas: event band, glucose plot, strips and hour labels.
    var canvasHeight: CGFloat {
        Self.eventBandHeight + glucose + Self.stripSeparation + 3 * Self.stripHeight + Self.hourRowHeight
    }

    /// Top of strip `index` (0 insulin, 1 carbs, 2 basal) in the canvas, at its separator line.
    func stripTop(_ index: Int) -> CGFloat {
        Self.eventBandHeight + glucose + Self.stripSeparation + CGFloat(index) * Self.stripHeight
    }

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
    /// below the event band in the detailed one.
    var glucosePaneTop: CGFloat { isDetailed ? DetailedChartLayout.eventBandHeight : basalHeight }

    /// One card: zoom buttons and Time in Range on top, then the chart stack with its titles,
    /// current values and y-axis labels drawn beside the plot column, never inside it.
    func detailedChartCard(_ chartStack: some View) -> some View {
        let palette = DetailedPalette(colorScheme)
        return VStack(spacing: 0) {
            detailedChartHeader(palette)
            chartStack
                .padding(.leading, DetailedChartLayout.plotLeading)
                .padding(.trailing, DetailedChartLayout.axisColumnWidth)
                .background(alignment: .topLeading) { detailedChartChrome(palette) }
        }
        .background {
            Color.clear
                .detailedCard(palette)
                .padding(.horizontal, 16)
        }
    }

    private func detailedChartHeader(_ palette: DetailedPalette) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(MainChartHelper.Config.detailedZoomPresets, id: \.self) { seconds in
                    let isSelected = abs(visibleSeconds - seconds) < 60
                    Button {
                        selectZoomPreset(seconds)
                    } label: {
                        Text("\(Int(seconds / 3600))" + String(localized: "h", comment: "h"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : palette.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? Color.tabBar : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .frame(maxWidth: 228)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.rail))

            Spacer(minLength: 0)

            timeInRangePill(palette)
                .frame(width: 124)
        }
        .frame(height: DetailedChartLayout.controlHeight)
        .padding(.horizontal, 28)
        .padding(.top, 11)
        .frame(height: DetailedChartLayout.headerHeight, alignment: .top)
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
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(palette.rail, lineWidth: 2.4)
                    Circle()
                        .trim(from: 0, to: hasData ? CGFloat(distribution.inRangePct / 100) : 0)
                        .stroke(palette.glucose, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12)

                Text(verbatim: "TIR")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.muted)

                Spacer(minLength: 2)

                Text(tirString)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.leading, 8)
            .padding(.trailing, 9)
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

    /// Event band labels, strip titles, current values and y-axis labels, laid out around
    /// the plot column. Drawn behind the chart stack; nothing here sits inside a plot area.
    private func detailedChartChrome(_ palette: DetailedPalette) -> some View {
        let layout = detailedLayout
        let iobScale = state.detailedIobScale
        let cob = state.enactedAndNonEnactedDeterminations.first?.cob ?? 0
        let insulinUnit = String(localized: " U", comment: "Insulin unit")
        let rateUnit = String(localized: " U/hr", comment: "Unit per hour with space")

        return ZStack(alignment: .topLeading) {
            detailedEventBandLabels(palette)
            detailedGlucoseAxis(layout, palette)

            detailedStripChrome(
                0,
                String(localized: "Active insulin", comment: "Detailed Home chart pane title"),
                value: (Formatter.decimalFormatterWithTwoFractionDigits.string(from: state.currentIOB as NSNumber) ?? "0")
                    + insulinUnit,
                tint: palette.insulin,
                maxLabel: "\(Int(iobScale.upperBound))" + insulinUnit,
                zeroFraction: iobScale.upperBound / (iobScale.upperBound - iobScale.lowerBound),
                layout,
                palette
            )

            detailedStripChrome(
                1,
                String(localized: "Active carbs", comment: "Detailed Home chart pane title"),
                value: (Formatter.integerFormatter.string(from: NSNumber(value: cob)) ?? "0")
                    + String(localized: " g", comment: "gram of carbs"),
                tint: palette.carbs,
                maxLabel: "\(Int(state.detailedCobMax))" + String(localized: " g", comment: "gram of carbs"),
                zeroFraction: 1,
                layout,
                palette
            )

            detailedStripChrome(
                2,
                String(localized: "Basal Rate"),
                value: (state.tempBasals.last?.tempBasal?.rate).map {
                    (Formatter.decimalFormatterWithTwoFractionDigits.string(from: $0) ?? "\($0)") + rateUnit
                } ?? "--",
                tint: palette.basal,
                maxLabel: "\(Int(state.detailedBasalMax))" + rateUnit,
                zeroFraction: 1,
                layout,
                palette
            )
        }
        .frame(width: geo.size.width, height: layout.canvasHeight, alignment: .topLeading)
    }

    /// "now" just right of the current time line and the glucose unit over the axis column;
    /// the bolus marks of the band scroll with the canvas.
    @ViewBuilder private func detailedEventBandLabels(_ palette: DetailedPalette) -> some View {
        let plotWidth = DetailedChartLayout.plotWidth(screenWidth: geo.size.width)
        let nowX = CGFloat(Date.now.timeIntervalSince(scrollPosition) / visibleSeconds) * plotWidth
        let y = DetailedChartLayout.eventBandHeight / 2 - 1

        // hidden near the right edge, where it would run into the unit label
        if nowX >= 0, nowX <= plotWidth - 40 {
            Text(String(
                localized: "chart.now",
                defaultValue: "now",
                comment: "Detailed Home chart: label of the current time line"
            ))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)
                .position(x: DetailedChartLayout.plotLeading + nowX + 7 + 30, y: y)
                .accessibilityHidden(true)
        }
        axisLabel(units.rawValue, size: 9, tint: palette.muted, isEmphasized: false)
            .position(x: axisLabelCenterX, y: y)
    }

    /// Round values and the dashed high / low thresholds, beside the glucose plot.
    private func detailedGlucoseAxis(_ layout: DetailedChartLayout, _ palette: DetailedPalette) -> some View {
        let domain = paddedGlucoseYDomain
        let span = max(Double(truncating: (domain.upperBound - domain.lowerBound) as NSNumber), 1)
        func y(_ value: Decimal) -> CGFloat {
            let fraction = Double(truncating: (value - domain.lowerBound) as NSNumber) / span
            return layout.glucose * CGFloat(1 - min(max(fraction, 0), 1))
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
        // a round-value label never crowds a threshold label nor leaves the plot's height
        let ticks: [(text: String, y: CGFloat, tint: Color?)] = DetailedChartLayout.glucoseTicks(in: domain, units: units)
            .map { (text: label($0), y: y($0), tint: Color?.none) }
            .filter { tick in
                tick.y >= 6 && tick.y <= layout.glucose - 6 && thresholds.allSatisfy { abs($0.y - tick.y) >= 14 }
            }

        return ForEach(Array((ticks + thresholds).enumerated()), id: \.offset) { _, tick in
            axisLabel(tick.text, size: 10.5, tint: tick.tint ?? palette.muted, isEmphasized: tick.tint != nil)
                .position(x: axisLabelCenterX, y: DetailedChartLayout.eventBandHeight + tick.y)
        }
    }

    /// Separator, then strip name and current value on one row above the plot; top-of-scale
    /// and zero labels beside the plot.
    private func detailedStripChrome(
        _ index: Int,
        _ title: String,
        value: String,
        tint: Color,
        maxLabel: String,
        zeroFraction: Double,
        _ layout: DetailedChartLayout,
        _ palette: DetailedPalette
    ) -> some View {
        let top = layout.stripTop(index)
        let plotTop = top + DetailedChartLayout.stripTitleHeight
        let maxY = plotTop + 4
        // the zero label sits just above the zero line, never on the top label
        let zeroY = max(plotTop + DetailedChartLayout.stripPlotHeight * CGFloat(zeroFraction) - 4, maxY + 11)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(palette.border)
                .frame(
                    width: geo.size.width - DetailedChartLayout.plotLeading - DetailedChartLayout.axisLabelTrailing,
                    height: 0.6
                )
                .offset(x: DetailedChartLayout.plotLeading, y: top)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.leading, DetailedChartLayout.plotLeading)
            .padding(.trailing, DetailedChartLayout.axisLabelTrailing)
            .frame(width: geo.size.width, height: 18)
            .offset(y: top + 4)
            .accessibilityElement(children: .combine)

            axisLabel(maxLabel, size: 9, tint: palette.muted, isEmphasized: false)
                .position(x: axisLabelCenterX, y: maxY)
            axisLabel("0", size: 9, tint: palette.muted, isEmphasized: false)
                .position(x: axisLabelCenterX, y: zeroY)
        }
    }

    /// Center x of the 50 pt wide y-axis labels, ending `axisLabelTrailing` from the screen edge.
    private var axisLabelCenterX: CGFloat {
        geo.size.width - DetailedChartLayout.axisLabelTrailing - 25
    }

    private func axisLabel(_ text: String, size: CGFloat, tint: Color, isEmphasized: Bool) -> some View {
        Text(text)
            .font(.system(size: size, weight: isEmphasized ? .semibold : .medium))
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
    /// Event band, glucose plot, then the three strips, each below the room for its title
    /// row (drawn by the pinned chrome), then the hour labels once for all of them.
    @ViewBuilder func detailedPanes() -> some View {
        let palette = DetailedPalette(colorScheme)
        let titleRoom = DetailedChartLayout.stripTitleHeight
        let gap = DetailedChartLayout.stripGap
        let plotHeight = DetailedChartLayout.stripPlotHeight

        detailedBolusBand(palette)
        mainChart
        Color.clear.frame(height: DetailedChartLayout.stripSeparation + titleRoom)
        detailedIobChart(palette).frame(width: canvasWidth, height: plotHeight)
        Color.clear.frame(height: gap + titleRoom)
        detailedCobChart(palette).frame(width: canvasWidth, height: plotHeight)
        Color.clear.frame(height: gap + titleRoom)
        detailedBasalChart(palette).frame(width: canvasWidth, height: plotHeight)
        Color.clear.frame(height: gap)
        detailedHourLabels(palette)
    }

    /// Boluses as small triangles above the glucose plot; amounts are read by pressing and
    /// holding the chart.
    private func detailedBolusBand(_ palette: DetailedPalette) -> some View {
        let window = max(windowEnd.timeIntervalSince(windowStart), 1)
        let dates = windowedInsulin.compactMap { event -> Date? in
            guard let amount = event.bolus?.amount, amount != 0 else { return nil }
            return event.timestamp
        }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(palette.insulin)
                    .position(
                        x: CGFloat(date.timeIntervalSince(windowStart) / window) * canvasWidth,
                        y: DetailedChartLayout.eventBandHeight / 2 - 1
                    )
            }
        }
        .frame(width: canvasWidth, height: DetailedChartLayout.eventBandHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Hour labels under the last strip, at the same absolute marks as the grid lines.
    private func detailedHourLabels(_ palette: DetailedPalette) -> some View {
        let window = max(windowEnd.timeIntervalSince(windowStart), 1)
        return ZStack(alignment: .topLeading) {
            ForEach(hourAxisMarks(over: windowStart ... windowEnd), id: \.self) { date in
                Text(date.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow))))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                    .fixedSize()
                    .position(
                        x: CGFloat(date.timeIntervalSince(windowStart) / window) * canvasWidth,
                        y: DetailedChartLayout.hourRowHeight / 2
                    )
            }
        }
        .frame(width: canvasWidth, height: DetailedChartLayout.hourRowHeight, alignment: .topLeading)
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

/// Carbs (and fat/protein equivalents) as small dots along the bottom of the glucose pane,
/// without numbers; boluses sit in the event band above it. Values are read by pressing and
/// holding the chart.
struct DetailedTreatmentMarks: ChartContent {
    let carbData: [CarbEntryStored]
    let fpuData: [CarbEntryStored]
    let yDomain: ClosedRange<Decimal>
    let palette: DetailedPalette

    private var carbY: Decimal { yDomain.lowerBound + (yDomain.upperBound - yDomain.lowerBound) * 0.04 }

    var body: some ChartContent {
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

// MARK: - Forecast cone

/// The stock forecast cone (same min/max bounds and 2.5 h horizon), drawn stronger for the
/// detailed cards and with a dashed line through its middle so the expected path reads at a glance.
struct DetailedForecastCone: ChartContent {
    let minForecast: [Int]
    let maxForecast: [Int]
    let units: GlucoseUnits
    let maxValue: Decimal
    let start: Date
    let palette: DetailedPalette

    private func display(_ mgdL: Int) -> Decimal {
        let value = units == .mgdL ? Decimal(mgdL) : Decimal(mgdL).asMmolL
        return min(value, maxValue)
    }

    var body: some ChartContent {
        ForEach(0 ..< min(minForecast.count, maxForecast.count), id: \.self) { index in
            let date = start.addingTimeInterval(TimeInterval(index * 300))
            if date <= Date(timeIntervalSinceNow: TimeInterval(hours: 2.5)) {
                // equal bounds still get a sliver, as in the stock cone
                let spread = minForecast[index] == maxForecast[index] ? 1 : 0
                let lower = display(min(minForecast[index], maxForecast[index]) - spread)
                let upper = display(max(minForecast[index], maxForecast[index]) + spread)
                AreaMark(
                    x: .value("Time", date),
                    yStart: .value("Min Value", lower),
                    yEnd: .value("Max Value", upper)
                )
                .foregroundStyle(palette.insulin.opacity(0.3))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", date),
                    y: .value("Middle", (lower + upper) / 2),
                    series: .value("Series", "ForecastMiddle")
                )
                .foregroundStyle(palette.insulin)
                .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                .interpolationMethod(.catmullRom)
            }
        }
    }
}
