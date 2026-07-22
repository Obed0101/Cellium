import Foundation

public enum BatterySessionKind: String, Codable, CaseIterable, Sendable {
    case charging
    case discharging
    case connectedDeficit
    case sleepGap
}

public struct BatterySession: Codable, Equatable, Sendable {
    public let kind: BatterySessionKind
    public let startedAt: Date
    public let endedAt: Date?
    public let startChargePercent: Int?
    public let endChargePercent: Int?
    public let sampleCount: Int
    public let quality: SensorQuality

    public init(
        kind: BatterySessionKind,
        startedAt: Date,
        endedAt: Date? = nil,
        startChargePercent: Int? = nil,
        endChargePercent: Int? = nil,
        sampleCount: Int = 0,
        quality: SensorQuality = .unavailable
    ) {
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startChargePercent = startChargePercent
        self.endChargePercent = endChargePercent
        self.sampleCount = max(0, sampleCount)
        self.quality = quality
    }
}

public enum BatterySessionEvent: Equatable, Sendable {
    case started(BatterySession)
    case completed(BatterySession)
}

public struct BatterySessionTracker: Sendable {
    public let maximumContinuityGap: TimeInterval

    private var active: ActiveSession?
    private var lastTimestamp: Date?

    public init(maximumContinuityGap: TimeInterval = 5 * 60) {
        self.maximumContinuityGap = max(0, maximumContinuityGap)
        self.active = nil
        self.lastTimestamp = nil
    }

    public mutating func ingest(_ sample: BatterySample) -> [BatterySessionEvent] {
        let timestamp = sample.battery.timestamp
        guard timestamp.timeIntervalSince1970.isFinite else { return [] }

        if let lastTimestamp {
            guard timestamp >= lastTimestamp else {
                return []
            }
        }

        var events: [BatterySessionEvent] = []
        if let lastTimestamp,
           timestamp.timeIntervalSince(lastTimestamp) > maximumContinuityGap {
            let previousChargePercent = active?.lastChargePercent
            if let active {
                events.append(.completed(active.finished(at: lastTimestamp)))
                self.active = nil
            }
            events.append(
                .completed(
                    BatterySession(
                        kind: .sleepGap,
                        startedAt: lastTimestamp,
                        endedAt: timestamp,
                        startChargePercent: previousChargePercent,
                        endChargePercent: sample.battery.chargePercent,
                        sampleCount: 0,
                        quality: .stale
                    )
                )
            )
        }

        self.lastTimestamp = timestamp
        guard let kind = Self.kind(for: sample) else {
            if let active {
                events.append(.completed(active.finished(at: timestamp)))
                self.active = nil
            }
            return events
        }

        if var active {
            if active.kind == kind {
                active.include(sample)
                self.active = active
                return events
            }

            events.append(.completed(active.finished(at: timestamp)))
        }

        let newActive = ActiveSession(sample: sample, kind: kind)
        self.active = newActive
        events.append(.started(newActive.snapshot()))
        return events
    }

    public mutating func finish(at date: Date = Date()) -> [BatterySessionEvent] {
        guard let active else { return [] }
        let endDate = max(date, active.lastTimestamp)
        self.active = nil
        return [.completed(active.finished(at: endDate))]
    }

    private static func kind(for sample: BatterySample) -> BatterySessionKind? {
        let battery = sample.battery
        guard battery.sourceQuality != .unavailable,
              battery.sourceQuality != .rejected else {
            return nil
        }

        if battery.externalPowerConnected {
            return battery.isCharging ? .charging : .connectedDeficit
        }
        guard battery.powerSourceState == .battery else { return nil }
        return .discharging
    }
}

private struct ActiveSession: Sendable {
    let kind: BatterySessionKind
    let startedAt: Date
    let startChargePercent: Int?
    var lastTimestamp: Date
    var lastChargePercent: Int?
    var sampleCount: Int
    var quality: SensorQuality

    init(sample: BatterySample, kind: BatterySessionKind) {
        self.kind = kind
        self.startedAt = sample.battery.timestamp
        self.startChargePercent = sample.battery.chargePercent
        self.lastTimestamp = sample.battery.timestamp
        self.lastChargePercent = sample.battery.chargePercent
        self.sampleCount = 1
        self.quality = sample.battery.sourceQuality
    }

    mutating func include(_ sample: BatterySample) {
        lastTimestamp = sample.battery.timestamp
        lastChargePercent = sample.battery.chargePercent
        sampleCount += 1
        quality = Self.worstQuality(quality, sample.battery.sourceQuality)
    }

    func snapshot() -> BatterySession {
        BatterySession(
            kind: kind,
            startedAt: startedAt,
            startChargePercent: startChargePercent,
            endChargePercent: lastChargePercent,
            sampleCount: sampleCount,
            quality: quality
        )
    }

    func finished(at date: Date) -> BatterySession {
        BatterySession(
            kind: kind,
            startedAt: startedAt,
            endedAt: max(date, lastTimestamp),
            startChargePercent: startChargePercent,
            endChargePercent: lastChargePercent,
            sampleCount: sampleCount,
            quality: quality
        )
    }

    private static func worstQuality(
        _ first: SensorQuality,
        _ second: SensorQuality
    ) -> SensorQuality {
        rank(first) >= rank(second) ? first : second
    }

    private static func rank(_ quality: SensorQuality) -> Int {
        switch quality {
        case .measured:
            return 0
        case .calculated:
            return 1
        case .estimated:
            return 2
        case .stale:
            return 3
        case .unavailable:
            return 4
        case .rejected:
            return 5
        }
    }
}
