import SwiftUI

// Detailed Home style (`HomeChartStyle.detailed`): a large glucose value with delta and
// eventual glucose, loop and pump cards, a row with IOB / COB / basal, then one chart card.
// Like the stock Home it fits the screen without scrolling: the glucose plot takes what the
// fixed rows leave. Kept apart from the stock header so the `.trio` layout stays as upstream
// ships it. Presentation only.

enum DetailedHomeLayout {
    static let topPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 12
    static let glucoseRowHeight: CGFloat = 64
    /// Between the glucose row and the loop and pump cards.
    static let glucoseRowSpacing: CGFloat = 8
    static let cardHeight: CGFloat = 90
    static let statsHeight: CGFloat = 52
    static let horizontalPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 10
    /// Top of the chart card.
    static var chartCardTop: CGFloat {
        topPadding + glucoseRowHeight + glucoseRowSpacing + cardHeight + statsHeight + 2 * sectionSpacing
    }
}

/// Bolus and carbs entered at a selected chart point.
struct ChartSelectionTreatments {
    let bolus: Decimal?
    let carbs: Decimal?
}

extension ChartSelectionLookup {
    /// Sums the boluses and carb entries inside the selection window, so each entry belongs
    /// to exactly one 5-minute scrub step.
    static func treatments(
        at date: Date,
        insulin: [PumpEventStored],
        carbs: [CarbEntryStored]
    ) -> ChartSelectionTreatments {
        let lower = date.addingTimeInterval(-window)
        let upper = date.addingTimeInterval(window)
        func inWindow(_ entryDate: Date?) -> Bool {
            guard let entryDate else { return false }
            return entryDate >= lower && entryDate < upper
        }

        let boluses = insulin
            .filter { inWindow($0.timestamp) }
            .compactMap { ($0.bolus?.amount).map { $0.decimalValue } }
            .filter { $0 != 0 }
        let carbAmounts = carbs
            .filter { inWindow($0.date) && $0.carbs > 0 }
            .map { Decimal($0.carbs) }

        return ChartSelectionTreatments(
            bolus: boluses.isEmpty ? nil : boluses.reduce(0, +),
            carbs: carbAmounts.isEmpty ? nil : carbAmounts.reduce(0, +)
        )
    }
}

extension Home.RootView {
    @ViewBuilder func detailedDashboardContent(_ geo: GeometryProxy) -> some View {
        VStack(spacing: DetailedHomeLayout.sectionSpacing) {
            Group {
                if let apsManager = state.apsManager, let bluetoothManager = apsManager.bluetoothManager,
                   bluetoothManager.bluetoothAuthorization != .authorized
                {
                    BluetoothRequiredView()
                } else {
                    detailedHeader(width: geo.size.width)
                }
            }
            .frame(
                height: DetailedHomeLayout.glucoseRowHeight + DetailedHomeLayout.glucoseRowSpacing
                    + DetailedHomeLayout.cardHeight
            )

            detailedStatsCard
                .padding(.horizontal, DetailedHomeLayout.horizontalPadding)

            detailedMainChart(geo: geo)
        }
        .padding(.top, DetailedHomeLayout.topPadding)
        .padding(.bottom, DetailedHomeLayout.bottomPadding)
        .frame(maxWidth: .infinity)
        .task(id: chartSelection) { await updateChartReadout() }
    }

    /// The chart card reaches down to the bottom controls; its glucose plot is the only
    /// flexible part, so nothing below it needs scrolling.
    @ViewBuilder private func detailedMainChart(geo: GeometryProxy) -> some View {
        let glucosePlotHeight = max(
            geo.size.height - detailedBottomZoneHeight - DetailedHomeLayout.chartCardTop
                - DetailedChartLayout.fixedHeight - DetailedHomeLayout.bottomPadding,
            DetailedChartLayout.minGlucosePlotHeight
        )
        MainChartView(
            geo: geo,
            chartHeight: glucosePlotHeight,
            units: state.units,
            highGlucose: state.highGlucose,
            lowGlucose: state.lowGlucose,
            currentGlucoseTarget: state.currentGlucoseTarget,
            glucoseColorScheme: state.glucoseColorScheme,
            displayXgridLines: state.displayXgridLines,
            displayYgridLines: state.displayYgridLines,
            thresholdLines: state.thresholdLines,
            state: state,
            chartStyle: .detailed,
            selection: $chartSelection
        )
    }

