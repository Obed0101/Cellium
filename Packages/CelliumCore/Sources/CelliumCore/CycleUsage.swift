import Foundation

public enum CycleUsageResolution: String, Codable, CaseIterable, Sendable {
    case quarterHour
    case day
}

public enum CycleUsageMethod: String, Codable, CaseIterable, Sendable {
    case instantCurrent
    case averageCurrent
    case capacity
    case percentage
    case unavailable
}

public struct CycleUsageBucket: Codable, Equatable, Sendable {
    public var resolution: CycleUsageResolution
    public var bucketStart: Date
    public var sampleCount: Int
    public var observedSeconds: TimeInterval
    public var gapSeconds: TimeInterval
    public var dischargedMAh: Double
    public var dischargedWattHours: Double
    public var equivalentCycles: Double
    public var firstCycleCount: Int?
    public var lastCycleCount: Int?
    public var hardwareCycleDelta: Int
    public var hardwareCycleDeltaDuringGap: Int
    public var cycleResetCount: Int
    public var quality: SensorQuality
    public var primaryMethod: CycleUsageMethod

    public var usagePercent: Double {
        equivalentCycles * 100
    }

    public init(
        resolution: CycleUsageResolution,
        bucketStart: Date,
        sampleCount: Int = 0,
        observedSeconds: TimeInterval = 0,
        gapSeconds: TimeInterval = 0,
        dischargedMAh: Double = 0,
        dischargedWattHours: Double = 0,
        equivalentCycles: Double = 0,
        firstCycleCount: Int? = nil,
        lastCycleCount: Int? = nil,
        hardwareCycleDelta: Int = 0,
        hardwareCycleDeltaDuringGap: Int = 0,
        cycleResetCount: Int = 0,
        quality: SensorQuality = .unavailable,
        primaryMethod: CycleUsageMethod = .unavailable
    ) {
        self.resolution = resolution
        self.bucketStart = bucketStart
        self.sampleCount = max(0, sampleCount)
        self.observedSeconds = Self.finiteNonNegative(observedSeconds)
        self.gapSeconds = Self.finiteNonNegative(gapSeconds)
        self.dischargedMAh = Self.finiteNonNegative(dischargedMAh)
        self.dischargedWattHours = Self.finiteNonNegative(dischargedWattHours)
        self.equivalentCycles = Self.finiteNonNegative(equivalentCycles)
        self.firstCycleCount = firstCycleCount.flatMap { $0 >= 0 ? $0 : nil }
        self.lastCycleCount = lastCycleCount.flatMap { $0 >= 0 ? $0 : nil }
        self.hardwareCycleDelta = max(0, hardwareCycleDelta)
        self.hardwareCycleDeltaDuringGap = max(0, hardwareCycleDeltaDuringGap)
        self.cycleResetCount = max(0, cycleResetCount)
        self.quality = quality
        self.primaryMethod = primaryMethod
    }

    private static func finiteNonNegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}

public struct CycleUsageObservation: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let instantAmperageMilliamps: Int64?
    public let averageAmperageMilliamps: Int64?
    public let voltageMillivolts: Int?
    public let rawCurrentCapacityMAh: Int?
    public let rawMaxCapacityMAh: Int?
    public let currentCapacityMAh: Int?
    public let nominalChargeCapacityMAh: Int?
    public let chargePercent: Int?
    public let cycleCount: Int?
    public let isCharging: Bool

    public init(snapshot: BatterySnapshot) {
        self.timestamp = snapshot.timestamp
        self.instantAmperageMilliamps = snapshot.instantAmperageMilliamps
        self.averageAmperageMilliamps = snapshot.amperageMilliamps
        self.voltageMillivolts = snapshot.voltageMillivolts
        self.rawCurrentCapacityMAh = snapshot.rawCurrentCapacityMAh
        self.rawMaxCapacityMAh = snapshot.rawMaxCapacityMAh
        self.currentCapacityMAh = snapshot.currentCapacityMAh
        self.nominalChargeCapacityMAh = snapshot.nominalChargeCapacityMAh
        self.chargePercent = snapshot.chargePercent
        self.cycleCount = snapshot.cycleCount
        self.isCharging = snapshot.isCharging
    }
}

public struct CycleUsageTrackerState: Codable, Equatable, Sendable {
    public var lastObservation: CycleUsageObservation?
    public var currentQuarterHour: CycleUsageBucket?
    public var currentDay: CycleUsageBucket?

    public init(
        lastObservation: CycleUsageObservation? = nil,
        currentQuarterHour: CycleUsageBucket? = nil,
        currentDay: CycleUsageBucket? = nil
    ) {
        self.lastObservation = lastObservation
        self.currentQuarterHour = currentQuarterHour
        self.currentDay = currentDay
    }
}

