import CelliumCore

public protocol ReadOnlyPowerReader: Sendable {
    func readBatteryPowerWatts() -> Double?
}

/// Safe MVP fallback. It deliberately has no SMC access or write capability.
public struct UnavailableSMCPowerReader: ReadOnlyPowerReader, Sendable {
    public init() {}

    public func readBatteryPowerWatts() -> Double? {
        nil
    }
}

public enum DarwinModule {
    public static let name = "CelliumDarwin"
    public static let smcWriteSupported = false
}
