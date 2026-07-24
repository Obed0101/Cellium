import Foundation

public enum CyclePlanMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case weeklyBudget
    case targetDate
}

public struct CyclePlanConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var mode: CyclePlanMode
    public var weeklyEquivalentCycleBudget: Double
    public var targetDate: Date?
    public var targetCycleCount: Int?
    public var alertsEnabled: Bool

    public init(
        enabled: Bool = true,
        mode: CyclePlanMode = .automatic,
        weeklyEquivalentCycleBudget: Double = 7,
        targetDate: Date? = nil,
        targetCycleCount: Int? = nil,
        alertsEnabled: Bool = true
    ) {
        self.enabled = enabled
        self.mode = mode
        self.weeklyEquivalentCycleBudget = Self.validBudget(weeklyEquivalentCycleBudget)
        self.targetDate = targetDate
        self.targetCycleCount = targetCycleCount.flatMap { $0 >= 0 ? $0 : nil }
        self.alertsEnabled = alertsEnabled
    }

    private static func validBudget(_ value: Double) -> Double {
        guard value.isFinite else { return 7 }
        return min(100, max(0.1, value))
    }
}

public enum CyclePaceComparison: String, Codable, CaseIterable, Sendable {
    case lower
    case usual
    case higher
    case insufficientData
}

public enum CyclePaceStatus: String, Codable, CaseIterable, Sendable {
    case onTrack
    case elevated
    case high
    case insufficientData
}

public enum CycleUsageConfidence: String, Codable, CaseIterable, Sendable {
    case unavailable
    case low
    case medium
    case high
}

public struct CycleForecast: Codable, Equatable, Sendable {
    public let dailyEquivalentCycles: Double
    public let cyclesIn30Days: Double
    public let cyclesIn90Days: Double
    public let cyclesIn365Days: Double
    public let confidence: CycleUsageConfidence

    public init(
        dailyEquivalentCycles: Double,
        cyclesIn30Days: Double,
        cyclesIn90Days: Double,
        cyclesIn365Days: Double,
        confidence: CycleUsageConfidence
    ) {
        self.dailyEquivalentCycles = max(0, dailyEquivalentCycles)
        self.cyclesIn30Days = max(0, cyclesIn30Days)
        self.cyclesIn90Days = max(0, cyclesIn90Days)
        self.cyclesIn365Days = max(0, cyclesIn365Days)
        self.confidence = confidence
    }
}