public struct CycleUsageTracker: Sendable {
    public let maximumContinuityGap: TimeInterval
    public let calendar: Calendar
    public private(set) var state: CycleUsageTrackerState

    public init(
        maximumContinuityGap: TimeInterval = 5 * 60,
        calendar: Calendar = .autoupdatingCurrent,
        state: CycleUsageTrackerState = CycleUsageTrackerState()
    ) {
        self.maximumContinuityGap = max(1, maximumContinuityGap)
        self.calendar = calendar
        self.state = state
    }

    public mutating func ingest(_ sample: BatterySample) -> [CycleUsageBucket] {
        ingest([sample])
    }

    public mutating func ingest(_ samples: [BatterySample]) -> [CycleUsageBucket] {
        var updates: [BucketKey: CycleUsageBucket] = [:]
        let ordered = samples.sorted { $0.battery.timestamp < $1.battery.timestamp }

        for sample in ordered {
            let observation = CycleUsageObservation(snapshot: sample.battery)
            guard observation.timestamp.timeIntervalSince1970.isFinite else { continue }
            if let previous = state.lastObservation,
               observation.timestamp <= previous.timestamp {
                continue
            }

            ensureBucket(
                resolution: .quarterHour,
                at: observation.timestamp,
                updates: &updates
            )
            ensureBucket(
                resolution: .day,
                at: observation.timestamp,
                updates: &updates
            )

            let interval = state.lastObservation.map {
                Self.intervalEstimate(from: $0, to: observation, maximumGap: maximumContinuityGap)
            }
            updateCurrentBuckets(with: observation, interval: interval)
            recordCurrentBuckets(in: &updates)
            state.lastObservation = observation
        }

        return updates.values.sorted {
            if $0.bucketStart != $1.bucketStart { return $0.bucketStart < $1.bucketStart }
            return $0.resolution.rawValue < $1.resolution.rawValue
        }
    }

    private mutating func ensureBucket(
        resolution: CycleUsageResolution,
        at date: Date,
        updates: inout [BucketKey: CycleUsageBucket]
    ) {
        let start = bucketStart(for: date, resolution: resolution)
        let current = bucket(for: resolution)
        guard current?.bucketStart != start else { return }
        if let current {
            updates[BucketKey(current)] = current
        }
        setBucket(
            CycleUsageBucket(resolution: resolution, bucketStart: start),
            for: resolution
        )
    }

    private mutating func updateCurrentBuckets(
        with observation: CycleUsageObservation,
        interval: IntervalEstimate?
    ) {
        for resolution in CycleUsageResolution.allCases {
            guard var bucket = bucket(for: resolution) else { continue }
            bucket.sampleCount += 1
            if bucket.firstCycleCount == nil {
                bucket.firstCycleCount = observation.cycleCount
            }
            if let cycleCount = observation.cycleCount {
                bucket.lastCycleCount = cycleCount
            }

            if let interval {
                bucket.observedSeconds += interval.observedSeconds
                bucket.gapSeconds += interval.gapSeconds
                bucket.dischargedMAh += interval.dischargedMAh
                bucket.dischargedWattHours += interval.dischargedWattHours
                bucket.equivalentCycles += interval.equivalentCycles
                bucket.hardwareCycleDelta += interval.hardwareCycleDelta
                bucket.hardwareCycleDeltaDuringGap += interval.hardwareCycleDeltaDuringGap
                bucket.cycleResetCount += interval.cycleResetCount
                bucket.quality = Self.betterQuality(bucket.quality, interval.quality)
                bucket.primaryMethod = Self.betterMethod(bucket.primaryMethod, interval.method)
            }
            setBucket(bucket, for: resolution)
        }
    }

    private func bucket(for resolution: CycleUsageResolution) -> CycleUsageBucket? {
        switch resolution {
        case .quarterHour: return state.currentQuarterHour
        case .day: return state.currentDay
        }
    }

    private mutating func setBucket(_ bucket: CycleUsageBucket, for resolution: CycleUsageResolution) {
        switch resolution {
        case .quarterHour: state.currentQuarterHour = bucket
        case .day: state.currentDay = bucket
        }
    }

    private func recordCurrentBuckets(in updates: inout [BucketKey: CycleUsageBucket]) {
        if let bucket = state.currentQuarterHour {
            updates[BucketKey(bucket)] = bucket
        }
        if let bucket = state.currentDay {
            updates[BucketKey(bucket)] = bucket
        }
    }

