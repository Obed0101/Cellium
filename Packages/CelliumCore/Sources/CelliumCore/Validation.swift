import Foundation

public struct SnapshotValidator: Sendable {
    public init() {}

    public func sanitize(_ snapshot: BatterySnapshot) -> BatterySnapshot {
        let chargePercent = BatteryMath.validPercent(snapshot.chargePercent)
        let temperature = snapshot.temperatureCelsius.flatMap(Self.validTemperature)
        let virtualTemperature = snapshot.virtualTemperatureCelsius.flatMap(Self.validTemperature)
        let cycleCount = snapshot.cycleCount.flatMap(Self.validNonNegative)
        let designCycleCount = snapshot.designCycleCount.flatMap(Self.validNonNegative)
        let timeToEmpty = BatteryMath.rejectTimeSentinel(snapshot.timeToEmptyMinutes)
        let timeToFull = BatteryMath.rejectTimeSentinel(snapshot.timeToFullMinutes)

        var diagnostics = snapshot.diagnostics
        if snapshot.chargePercent != nil, chargePercent == nil {
            diagnostics.append("charge_percent_out_of_range")
        }
        if snapshot.temperatureCelsius != nil, temperature == nil {
            diagnostics.append("temperature_out_of_range")
        }
        if snapshot.virtualTemperatureCelsius != nil, virtualTemperature == nil {
            diagnostics.append("virtual_temperature_out_of_range")
        }
        if snapshot.timeToFullMinutes == 65_535 {
            diagnostics.append("time_to_full_sentinel")
        }

        return BatterySnapshot(
            timestamp: snapshot.timestamp,
            chargePercent: chargePercent,
            currentCapacityMAh: Self.validNonNegative(snapshot.currentCapacityMAh),
            nominalChargeCapacityMAh: Self.validNonNegative(snapshot.nominalChargeCapacityMAh),
            designCapacityMAh: Self.validNonNegative(snapshot.designCapacityMAh),
            rawCurrentCapacityMAh: Self.validNonNegative(snapshot.rawCurrentCapacityMAh),
            rawMaxCapacityMAh: Self.validNonNegative(snapshot.rawMaxCapacityMAh),
            voltageMillivolts: Self.validPositive(snapshot.voltageMillivolts),
            amperageMilliamps: snapshot.amperageMilliamps,
            instantAmperageMilliamps: snapshot.instantAmperageMilliamps,
            temperatureCelsius: temperature,
            virtualTemperatureCelsius: virtualTemperature,
            cycleCount: cycleCount,
            designCycleCount: designCycleCount,
            isCharging: snapshot.isCharging,
            isFullyCharged: snapshot.isFullyCharged,
            externalPowerConnected: snapshot.externalPowerConnected,
            atCriticalLevel: snapshot.atCriticalLevel,
            timeToEmptyMinutes: timeToEmpty,
            timeToFullMinutes: timeToFull,
            adapter: snapshot.adapter,
            sourceQuality: snapshot.sourceQuality,
            powerSourceState: snapshot.powerSourceState,
            diagnostics: Array(Set(diagnostics)).sorted()
        )
    }

    private static func validTemperature(_ value: Double) -> Double? {
        guard value.isFinite, (-20...100).contains(value) else { return nil }
        return value
    }

    private static func validNonNegative(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func validPositive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