public struct CycleUsageSummary: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let currentCycleCount: Int?
    public let todayEquivalentCycles: Double
    public let rolling24HourEquivalentCycles: Double
    public let weekEquivalentCycles: Double
    public let todayHardwareCycleDelta: Int
    public let rolling24HourHardwareCycleDelta: Int
    public let weekHardwareCycleDelta: Int
    public let baselineEquivalentCyclesAtCurrentTime: Double?
    public let baselineDayCount: Int
    public let comparison: CyclePaceComparison
    public let projectedTodayEquivalentCycles: Double?
    public let projectedWeekEquivalentCycles: Double?
    public let weeklyBudget: Double?
    public let status: CyclePaceStatus
    public let confidence: CycleUsageConfidence
    public let forecast: CycleForecast?
    public let observedSecondsToday: TimeInterval
    public let gapSecondsToday: TimeInterval

    public var todayUsagePercent: Double {
        todayEquivalentCycles * 100
    }

    public var isActionableHighPace: Bool {
        status == .high
    }

    public init(
        generatedAt: Date,
        currentCycleCount: Int?,
        todayEquivalentCycles: Double,
        rolling24HourEquivalentCycles: Double,
        weekEquivalentCycles: Double,
        todayHardwareCycleDelta: Int,
        rolling24HourHardwareCycleDelta: Int,
        weekHardwareCycleDelta: Int,
        baselineEquivalentCyclesAtCurrentTime: Double?,
        baselineDayCount: Int,
        comparison: CyclePaceComparison,
        projectedTodayEquivalentCycles: Double?,
        projectedWeekEquivalentCycles: Double?,
        weeklyBudget: Double?,
        status: CyclePaceStatus,
        confidence: CycleUsageConfidence,
        forecast: CycleForecast?,
        observedSecondsToday: TimeInterval,
        gapSecondsToday: TimeInterval
    ) {
        self.generatedAt = generatedAt
        self.currentCycleCount = currentCycleCount
        self.todayEquivalentCycles = max(0, todayEquivalentCycles)
        self.rolling24HourEquivalentCycles = max(0, rolling24HourEquivalentCycles)
        self.weekEquivalentCycles = max(0, weekEquivalentCycles)
        self.todayHardwareCycleDelta = max(0, todayHardwareCycleDelta)
        self.rolling24HourHardwareCycleDelta = max(0, rolling24HourHardwareCycleDelta)
        self.weekHardwareCycleDelta = max(0, weekHardwareCycleDelta)
        self.baselineEquivalentCyclesAtCurrentTime = baselineEquivalentCyclesAtCurrentTime
        self.baselineDayCount = max(0, baselineDayCount)
        self.comparison = comparison
        self.projectedTodayEquivalentCycles = projectedTodayEquivalentCycles
        self.projectedWeekEquivalentCycles = projectedWeekEquivalentCycles
        self.weeklyBudget = weeklyBudget
        self.status = status
        self.confidence = confidence
        self.forecast = forecast
        self.observedSecondsToday = max(0, observedSecondsToday)
        self.gapSecondsToday = max(0, gapSecondsToday)
    }
}