    private func bucketStart(for date: Date, resolution: CycleUsageResolution) -> Date {
        switch resolution {
        case .quarterHour:
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            var rounded = components
            rounded.minute = (components.minute ?? 0) / 15 * 15
            rounded.second = 0
            return calendar.date(from: rounded) ?? date
        case .day:
            return calendar.startOfDay(for: date)
        }
    }

    private static func intervalEstimate(
        from previous: CycleUsageObservation,
        to current: CycleUsageObservation,
        maximumGap: TimeInterval
    ) -> IntervalEstimate {
        let duration = current.timestamp.timeIntervalSince(previous.timestamp)
        let cycleChange = cycleChange(from: previous.cycleCount, to: current.cycleCount)
        guard duration > 0, duration <= maximumGap else {
            return IntervalEstimate(
                observedSeconds: 0,
                gapSeconds: min(max(0, duration), 86_400),
                hardwareCycleDelta: cycleChange.delta,
                hardwareCycleDeltaDuringGap: cycleChange.delta,
                cycleResetCount: cycleChange.reset ? 1 : 0
            )
        }

        if let estimate = currentEstimate(from: previous, to: current, duration: duration) {
            return IntervalEstimate(
                observedSeconds: duration,
                dischargedMAh: estimate.dischargedMAh,
                dischargedWattHours: estimate.dischargedWattHours,
                equivalentCycles: estimate.equivalentCycles,
                hardwareCycleDelta: cycleChange.delta,
                cycleResetCount: cycleChange.reset ? 1 : 0,
                quality: estimate.quality,
                method: estimate.method
            )
        }

        if let estimate = capacityEstimate(from: previous, to: current) {
            return IntervalEstimate(
                observedSeconds: duration,
                dischargedMAh: estimate.dischargedMAh,
                equivalentCycles: estimate.equivalentCycles,
                hardwareCycleDelta: cycleChange.delta,
                cycleResetCount: cycleChange.reset ? 1 : 0,
                quality: .estimated,
                method: estimate.method
            )
        }

        return IntervalEstimate(
            observedSeconds: 0,
            gapSeconds: duration,
            hardwareCycleDelta: cycleChange.delta,
            hardwareCycleDeltaDuringGap: cycleChange.delta,
            cycleResetCount: cycleChange.reset ? 1 : 0
        )
    }

    private static func currentEstimate(
        from previous: CycleUsageObservation,
        to current: CycleUsageObservation,
        duration: TimeInterval
    ) -> CurrentEstimate? {
        let instantPair = validCurrentPair(
            previous.instantAmperageMilliamps,
            current.instantAmperageMilliamps
        )
        let averagePair = validCurrentPair(
            previous.averageAmperageMilliamps,
            current.averageAmperageMilliamps
        )
        let pair: (Double, Double)
        let method: CycleUsageMethod
        let quality: SensorQuality
        if let instantPair {
            pair = instantPair
            method = .instantCurrent
            quality = .measured
        } else if let averagePair {
            pair = averagePair
            method = .averageCurrent
            quality = .calculated
        } else {
            return nil
        }

        guard let capacity = averageCapacity(previous, current), capacity >= 500, capacity <= 30_000 else {
            return nil
        }
        let previousDischarge = previous.isCharging ? 0 : max(0, -pair.0)
        let currentDischarge = current.isCharging ? 0 : max(0, -pair.1)
        let averageDischargeMilliamps = (previousDischarge + currentDischarge) / 2
        let dischargedMAh = averageDischargeMilliamps * duration / 3_600
        let equivalentCycles = dischargedMAh / capacity
        guard equivalentCycles.isFinite, equivalentCycles >= 0, equivalentCycles <= 0.25 else {
            return nil
        }

        let dischargedWattHours: Double
        if let previousVoltage = validVoltage(previous.voltageMillivolts),
           let currentVoltage = validVoltage(current.voltageMillivolts) {
            let averageVoltage = (previousVoltage + currentVoltage) / 2
            dischargedWattHours = averageDischargeMilliamps * averageVoltage * duration / 3_600_000_000
        } else {
            dischargedWattHours = 0
        }

        return CurrentEstimate(
            dischargedMAh: dischargedMAh,
            dischargedWattHours: dischargedWattHours,
            equivalentCycles: equivalentCycles,
            quality: quality,
            method: method
        )
    }

