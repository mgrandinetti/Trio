import Charts
import CoreData
import SwiftUI

// Detailed Home chart style (`HomeChartStyle.detailed`). Everything specific to it lives
// here so the stock chart stays as upstream ships it: glucose on top, then active insulin,
// active carbs and basal in their own rows on the same time axis, with small treatment marks
// and zoom buttons. Presentation only: it draws data the Home state model already exposes.

extension MainChartHelper.Config {
    /// Double-tap cycle and zoom buttons of the detailed style.
    static let detailedZoomPresets: [TimeInterval] = [3 * 3600, 6 * 3600, 12 * 3600, 24 * 3600]
}

/// Pane heights of the detailed stack, derived from the chart's allocation.
struct DetailedChartLayout: Equatable {
    static let zoomBarHeight: CGFloat = 40
    /// Strip above each lower pane that carries its pinned title and current value.
    static let titleHeight: CGFloat = 18

    let glucose: CGFloat
    let iob: CGFloat
    let cob: CGFloat
    let basal: CGFloat

    init(chartHeight: CGFloat) {
        let panes = max(chartHeight - Self.zoomBarHeight - 3 * Self.titleHeight, 80)
        glucose = panes * 0.56
        iob = panes * 0.12
        cob = panes * 0.12
        // includes the hour labels, which render once, under the bottom pane
        basal = panes * 0.20
    }

    var iobTitleTop: CGFloat { glucose }
    var cobTitleTop: CGFloat { iobTitleTop + Self.titleHeight + iob }
    var basalTitleTop: CGFloat { cobTitleTop + Self.titleHeight + cob }
    var canvasHeight: CGFloat { basalTitleTop + Self.titleHeight + basal }
}

// MARK: - Shell (pinned, never scrolls)

extension MainChartView {
    var isDetailed: Bool { chartStyle == .detailed }

    var detailedLayout: DetailedChartLayout { DetailedChartLayout(chartHeight: chartHeight) }

    /// Top of the glucose pane in the stack: below the basal strip in the stock style,
    /// first pane in the detailed one.
    var glucosePaneTop: CGFloat { isDetailed ? 0 : basalHeight }

    var detailedZoomBar: some View {
        HStack(spacing: 8) {
            ForEach(MainChartHelper.Config.detailedZoomPresets, id: \.self) { seconds in
                let isSelected = abs(visibleSeconds - seconds) < 60
                Button {
                    selectZoomPreset(seconds)
                } label: {
                    Text("\(Int(seconds / 3600))" + String(localized: "h", comment: "h"))
                        .font(.subheadline).fontWeight(isSelected ? .bold : .medium).fontDesign(.rounded)
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.tabBar : Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }

            Button {
                state.isLegendPresented.toggle()
            } label: {
                Image(systemName: "info")
                    .font(.footnote).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 2))
                    .accessibilityLabel(Text("Chart legend"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: DetailedChartLayout.zoomBarHeight)
    }

    /// Titles and current values of the lower panes, pinned over the scrolling canvas.
    var detailedPaneTitles: some View {
        let layout = detailedLayout
        let cob = state.enactedAndNonEnactedDeterminations.first?.cob ?? 0
        return ZStack(alignment: .topLeading) {
            paneTitle(
                String(localized: "Active insulin", comment: "Detailed Home chart pane title"),
                value: (Formatter.decimalFormatterWithTwoFractionDigits.string(from: state.currentIOB as NSNumber) ?? "0")
                    + String(localized: " U", comment: "Insulin unit"),
                tint: Color.darkerBlue
            )
            .offset(y: layout.iobTitleTop)

            paneTitle(
                String(localized: "Active carbs", comment: "Detailed Home chart pane title"),
                value: (Formatter.integerFormatter.string(from: NSNumber(value: cob)) ?? "0")
                    + String(localized: " g", comment: "gram of carbs"),
                tint: Color.orange
            )
            .offset(y: layout.cobTitleTop)

            paneTitle(
                String(localized: "Basal Rate"),
                value: currentBasalRate.map {
                    (Formatter.decimalFormatterWithTwoFractionDigits.string(from: $0) ?? "\($0)")
                        + String(localized: " U/hr", comment: "Unit per hour with space")
                },
                tint: Color.insulin
            )
            .offset(y: layout.basalTitleTop)
        }
    }

    private var currentBasalRate: NSDecimalNumber? {
        state.tempBasals.last?.tempBasal?.rate
    }

    private func paneTitle(_ title: String, value: String?, tint: Color) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            if let value {
                Text(value)
                    .font(.caption).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: DetailedChartLayout.titleHeight)
    }
}

// MARK: - Canvas panes

extension MainChartCanvas {
    @ViewBuilder func detailedPanes(_ layout: DetailedChartLayout) -> some View {
        mainChart
        Color.clear.frame(height: DetailedChartLayout.titleHeight)
        detailedIobChart.frame(width: canvasWidth, height: layout.iob)
        Color.clear.frame(height: DetailedChartLayout.titleHeight)
        detailedCobChart.frame(width: canvasWidth, height: layout.cob)
        Color.clear.frame(height: DetailedChartLayout.titleHeight)
        detailedBasalChart.frame(width: canvasWidth, height: layout.basal)
    }