public enum CycleBudgetEngine {
    public static func summarize(
        quarterHourBuckets: [CycleUsageBucket],
        dailyBuckets: [CycleUsageBucket],
        currentCycleCount: Int?,
        configuration: CyclePlanConfiguration,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> CycleUsageSummary {
        let quarterHours = quarterHourBuckets
            .filter { $0.resolution == .quarterHour && $0.bucketStart <= now }
        let days = dailyBuckets
            .filter { $0.resolution == .day && $0.bucketStart <= now }
        let todayStart = calendar.startOfDay(for: now)
        let today = days.first { calendar.isDate($0.bucketStart, inSameDayAs: now) }
            ?? combinedBucket(
                quarterHours.filter { $0.bucketStart >= todayStart },
                resolution: .day,
                start: todayStart
            )
        let rollingStart = now.addingTimeInterval(-86_400)
        let rollingBuckets = quarterHours.filter { $0.bucketStart >= rollingStart }
        let rolling24EFC = rollingBuckets.reduce(0) { $0 + $1.equivalentCycles }
        let rolling24Hardware = rollingBuckets.reduce(0) { $0 + $1.hardwareCycleDelta }

        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let weekStart = weekInterval?.start
            ?? calendar.date(byAdding: .day, value: -6, to: todayStart)
            ?? todayStart
        let weekBuckets = days.filter { $0.bucketStart >= weekStart }
        let weekEFC = weekBuckets.reduce(0) { $0 + $1.equivalentCycles }
        let weekHardware = weekBuckets.reduce(0) { $0 + $1.hardwareCycleDelta }

        let baselineValues = sameTimeBaselineValues(
            quarterHourBuckets: quarterHours,
            now: now,
            calendar: calendar
        )
        let baseline = median(baselineValues)
        let comparison = comparison(
            today: today.equivalentCycles,
            baseline: baseline,
            baselineDayCount: baselineValues.count
        )
        let confidence: CycleUsageConfidence
        if quarterHours.isEmpty && days.isEmpty {
            confidence = .unavailable
        } else if baselineValues.count >= 7 {
            confidence = .high
        } else if baselineValues.count >= 3 {
            confidence = .medium
        } else {
            confidence = .low
        }

        let elapsedToday = max(0, now.timeIntervalSince(todayStart))
        let projectedToday: Double?
        if today.observedSeconds >= 7_200, elapsedToday >= 7_200 {
            let fraction = min(1, max(1.0 / 12.0, elapsedToday / 86_400))
            projectedToday = today.equivalentCycles / fraction
        } else {
            projectedToday = nil
        }

        let weeklyBudget = budget(
            configuration: configuration,
            currentCycleCount: currentCycleCount,
            now: now
        )
        let elapsedWeek = max(0, now.timeIntervalSince(weekStart))
        let projectedWeek: Double?
        if today.observedSeconds >= 7_200, elapsedWeek >= 7_200 {
            let weekFraction = min(1, max(1.0 / 84.0, elapsedWeek / (7 * 86_400)))
            projectedWeek = weekEFC / weekFraction
        } else {
            projectedWeek = nil
        }

        let budgetRatio: Double? = {
            guard let weeklyBudget, weeklyBudget > 0, let projectedWeek else { return nil }
            return projectedWeek / weeklyBudget
        }()
        let status: CyclePaceStatus
        // The personal baseline describes context; it must not turn a small
        // absolute amount of use into an alert. A user can be above their
        // usual pace while still using only a normal fraction of one EFC.
        let absoluteHighPace = rolling24EFC >= 2
            || rolling24Hardware >= 2
            || (budgetRatio ?? 0) >= 1.5 && confidence != .low && confidence != .unavailable
        let absoluteElevatedPace = today.equivalentCycles > 0.20
            || rolling24EFC > 0.20
            || (budgetRatio ?? 0) > 1

        if absoluteHighPace {
            status = .high
        } else if absoluteElevatedPace {
            status = .elevated
        } else if confidence == .unavailable {
            status = .insufficientData
        } else {
            status = .onTrack
        }

        let forecast = CycleForecastEngine.makeForecast(
            dailyBuckets: days,
            currentDayStart: todayStart,
            provisionalDailyRate: projectedToday,
            now: now,
            calendar: calendar
        )

        return CycleUsageSummary(
            generatedAt: now,
            currentCycleCount: currentCycleCount,
            todayEquivalentCycles: today.equivalentCycles,
            rolling24HourEquivalentCycles: rolling24EFC,
            weekEquivalentCycles: weekEFC,
            todayHardwareCycleDelta: today.hardwareCycleDelta,
            rolling24HourHardwareCycleDelta: rolling24Hardware,
            weekHardwareCycleDelta: weekHardware,
            baselineEquivalentCyclesAtCurrentTime: baseline,
            baselineDayCount: baselineValues.count,
            comparison: comparison,
            projectedTodayEquivalentCycles: projectedToday,
            projectedWeekEquivalentCycles: projectedWeek,
            weeklyBudget: weeklyBudget,
            status: configuration.enabled ? status : .onTrack,
            confidence: confidence,
            forecast: forecast,
            observedSecondsToday: today.observedSeconds,
            gapSecondsToday: today.gapSeconds
        )
    }

    private static func sameTimeBaselineValues(
        quarterHourBuckets: [CycleUsageBucket],
        now: Date,
        calendar: Calendar
    ) -> [Double] {
        let todayStart = calendar.startOfDay(for: now)
        let secondsIntoDay = now.timeIntervalSince(todayStart)
        let cutoff = calendar.date(byAdding: .day, value: -30, to: todayStart) ?? .distantPast
        let previous = quarterHourBuckets.filter {
            $0.bucketStart >= cutoff && $0.bucketStart < todayStart
        }
        let grouped = Dictionary(grouping: previous) {
            calendar.startOfDay(for: $0.bucketStart)
        }
        return grouped.compactMap { dayStart, buckets in
            let comparable = buckets.filter {
                $0.bucketStart.timeIntervalSince(dayStart) <= secondsIntoDay
            }
            let observed = comparable.reduce(0) { $0 + $1.observedSeconds }
            guard observed >= 30 * 60 else { return nil }
            return comparable.reduce(0) { $0 + $1.equivalentCycles }
        }
    }

    private static func comparison(
        today: Double,
        baseline: Double?,
        baselineDayCount: Int
    ) -> CyclePaceComparison {
        guard baselineDayCount >= 3, let baseline else { return .insufficientData }
        if baseline <= 0.01 {
            return today > 0.05 ? .higher : .usual
        }
        let ratio = today / baseline
        if ratio < 0.8 { return .lower }
        if ratio > 1.2 { return .higher }
        return .usual
    }

    private static func budget(
        configuration: CyclePlanConfiguration,
        currentCycleCount: Int?,
        now: Date
    ) -> Double? {
        guard configuration.enabled else { return nil }
        switch configuration.mode {
        case .automatic:
            return nil
        case .weeklyBudget:
            return configuration.weeklyEquivalentCycleBudget
        case .targetDate:
            guard let targetDate = configuration.targetDate,
                  let targetCycleCount = configuration.targetCycleCount,
                  let currentCycleCount,
                  targetDate > now,
                  targetCycleCount >= currentCycleCount else {
                return nil
            }
            let weeks = max(1.0 / 7.0, targetDate.timeIntervalSince(now) / (7 * 86_400))
            return Double(targetCycleCount - currentCycleCount) / weeks
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func combinedBucket(
        _ buckets: [CycleUsageBucket],
        resolution: CycleUsageResolution,
        start: Date
    ) -> CycleUsageBucket {
        CycleUsageBucket(
            resolution: resolution,
            bucketStart: start,
            sampleCount: buckets.reduce(0) { $0 + $1.sampleCount },
            observedSeconds: buckets.reduce(0) { $0 + $1.observedSeconds },
            gapSeconds: buckets.reduce(0) { $0 + $1.gapSeconds },
            dischargedMAh: buckets.reduce(0) { $0 + $1.dischargedMAh },
            dischargedWattHours: buckets.reduce(0) { $0 + $1.dischargedWattHours },
            equivalentCycles: buckets.reduce(0) { $0 + $1.equivalentCycles },
            firstCycleCount: buckets.first?.firstCycleCount,
            lastCycleCount: buckets.last?.lastCycleCount,
            hardwareCycleDelta: buckets.reduce(0) { $0 + $1.hardwareCycleDelta },
            hardwareCycleDeltaDuringGap: buckets.reduce(0) { $0 + $1.hardwareCycleDeltaDuringGap },
            cycleResetCount: buckets.reduce(0) { $0 + $1.cycleResetCount },
            quality: buckets.last?.quality ?? .unavailable,
            primaryMethod: buckets.last?.primaryMethod ?? .unavailable
        )
    }
}

public enum CycleForecastEngine {
    public static func makeForecast(
        dailyBuckets: [CycleUsageBucket],
        currentDayStart: Date,
        provisionalDailyRate: Double?,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> CycleForecast? {
        let completed = dailyBuckets
            .filter { $0.bucketStart < currentDayStart && $0.sampleCount > 0 }
            .sorted { $0.bucketStart > $1.bucketStart }
        let recentRates = completed.prefix(14).map(\.equivalentCycles)
        let dailyRate: Double
        let confidence: CycleUsageConfidence
        if recentRates.count >= 7 {
            dailyRate = median(Array(recentRates)) ?? 0
            confidence = .high
        } else if recentRates.count >= 3 {
            dailyRate = median(Array(recentRates)) ?? 0
            confidence = .medium
        } else if let provisionalDailyRate, provisionalDailyRate.isFinite {
            dailyRate = max(0, provisionalDailyRate)
            confidence = .low
        } else {
            return nil
        }
        return CycleForecast(
            dailyEquivalentCycles: dailyRate,
            cyclesIn30Days: dailyRate * 30,
            cyclesIn90Days: dailyRate * 90,
            cyclesIn365Days: dailyRate * 365,
            confidence: confidence
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