    private static func capacityEstimate(
        from previous: CycleUsageObservation,
        to current: CycleUsageObservation
    ) -> (dischargedMAh: Double, equivalentCycles: Double, method: CycleUsageMethod)? {
        if let previousCurrent = validCapacity(previous.rawCurrentCapacityMAh),
           let currentCurrent = validCapacity(current.rawCurrentCapacityMAh),
           let previousMaximum = validCapacity(previous.rawMaxCapacityMAh),
           let currentMaximum = validCapacity(current.rawMaxCapacityMAh) {
            let maximum = (previousMaximum + currentMaximum) / 2
            let delta = max(0, previousCurrent - currentCurrent)
            let equivalentCycles = delta / maximum
            if equivalentCycles <= 0.25 {
                return (delta, equivalentCycles, .capacity)
            }
        }

        if let previousCurrent = validCapacity(previous.currentCapacityMAh),
           let currentCurrent = validCapacity(current.currentCapacityMAh),
           let previousMaximum = validCapacity(previous.nominalChargeCapacityMAh),
           let currentMaximum = validCapacity(current.nominalChargeCapacityMAh) {
            let maximum = (previousMaximum + currentMaximum) / 2
            let delta = max(0, previousCurrent - currentCurrent)
            let equivalentCycles = delta / maximum
            if equivalentCycles <= 0.25 {
                return (delta, equivalentCycles, .capacity)
            }
        }

        if let previousPercent = previous.chargePercent,
           let currentPercent = current.chargePercent,
           (0...100).contains(previousPercent),
           (0...100).contains(currentPercent) {
            let equivalentCycles = Double(max(0, previousPercent - currentPercent)) / 100
            if equivalentCycles <= 0.25 {
                return (0, equivalentCycles, .percentage)
            }
        }
        return nil
    }

    private static func validCurrentPair(_ first: Int64?, _ second: Int64?) -> (Double, Double)? {
        guard let first, let second,
              abs(first) <= 25_000,
              abs(second) <= 25_000 else {
            return nil
        }
        return (Double(first), Double(second))
    }

    private static func averageCapacity(
        _ previous: CycleUsageObservation,
        _ current: CycleUsageObservation
    ) -> Double? {
        if let first = validCapacity(previous.rawMaxCapacityMAh),
           let second = validCapacity(current.rawMaxCapacityMAh) {
            return (first + second) / 2
        }
        if let first = validCapacity(previous.nominalChargeCapacityMAh),
           let second = validCapacity(current.nominalChargeCapacityMAh) {
            return (first + second) / 2
        }
        return nil
    }

    private static func validCapacity(_ value: Int?) -> Double? {
        guard let value, value > 0, value <= 30_000 else { return nil }
        return Double(value)
    }

    private static func validVoltage(_ value: Int?) -> Double? {
        guard let value, value >= 5_000, value <= 30_000 else { return nil }
        return Double(value)
    }

    private static func cycleChange(from previous: Int?, to current: Int?) -> (delta: Int, reset: Bool) {
        guard let previous, let current else { return (0, false) }
        if current >= previous { return (current - previous, false) }
        return (0, true)
    }

    private static func betterQuality(_ first: SensorQuality, _ second: SensorQuality) -> SensorQuality {
        let rank: [SensorQuality: Int] = [
            .unavailable: 0,
            .stale: 1,
            .estimated: 2,
            .calculated: 3,
            .measured: 4,
            .rejected: -1
        ]
        return (rank[second] ?? 0) > (rank[first] ?? 0) ? second : first
    }

    private static func betterMethod(_ first: CycleUsageMethod, _ second: CycleUsageMethod) -> CycleUsageMethod {
        let rank: [CycleUsageMethod: Int] = [
            .unavailable: 0,
            .percentage: 1,
            .capacity: 2,
            .averageCurrent: 3,
            .instantCurrent: 4
        ]
        return (rank[second] ?? 0) > (rank[first] ?? 0) ? second : first
    }
}

private struct BucketKey: Hashable {
    let resolution: CycleUsageResolution
    let bucketStart: Date

    init(_ bucket: CycleUsageBucket) {
        self.resolution = bucket.resolution
        self.bucketStart = bucket.bucketStart
    }
}

private struct IntervalEstimate {
    var observedSeconds: TimeInterval = 0
    var gapSeconds: TimeInterval = 0
    var dischargedMAh: Double = 0
    var dischargedWattHours: Double = 0
    var equivalentCycles: Double = 0
    var hardwareCycleDelta: Int = 0
    var hardwareCycleDeltaDuringGap: Int = 0
    var cycleResetCount: Int = 0
    var quality: SensorQuality = .unavailable
    var method: CycleUsageMethod = .unavailable
}

private struct CurrentEstimate {
    let dischargedMAh: Double
    let dischargedWattHours: Double
    let equivalentCycles: Double
    let quality: SensorQuality
    let method: CycleUsageMethod
}
