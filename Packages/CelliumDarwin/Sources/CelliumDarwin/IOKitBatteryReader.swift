import Foundation
import IOKit
import IOKit.ps
import CelliumCore

public protocol BatteryReader: Sendable {
    func readSnapshot(at date: Date) -> BatterySnapshot
}

public struct IOKitBatteryReader: BatteryReader, Sendable {
    public init() {}

    public func readSnapshot(at date: Date = Date()) -> BatterySnapshot {
        let powerSource = readPowerSourceDescription()
        let registry = readAppleSmartBatteryProperties()
        var diagnostics: [String] = []

        if powerSource == nil {
            diagnostics.append("power_source_unavailable")
        }
        if registry.isEmpty {
            diagnostics.append("apple_smart_battery_unavailable")
        }

        let chargePercent = validPercent(
            integer(powerSource?["Current Capacity"]) ?? integer(registry["CurrentCapacity"])
        )
        let isCharging = boolean(powerSource?["Is Charging"]) ?? boolean(registry["IsCharging"]) ?? false
        let fullyCharged = boolean(powerSource?["Fully Charged"]) ?? boolean(registry["FullyCharged"]) ?? false
        let sourceState = powerSourceState(powerSource?["Power Source State"])
        let externalConnected = (boolean(powerSource?["External Connected"])
            ?? boolean(registry["ExternalConnected"])
            ?? false) || sourceState == .adapter

        let rawAmperage = signedMilliamps(registry["Amperage"])
        let rawInstantAmperage = signedMilliamps(registry["InstantAmperage"])
        let timeToFull = BatteryMath.rejectTimeSentinel(
            integer(powerSource?["Time to Full"]) ?? integer(registry["AvgTimeToFull"])
        )
        let timeToEmpty = BatteryMath.rejectTimeSentinel(
            integer(powerSource?["Time to Empty"]) ?? integer(registry["AvgTimeToEmpty"])
        )
        let chargeLimitPercent = chargeLimitPercent(from: registry)

        if integer(powerSource?["Time to Full"]) == 65_535 || integer(registry["AvgTimeToFull"]) == 65_535 {
            diagnostics.append("time_to_full_sentinel")
        }

        return BatterySnapshot(
            timestamp: date,
            chargePercent: chargePercent,
            // `CurrentCapacity` is percentage-style on the observed gauge; do not label it mAh.
            currentCapacityMAh: nil,
            nominalChargeCapacityMAh: nonNegative(integer(registry["NominalChargeCapacity"])),
            designCapacityMAh: nonNegative(integer(registry["DesignCapacity"])),
            rawCurrentCapacityMAh: nonNegative(integer(registry["AppleRawCurrentCapacity"])),
            rawMaxCapacityMAh: nonNegative(integer(registry["AppleRawMaxCapacity"])),
            voltageMillivolts: positive(integer(registry["Voltage"])),
            amperageMilliamps: rawAmperage,
            instantAmperageMilliamps: rawInstantAmperage,
            temperatureCelsius: BatteryMath.temperatureCelsius(fromCentiCelsius: integer(registry["Temperature"])),
            virtualTemperatureCelsius: BatteryMath.temperatureCelsius(fromCentiCelsius: integer(registry["VirtualTemperature"])),
            cycleCount: nonNegative(integer(registry["CycleCount"])),
            designCycleCount: nonNegative(integer(registry["DesignCycleCount9C"])),
            isCharging: isCharging,
            isFullyCharged: fullyCharged,
            externalPowerConnected: externalConnected,
            atCriticalLevel: boolean(powerSource?["At Critical Level"]) ?? boolean(registry["AtCriticalLevel"]) ?? false,
            timeToEmptyMinutes: timeToEmpty,
            timeToFullMinutes: timeToFull,
            chargeLimitPercent: chargeLimitPercent,
            adapter: nil,
            sourceQuality: powerSource == nil && registry.isEmpty ? .unavailable : .measured,
            powerSourceState: sourceState,
            diagnostics: diagnostics
        )
    }

    private func readPowerSourceDescription() -> [String: Any]? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if description["Type"] as? String == "InternalBattery" {
                return description
            }
        }

        return nil
    }

    private func readAppleSmartBatteryProperties() -> [String: Any] {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS,
              let unmanagedProperties,
              let properties = unmanagedProperties.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return properties
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(exactly: value) }
        if let value = value as? UInt64 { return Int(exactly: value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func signedMilliamps(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? UInt64 { return Int64(bitPattern: value) }
        if let value = value as? NSNumber {
            let unsigned = value.uint64Value
            if unsigned > UInt64(Int64.max) {
                return Int64(bitPattern: unsigned)
            }
            return value.int64Value
        }
        if let value = value as? String, let parsed = UInt64(value) {
            return Int64(bitPattern: parsed)
        }
        return nil
    }

    private func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private func powerSourceState(_ value: Any?) -> PowerSourceState {
        guard let state = value as? String else { return .unknown }
        switch state {
        case "Battery Power": return .battery
        case "AC Power": return .adapter
        default: return .unknown
        }
    }

    private func chargeLimitPercent(from registry: [String: Any]) -> Int? {
        guard let batteryData = registry["BatteryData"] as? [String: Any],
              let dailyMaximum = validPercent(integer(batteryData["DailyMaxSoc"])),
              dailyMaximum > 0,
              dailyMaximum < 100 else {
            return nil
        }
        return dailyMaximum
    }

    private func validPercent(_ value: Int?) -> Int? {
        BatteryMath.validPercent(value)
    }

    private func nonNegative(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