    // MARK: - Header

    @ViewBuilder private func detailedHeader(width: CGFloat) -> some View {
        let inner = width - 2 * DetailedHomeLayout.horizontalPadding - DetailedHomeLayout.cardSpacing
        VStack(spacing: DetailedHomeLayout.glucoseRowSpacing) {
            HStack(spacing: 12) {
                detailedGlucoseRow
                alarmsPill
            }
            .frame(height: DetailedHomeLayout.glucoseRowHeight)

            HStack(spacing: DetailedHomeLayout.cardSpacing) {
                detailedLoopCard
                    .frame(width: max(inner / 3, 0))
                detailedPumpCard
                    .frame(maxWidth: .infinity)
            }
            .frame(height: DetailedHomeLayout.cardHeight)
        }
        .padding(.horizontal, DetailedHomeLayout.horizontalPadding)
    }

    private var detailedGlucoseRow: some View {
        DetailedGlucoseRow(
            units: state.units,
            cgmAvailable: state.cgmAvailable,
            glucose: state.latestTwoGlucoseValues,
            cgmStatus: state.cgmDisplayState,
            highGlucose: state.highGlucose,
            lowGlucose: state.lowGlucose,
            eventualGlucose: (state.enactedAndNonEnactedDeterminations.first?.eventualBG).map { $0 as Decimal },
            timerDate: state.timerDate
        )
        // same gestures as the stock glucose bobble
        .contentShape(Rectangle())
        .onTapGesture {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .onLongPressGesture {
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            showSnoozeSheet = true
        }
        .accessibilityAction {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .accessibilityAction(named: Text("Snooze alerts")) {
            showSnoozeSheet = true
        }
    }

    private var detailedLoopCard: some View {
        DetailedLoopCard(
            dosingMode: state.dosingMode,
            timerDate: state.timerDate,
            isLooping: state.isLooping,
            lastLoopDate: state.lastLoopDate,
            manualTempBasal: state.manualTempBasal,
            hasDeviceIssue: state.hasDeviceIssue,
            determination: state.determinationsFromPersistence
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.isLoopStatusPresented = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(String(localized: "Opens loop status", comment: "Accessibility hint")))
        .accessibilityAction { state.isLoopStatusPresented = true }
    }

    private var detailedPumpCard: some View {
        DetailedPumpCard(
            reservoir: state.reservoir,
            name: state.pumpName,
            expiresAtDate: state.pumpExpiresAtDate,
            activatedAtDate: state.pumpActivatedAtDate,
            timerDate: state.timerDate,
            pumpStatusHighlightMessage: state.pumpStatusHighlightMessage,
            battery: state.batteryFromPersistence,
            lastCommsDate: state.lastPumpCommsDate
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if state.pumpDisplayState == nil {
                showPumpSelection.toggle()
            } else {
                state.shouldDisplayPumpSetupSheet.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(
            state.pumpDisplayState == nil
                ? String(localized: "Opens pump setup", comment: "Accessibility hint")
                : String(localized: "Opens pump settings", comment: "Accessibility hint")
        ))
        .accessibilityAction {
            if state.pumpDisplayState == nil {
                showPumpSelection.toggle()
            } else {
                state.shouldDisplayPumpSetupSheet.toggle()
            }
        }
    }

    // MARK: - Stats card

    /// IOB / COB / basal in three equal columns.
    private var detailedStatsCard: some View {
        let palette = DetailedPalette(colorScheme)
        let determination = state.enactedAndNonEnactedDeterminations.first
        let iob = Formatter.decimalFormatterWithTwoFractionDigits.string(from: state.currentIOB as NSNumber) ?? "0"
        let cob = Formatter.integerFormatter.string(from: NSNumber(value: determination?.cob ?? 0)) ?? "0"
        let basal = (state.tempBasals.last?.tempBasal?.rate).map {
            Formatter.decimalFormatterWithTwoFractionDigits.string(from: $0) ?? "\($0)"
        }

        return HStack(spacing: 0) {
            statColumn(
                String(localized: "IOB"),
                value: iob,
                unit: String(localized: "U", comment: "Insulin unit"),
                tint: palette.insulin,
                palette
            )
            statDivider(palette)
            statColumn(
                String(localized: "COB"),
                value: cob,
                unit: String(localized: "g", comment: "gram of carbs"),
                tint: palette.carbs,
                palette
            )
            statDivider(palette)
            statColumn(
                String(localized: "Current basal", comment: "Detailed Home stats row title"),
                value: basal ?? "--",
                unit: String(localized: "U/hr", comment: "Insulin unit per hour abbreviation"),
                tint: palette.basal,
                palette
            )
        }
        .frame(height: DetailedHomeLayout.statsHeight)
        .detailedCard(palette, cornerRadius: 15)
    }

    /// Label above; value and unit on one baseline.
    private func statColumn(
        _ title: String,
        value: String,
        unit: String,
        tint: Color,
        _ palette: DetailedPalette
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func statDivider(_ palette: DetailedPalette) -> some View {
        Rectangle()
            .fill(palette.border)
            .frame(width: 0.65, height: 28)
    }

    // MARK: - Chart readout

    /// Press-and-hold readout, over the glucose row at the top of the screen.
    @ViewBuilder func detailedChartReadout() -> some View {
        if let readoutDate = chartReadoutDate,
           let selectedGlucose = ChartSelectionLookup.glucose(at: readoutDate, in: state.glucoseFromPersistence)
        {
            ChartSelectionRow(
                selectedGlucose: selectedGlucose,
                determination: nil,
                units: state.units,
                highGlucose: state.highGlucose,
                lowGlucose: state.lowGlucose,
                currentGlucoseTarget: state.currentGlucoseTarget,
                glucoseColorScheme: state.glucoseColorScheme,
                isSmoothingEnabled: state.settingsManager.settings.smoothGlucose,
                treatments: ChartSelectionLookup.treatments(
                    at: readoutDate,
                    insulin: state.insulinFromPersistence,
                    carbs: state.carbsFromPersistence
                )
            )
            .padding(.horizontal)
            .frame(height: HomeLayout.mealSlotHeight)
            .detailedCard(DetailedPalette(colorScheme), cornerRadius: 17)
            .padding(.horizontal, DetailedHomeLayout.horizontalPadding)
            .padding(.top, DetailedHomeLayout.topPadding)
            .opacity(isChartReadoutVisible ? 1 : 0)
            .allowsHitTesting(false)
            .animation(ChartSelectionLookup.readoutFade, value: isChartReadoutVisible)
        }
    }

    // MARK: - Bottom controls

    /// Adjustment / bolus slot, only while an override, a temp target or a bolus is running.
    private var detailedShowsAdjustmentSlot: Bool {
        state.bolusProgress != nil || overrideString != nil || tempTargetString != nil
    }

    /// Alert banners of the multi-use panel; its stats face is the Time in Range pill here.
    private var detailedShowsAlertBanner: Bool {
        multiUsePanelState != .stats
    }

    var detailedBottomZoneHeight: CGFloat {
        let showsSlot = detailedShowsAdjustmentSlot
        let showsBanner = detailedShowsAlertBanner
        guard showsSlot || showsBanner else { return 0 }
        return (showsSlot ? HomeLayout.bottomPanelHeight : 0) + (showsBanner ? HomeLayout.statsBannerHeight : 0)
            + ((showsSlot && showsBanner) ? 3 : 2) * HomeLayout.bottomZonePadding
    }

    /// Same panels as `bottomControls`, shown only when they have something to say.
    @ViewBuilder func detailedBottomControls() -> some View {
        let showsSlot = detailedShowsAdjustmentSlot
        let showsBanner = detailedShowsAlertBanner
        VStack(spacing: HomeLayout.bottomZonePadding) {
            if showsSlot {
                Group {
                    if let progress = state.bolusProgress {
                        bolusView(progress)
                    } else {
                        adjustmentView()
                    }
                }
                .frame(height: HomeLayout.bottomPanelHeight)
            }

            if showsBanner {
                multiUsePanel()
                    .frame(height: HomeLayout.statsBannerHeight)
            }
        }
        .padding(.vertical, showsSlot || showsBanner ? HomeLayout.bottomZonePadding : 0)
        .animation(.easeInOut(duration: 0.2), value: showsSlot)
    }
}

// MARK: - Glucose row

struct DetailedGlucoseRow: View {
    let units: GlucoseUnits
    let cgmAvailable: Bool
    /// last two readings, oldest first
    let glucose: [GlucoseStored]
    let cgmStatus: CgmDisplayState?
    let highGlucose: Decimal
    let lowGlucose: Decimal
    /// eventual glucose of the latest determination, mg/dL
    let eventualGlucose: Decimal?
    /// ticks the minutes-ago caption
    let timerDate: Date

    @Environment(\.colorScheme) var colorScheme

    /// Same freshness gate as the stock bobble: older readings are masked.
    private var freshReading: GlucoseStored? {
        guard let last = glucose.last, let date = last.date, timerDate.timeIntervalSince(date) < 12 * 60 else {
            return nil
        }
        return last
    }

    private var deltaString: String? {
        guard glucose.count >= 2, let last = glucose.last, let first = glucose.first else { return nil }
        var delta = Decimal(last.glucose) - Decimal(first.glucose)
        if units == .mmolL { delta = delta.asMmolL }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = units == .mmolL ? 1 : 0
        formatter.maximumFractionDigits = units == .mmolL ? 1 : 0
        formatter.positivePrefix = "+"
        return formatter.string(from: delta as NSNumber)
    }

    private var predictedCaption: String {
        String(
            localized: "detailed.predicted",
            defaultValue: "predicted",
            comment: "Detailed Home glucose row: caption above the eventual glucose forecast"
        )
    }

    /// Eventual glucose in the display unit, colored by the same high / low thresholds as
    /// the glucose value (ink when in range).
    private var eventualString: (text: String, color: Color)? {
        guard let eventualGlucose else { return nil }
        let palette = DetailedPalette(colorScheme)
        let color = eventualGlucose < lowGlucose ? palette.low : (eventualGlucose > highGlucose ? palette.high : palette.ink)
        let text = units == .mgdL ? eventualGlucose.description : eventualGlucose.formattedAsMmolL
        return (text, color)
    }

    /// Trend arrow symbol and how many times to repeat it (double/triple arrows).
    private var trendArrow: (symbol: String, count: Int)? {
        switch freshReading?.directionEnum {
        case .tripleUp: return ("arrow.up", 3)
        case .doubleUp: return ("arrow.up", 2)
        case .singleUp: return ("arrow.up", 1)
        case .fortyFiveUp: return ("arrow.up.right", 1)
        case .flat: return ("arrow.right", 1)
        case .fortyFiveDown: return ("arrow.down.right", 1)
        case .singleDown: return ("arrow.down", 1)
        case .doubleDown: return ("arrow.down", 2)
        case .tripleDown: return ("arrow.down", 3)
        default: return nil
        }
    }

    var body: some View {
        let palette = DetailedPalette(colorScheme)
        if !cgmAvailable {
            HStack(spacing: 10) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill").font(.title2)
                Text("Add CGM").font(.headline)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        } else if let reading = freshReading {
            let mgdL = Decimal(reading.glucose)
            let color = mgdL > highGlucose ? palette.high : (mgdL < lowGlucose ? palette.low : palette.glucose)
            let value = mgdL == 400
                ? "HIGH"
                : (units == .mgdL ? mgdL.description : mgdL.formattedAsMmolL)

            HStack(alignment: .center, spacing: 16) {
                HStack(alignment: .center, spacing: 8) {
                    Text(value)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if let arrow = trendArrow {
                        HStack(spacing: -6) {
                            ForEach(0 ..< arrow.count, id: \.self) { _ in
                                Image(systemName: arrow.symbol)
                            }
                        }
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(color)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    if let deltaString {
                        Text(deltaString)
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.ink)
                    }
                    Text(units.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.muted)
                }
                .fixedSize()

                if let eventual = eventualString {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(predictedCaption)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.muted)
                        Text(eventual.text)
                            .font(.system(size: 19, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(eventual.color)
                    }
                    .fixedSize()
                }

                Spacer(minLength: 4)

                Text(TimeAgoFormatter.minutesAgo(from: reading.date))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(
                [
                    String(localized: "Glucose", comment: "Accessibility: glucose label") + " \(value) \(units.rawValue)",
                    deltaString.map { String(localized: "delta", comment: "Accessibility: glucose delta") + " \($0)" },
                    eventualString.map { predictedCaption + " \($0.text) \(units.rawValue)" },
                    TimeAgoFormatter.minutesAgoAccessible(from: reading.date)
                ].compactMap { $0 }.joined(separator: ", ")
            ))
        } else {
            HStack(spacing: 10) {
                Text(verbatim: "--")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.muted)
                if let status = cgmStatus, !status.localizedMessage.isEmpty {
                    Text(status.localizedMessage.replacingOccurrences(of: "\n", with: " "))
                        .font(.callout).fontWeight(.semibold)
                        .foregroundStyle(status.status == .critical ? Color.loopRed : Color.orange)
                        .lineLimit(2)
                }
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(localized: "Glucose unavailable", comment: "Accessibility: no fresh glucose")))
        }
    }
}

// MARK: - Loop card

/// Loop state card: ring colored like `LoopView` (same rules, reused), minutes since the last
/// loop in the middle, dosing mode and last-loop caption below.
struct DetailedLoopCard: View {
    let dosingMode: DosingMode
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool
    let hasDeviceIssue: Bool
    let determination: [OrefDetermination]

    @Environment(\.colorScheme) var colorScheme

    private var color: Color {
        LoopView.ringColor(
            automation: dosingMode.automation,
            manualTempBasal: manualTempBasal,
            hasDeviceIssue: hasDeviceIssue,
            hasEnactedDetermination: determination.first?.timestamp != nil,
            secondsSinceLastLoop: timerDate.timeIntervalSince(lastLoopDate)
        )
    }

    private var ringGap: CGFloat {
        LoopView.ringGap(automation: dosingMode.automation, manualTempBasal: manualTempBasal)
    }

    /// Minutes since the last loop, nil when unknown or older than a day.
    private var minutesSinceLoop: Int? {
        guard determination.first?.deliverAt != nil else { return nil }
        let minutes = Int(timerDate.timeIntervalSince(lastLoopDate) / 60)
        return (0 ... 1440).contains(minutes) ? minutes : nil
    }

    private var caption: String {
        if isLooping { return String(localized: "looping") }
        if manualTempBasal { return String(localized: "Manual") }
        guard let minutesSinceLoop else { return "--" }
        return "\(minutesSinceLoop) " + String(localized: "min ago")
    }

    var body: some View {
        let palette = DetailedPalette(colorScheme)
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(palette.rail, lineWidth: 3)
                if ringGap == 0 {
                    Circle().stroke(color, lineWidth: 3)
                } else {
                    Circle()
                        .trim(from: ringGap / 2, to: 0.5 - ringGap / 2)
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    Circle()
                        .trim(from: 0.5 + ringGap / 2, to: 1 - ringGap / 2)
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                if isLooping {
                    ProgressView()
                        .controlSize(.small)
                } else if !manualTempBasal, let symbol = LoopView.centerSymbol(automation: dosingMode.automation) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                } else if let minutesSinceLoop {
                    Text(verbatim: "\(minutesSinceLoop)\u{2032}")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 34, height: 34)
            .padding(.bottom, 3)

            Text(dosingMode.displayName)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .detailedCard(palette, cornerRadius: 17)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([dosingMode.displayName, caption].joined(separator: ", ")))
    }
}