    /// Dashed high (yellow) and low (red) thresholds, always on in the detailed style.
    @ChartContentBuilder func drawDetailedThresholdLines() -> some ChartContent {
        RuleMark(y: .value("High", units == .mgdL ? highGlucose : highGlucose.asMmolL))
            .foregroundStyle(Color.loopYellow)
            .lineStyle(.init(lineWidth: 1, dash: [5, 4]))
        RuleMark(y: .value("Low", units == .mgdL ? lowGlucose : lowGlucose.asMmolL))
            .foregroundStyle(Color.loopRed)
            .lineStyle(.init(lineWidth: 1, dash: [5, 4]))
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

    private static func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    var detailedIobChart: some View {
        let latestIob = state.enactedAndNonEnactedDeterminations.first?.iob?.doubleValue
        let points = projection(state.iobProjection, anchorValue: latestIob)
        let lower = min(Self.double(state.minValueIobChart), 0)
        let upper = max(Self.double(state.maxValueIobChart), 0.5)

        return Chart {
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
                .foregroundStyle(Color.darkerBlue.opacity(0.2))
                LineMark(x: .value("Time", date), y: .value("Amount", amount), series: .value("Series", "IOB"))
                    .foregroundStyle(Color.darkerBlue)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Amount", point.value),
                    series: .value("Series", "IOBProjection")
                )
                .foregroundStyle(Color.darkerBlue.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: windowStart ... windowEnd)
        .chartXAxis { mainChartXAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: lower ... upper)
    }

    var detailedCobChart: some View {
        let latestCob = state.enactedAndNonEnactedDeterminations.first.map { Double($0.cob) }
        let points = projection(state.cobProjection, anchorValue: latestCob)
        let upper = max(Self.double(state.maxValueCobChart), 10)

        return Chart {
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
                .foregroundStyle(Color.orange.opacity(0.2))
                LineMark(x: .value("Time", date), y: .value("Value", amount), series: .value("Series", "COB"))
                    .foregroundStyle(Color.orange)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", "COBProjection")
                )
                .foregroundStyle(Color.orange.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: windowStart ... windowEnd)
        .chartXAxis { mainChartXAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... upper)
    }

    /// Basal bars standing on the pane floor (the stock strip hangs them from the top),
    /// from the same prepared temp basals, profile and suspensions.
    var detailedBasalChart: some View {
        let tempBasals = preparedTempBasals.filter { $0.end >= windowStart && $0.start <= windowEnd }
        let profiles = basalProfiles.filter { ($0.endDate ?? state.endMarker) >= windowStart && $0.startDate <= windowEnd }
        let suspensions = suspensionIntervals().filter { $0.end >= windowStart && $0.start <= windowEnd }

        return Chart {
            drawCurrentTimeMarker()
            ForEach(tempBasals, id: \.start) { basal in
                RectangleMark(
                    xStart: .value("start", basal.start),
                    xEnd: .value("end", basal.end),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", basal.rate)
                )
                .foregroundStyle(Color.insulin.opacity(0.3))
                .opacity(basal.isScheduled ? 0.5 : 1)

                LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                    .opacity(basal.isScheduled ? 0.5 : 1)
                LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                    .opacity(basal.isScheduled ? 0.5 : 1)
            }
            ForEach(profiles, id: \.self) { profile in
                LineMark(
                    x: .value("Start Date", profile.startDate),
                    y: .value("Amount", profile.amount),
                    series: .value("profile", "profile")
                ).lineStyle(.init(lineWidth: 1.5, dash: [2, 4])).foregroundStyle(Color.insulin)
                LineMark(
                    x: .value("End Date", profile.endDate ?? state.endMarker),
                    y: .value("Amount", profile.amount),
                    series: .value("profile", "profile")
                ).lineStyle(.init(lineWidth: 1.5, dash: [2, 4])).foregroundStyle(Color.insulin)
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
        // the bottom pane carries the hour labels for the whole stack
        .chartXAxis { basalChartXAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... basalDomainMax)
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
                        .foregroundStyle(Color.insulin)
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
                        .fill(Color.orange)
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
