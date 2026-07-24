import Foundation

public enum BatteryMath {
    private static let minTemperatureCelsius = -20.0
    private static let maxTemperatureCelsius = 100.0

    public static func validPercent(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }

    public static func healthPercent(
        nominalChargeCapacityMAh: Int?,
        designCapacityMAh: Int?
    ) -> Double? {
        guard let nominalChargeCapacityMAh,
              let designCapacityMAh,
              nominalChargeCapacityMAh > 0,
              designCapacityMAh > 0 else {
            return nil
        }

        let result = Double(nominalChargeCapacityMAh) / Double(designCapacityMAh) * 100
        guard result.isFinite, result > 0, result <= 150 else { return nil }
        return result
    }

    public static func temperatureCelsius(fromCentiCelsius rawValue: Int?) -> Double? {
        guard let rawValue else { return nil }
        let temperature = Double(rawValue) / 100
        guard temperature.isFinite,
              (minTemperatureCelsius...maxTemperatureCelsius).contains(temperature) else {
            return nil
        }
        return temperature
    }

    public static func signedMilliamps(fromRawUnsigned rawValue: UInt64?) -> Int64? {
        guard let rawValue else { return nil }
        return Int64(bitPattern: rawValue)
    }

    /// Cellium convention: positive battery power means discharge; negative means charge.
    /// AppleSmartBattery commonly reports a negative signed current during discharge, so
    /// normalization intentionally inverts the raw electrical sign.
    public static func batteryPowerWatts(
        voltageMillivolts: Int?,
        signedAmperageMilliamps: Int64?
    ) -> Double? {
        guard let voltageMillivolts,
              let signedAmperageMilliamps,
              voltageMillivolts > 0 else {
            return nil
        }

        let rawWatts = Double(voltageMillivolts) * Double(signedAmperageMilliamps) / 1_000_000
        let normalizedWatts = -rawWatts
        guard normalizedWatts.isFinite, abs(normalizedWatts) <= 1_000 else { return nil }
        return normalizedWatts
    }

    public static func rejectTimeSentinel(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65_535 else { return nil }
        return value
    }
}

/// Prevents transient macOS capacity recalculations from looking like health changes.
/// Battery health should move slowly and should not improve because of one noisy sample.
public struct BatteryHealthStabilizer: Equatable, Sendable {
    public let confirmationSamples: Int
    public let significantChangePercent: Double
    public private(set) var stablePercent: Double?

    private var pendingPercent: Double?
    private var pendingSamples = 0

    public init(
        initialPercent: Double? = nil,
        confirmationSamples: Int = 12,
        significantChangePercent: Double = 0.5
    ) {
        self.confirmationSamples = max(1, confirmationSamples)
        self.significantChangePercent = max(0.1, significantChangePercent)
        self.stablePercent = Self.validPercent(initialPercent)
    }

    public mutating func update(_ rawPercent: Double?) -> Double? {
        guard let rawPercent = Self.validPercent(rawPercent) else {
            return stablePercent
        }
        guard let stablePercent else {
            self.stablePercent = rawPercent
            return rawPercent
        }

        // Health must not jump upward because the controller reported a new
        // nominal capacity while the battery was charging or discharging.
        guard rawPercent < stablePercent - significantChangePercent else {
            pendingPercent = nil
            pendingSamples = 0
            return stablePercent
        }

        if let pendingPercent,
           abs(pendingPercent - rawPercent) <= significantChangePercent {
            pendingSamples += 1
        } else {
            self.pendingPercent = rawPercent
            pendingSamples = 1
        }

        guard pendingSamples >= confirmationSamples else {
            return stablePercent
        }

        self.stablePercent = rawPercent
        pendingPercent = nil
        pendingSamples = 0
        return rawPercent
    }

    private static func validPercent(_ value: Double?) -> Double? {
        guard let value,
              value.isFinite,
              value > 0,
              value <= 150 else {
            return nil
        }
        return value
    }
}
