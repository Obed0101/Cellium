import XCTest
@testable import CelliumCore

final class CycleUsageTests: XCTestCase {
    func testIntegratesCurrentIntoEquivalentCyclesBeyondOneHundredPercent() {
        var tracker = CycleUsageTracker(calendar: utcCalendar)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0...15 {
            _ = tracker.ingest(sample(
                at: start.addingTimeInterval(Double(index) * 300),
                instantCurrent: -5_000,
                maximumCapacity: 5_000,
                cycleCount: 150
            ))
        }

        let day = tracker.state.currentDay
        XCTAssertEqual(day?.equivalentCycles ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertEqual(day?.usagePercent ?? 0, 125, accuracy: 0.01)
        XCTAssertEqual(day?.dischargedMAh ?? 0, 6_250, accuracy: 0.1)
        XCTAssertEqual(day?.quality, .measured)
        XCTAssertEqual(day?.primaryMethod, .instantCurrent)
    }

    func testTracksHardwareCycleChangesSeparatelyFromEFC() {
        var tracker = CycleUsageTracker(calendar: utcCalendar)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        _ = tracker.ingest(sample(at: start, instantCurrent: -1_000, cycleCount: 150))
        _ = tracker.ingest(sample(at: start.addingTimeInterval(300), instantCurrent: -1_000, cycleCount: 152))

        let day = tracker.state.currentDay
        XCTAssertEqual(day?.hardwareCycleDelta, 2)
        XCTAssertEqual(day?.hardwareCycleDeltaDuringGap, 0)
        XCTAssertLessThan(day?.equivalentCycles ?? 1, 0.1)
    }

    func testMarksLongGapAndCycleChangeAsUncertain() {
        var tracker = CycleUsageTracker(maximumContinuityGap: 300, calendar: utcCalendar)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        _ = tracker.ingest(sample(at: start, instantCurrent: -5_000, cycleCount: 150))
        _ = tracker.ingest(sample(at: start.addingTimeInterval(900), instantCurrent: -5_000, cycleCount: 152))

        let day = tracker.state.currentDay
        XCTAssertEqual(day?.equivalentCycles, 0)
        XCTAssertEqual(day?.gapSeconds, 900)
        XCTAssertEqual(day?.hardwareCycleDelta, 2)
        XCTAssertEqual(day?.hardwareCycleDeltaDuringGap, 2)
    }

    func testCycleCounterDecreaseRecordsResetWithoutNegativeDelta() {
        var tracker = CycleUsageTracker(calendar: utcCalendar)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        _ = tracker.ingest(sample(at: start, instantCurrent: 0, cycleCount: 500))
        _ = tracker.ingest(sample(at: start.addingTimeInterval(60), instantCurrent: 0, cycleCount: 2))

        XCTAssertEqual(tracker.state.currentDay?.hardwareCycleDelta, 0)
        XCTAssertEqual(tracker.state.currentDay?.cycleResetCount, 1)
    }

    func testFallsBackToCapacityWhenCurrentIsUnavailable() {
        var tracker = CycleUsageTracker(calendar: utcCalendar)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        _ = tracker.ingest(sample(
            at: start,
            instantCurrent: nil,
            rawCurrentCapacity: 5_000,
            maximumCapacity: 5_000
        ))
        _ = tracker.ingest(sample(
            at: start.addingTimeInterval(300),
            instantCurrent: nil,
            rawCurrentCapacity: 4_500,
            maximumCapacity: 5_000
        ))

        XCTAssertEqual(tracker.state.currentDay?.equivalentCycles ?? 0, 0.1, accuracy: 0.0001)
        XCTAssertEqual(tracker.state.currentDay?.primaryMethod, .capacity)
        XCTAssertEqual(tracker.state.currentDay?.quality, .estimated)
    }

    func testBudgetEngineMarksTwoCyclesInTwentyFourHoursHigh() {
        let now = Date(timeIntervalSince1970: 1_700_050_000)
        let start = now.addingTimeInterval(-3_600)
        let buckets = [
            usageBucket(at: start, efc: 1, hardwareDelta: 1),
            usageBucket(at: start.addingTimeInterval(900), efc: 1, hardwareDelta: 1)
        ]

        let summary = CycleBudgetEngine.summarize(
            quarterHourBuckets: buckets,
            dailyBuckets: [],
            currentCycleCount: 153,
            configuration: CyclePlanConfiguration(),
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(summary.status, .high)
        XCTAssertEqual(summary.rolling24HourEquivalentCycles, 2, accuracy: 0.0001)
        XCTAssertEqual(summary.rolling24HourHardwareCycleDelta, 2)
        XCTAssertTrue(summary.isActionableHighPace)
    }

    func testBudgetEngineComparesTodayOnlyAfterThreeBaselineDays() {
        let calendar = utcCalendar
        let todayStart = Date(timeIntervalSince1970: 1_700_006_400)
        let now = todayStart.addingTimeInterval(12 * 3_600)
        var buckets: [CycleUsageBucket] = []
        for offset in 1...3 {
            buckets.append(usageBucket(
                at: calendar.date(byAdding: .day, value: -offset, to: todayStart)!.addingTimeInterval(8 * 3_600),
                efc: 0.5,
                observedSeconds: 3_600
            ))
        }
        buckets.append(usageBucket(
            at: todayStart.addingTimeInterval(8 * 3_600),
            efc: 0.7,
            observedSeconds: 3_600
        ))

        let summary = CycleBudgetEngine.summarize(
            quarterHourBuckets: buckets,
            dailyBuckets: [],
            currentCycleCount: 153,
            configuration: CyclePlanConfiguration(),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.baselineDayCount, 3)
        XCTAssertEqual(summary.baselineEquivalentCyclesAtCurrentTime ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(summary.comparison, .higher)
        XCTAssertEqual(summary.status, .elevated)
        XCTAssertEqual(summary.confidence, .medium)
    }

    func testBudgetEngineKeepsTwentyPercentOrLessOnTrackDespiteHigherBaseline() {
        let calendar = utcCalendar
        let todayStart = Date(timeIntervalSince1970: 1_700_006_400)
        let now = todayStart.addingTimeInterval(12 * 3_600)
        var buckets: [CycleUsageBucket] = []
        for offset in 1...3 {
            buckets.append(usageBucket(
                at: calendar.date(byAdding: .day, value: -offset, to: todayStart)!.addingTimeInterval(8 * 3_600),
                efc: 0.1,
                observedSeconds: 3_600
            ))
        }
        buckets.append(usageBucket(
            at: todayStart.addingTimeInterval(8 * 3_600),
            efc: 0.17,
            observedSeconds: 3_600
        ))

        let summary = CycleBudgetEngine.summarize(
            quarterHourBuckets: buckets,
            dailyBuckets: [],
            currentCycleCount: 153,
            configuration: CyclePlanConfiguration(),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.comparison, .higher)
        XCTAssertEqual(summary.status, .onTrack)
    }

    func testBudgetEngineRaisesElevatedStatusAboveTwentyPercentAbsoluteUse() {
        let now = Date(timeIntervalSince1970: 1_700_050_000)
        let summary = CycleBudgetEngine.summarize(
            quarterHourBuckets: [usageBucket(at: now.addingTimeInterval(-900), efc: 0.21)],
            dailyBuckets: [],
            currentCycleCount: 153,
            configuration: CyclePlanConfiguration(),
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(summary.status, .elevated)
    }

    func testTargetDateModeDerivesWeeklyBudget() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let configuration = CyclePlanConfiguration(
            mode: .targetDate,
            targetDate: now.addingTimeInterval(10 * 7 * 86_400),
            targetCycleCount: 200
        )

        let summary = CycleBudgetEngine.summarize(
            quarterHourBuckets: [usageBucket(at: now, efc: 0.1)],
            dailyBuckets: [],
            currentCycleCount: 150,
            configuration: configuration,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(summary.weeklyBudget ?? 0, 5, accuracy: 0.0001)
    }

    func testProjectionRemainsHiddenUntilTwoObservedHours() {
        let calendar = utcCalendar
        let now = Date(timeIntervalSince1970: 1_700_049_600)
        let todayStart = calendar.startOfDay(for: now)
        let insufficient = dailyBucket(
            at: todayStart,
            efc: 0.4,
            observedSeconds: 7_199
        )

        let hidden = CycleBudgetEngine.summarize(
            quarterHourBuckets: [],
            dailyBuckets: [insufficient],
            currentCycleCount: 153,
            configuration: CyclePlanConfiguration(mode: .weeklyBudget, weeklyEquivalentCycleBudget: 3),
            now: now,
            calendar: calendar
        )
        XCTAssertNil(hidden.projectedTodayEquivalentCycles)
        XCTAssertNil(hidden.projectedWeekEquivalentCycles)

        let sufficient = dailyBucket(
            at: todayStart,
            efc: 0.4,
            observedSeconds: 7_200
        )
        let visible = CycleBudgetEngine.summarize(
            quarterHourBuckets: [],
            dailyBuckets: [sufficient],
            currentCycleCount: 153,
            configuration: CyclePlanConfiguration(mode: .weeklyBudget, weeklyEquivalentCycleBudget: 3),
            now: now,
            calendar: calendar
        )
        XCTAssertNotNil(visible.projectedTodayEquivalentCycles)
        XCTAssertNotNil(visible.projectedWeekEquivalentCycles)
    }

    func testForecastUsesMedianOfCompletedDays() {
        let calendar = utcCalendar
        let today = Date(timeIntervalSince1970: 1_700_006_400)
        let buckets = [0.2, 0.5, 0.8].enumerated().map { index, efc in
            dailyBucket(
                at: calendar.date(byAdding: .day, value: -(index + 1), to: today)!,
                efc: efc,
                observedSeconds: 8 * 3_600
            )
        }

        let forecast = CycleForecastEngine.makeForecast(
            dailyBuckets: buckets,
            currentDayStart: today,
            provisionalDailyRate: nil,
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(forecast?.dailyEquivalentCycles ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(forecast?.cyclesIn30Days ?? 0, 15, accuracy: 0.0001)
        XCTAssertEqual(forecast?.confidence, .medium)
    }

    func testConfidentProjectionAtOneHundredFiftyPercentOfBudgetIsHigh() {
        let calendar = utcCalendar
        let now = Date(timeIntervalSince1970: 1_700_049_600)
        let todayStart = calendar.startOfDay(for: now)
        var quarterHours = (1...3).map { offset in
            usageBucket(
                at: calendar.date(byAdding: .day, value: -offset, to: todayStart)!
                    .addingTimeInterval(3_600),
                efc: 0.2,
                observedSeconds: 1_800
            )
        }
        quarterHours.append(usageBucket(
            at: todayStart.addingTimeInterval(3_600),
            efc: 0.4,
            observedSeconds: 7_200
        ))

        let summary = CycleBudgetEngine.summarize(
            quarterHourBuckets: quarterHours,
            dailyBuckets: [dailyBucket(at: todayStart, efc: 0.8, observedSeconds: 7_200)],
            currentCycleCount: 153,
            configuration: CyclePlanConfiguration(
                mode: .weeklyBudget,
                weeklyEquivalentCycleBudget: 0.5
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.confidence, .medium)
        XCTAssertGreaterThanOrEqual(summary.projectedWeekEquivalentCycles ?? 0, 0.75)
        XCTAssertEqual(summary.status, .high)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func sample(
        at date: Date,
        instantCurrent: Int64?,
        rawCurrentCapacity: Int = 5_000,
        maximumCapacity: Int = 5_000,
        cycleCount: Int = 150
    ) -> BatterySample {
        BatterySample(
            battery: BatterySnapshot(
                timestamp: date,
                chargePercent: Int(Double(rawCurrentCapacity) / Double(maximumCapacity) * 100),
                currentCapacityMAh: rawCurrentCapacity,
                nominalChargeCapacityMAh: maximumCapacity,
                designCapacityMAh: 5_200,
                rawCurrentCapacityMAh: rawCurrentCapacity,
                rawMaxCapacityMAh: maximumCapacity,
                voltageMillivolts: 12_000,
                amperageMilliamps: instantCurrent,
                instantAmperageMilliamps: instantCurrent,
                cycleCount: cycleCount,
                designCycleCount: 1_000,
                isCharging: false,
                externalPowerConnected: false,
                sourceQuality: .measured,
                powerSourceState: .battery
            )
        )
    }

    private func usageBucket(
        at date: Date,
        efc: Double,
        observedSeconds: TimeInterval = 900,
        hardwareDelta: Int = 0
    ) -> CycleUsageBucket {
        CycleUsageBucket(
            resolution: .quarterHour,
            bucketStart: date,
            sampleCount: 2,
            observedSeconds: observedSeconds,
            equivalentCycles: efc,
            hardwareCycleDelta: hardwareDelta,
            quality: .measured,
            primaryMethod: .instantCurrent
        )
    }

    private func dailyBucket(
        at date: Date,
        efc: Double,
        observedSeconds: TimeInterval,
        hardwareDelta: Int = 0
    ) -> CycleUsageBucket {
        CycleUsageBucket(
            resolution: .day,
            bucketStart: date,
            sampleCount: 2,
            observedSeconds: observedSeconds,
            equivalentCycles: efc,
            hardwareCycleDelta: hardwareDelta,
            quality: .measured,
            primaryMethod: .instantCurrent
        )
    }
}
