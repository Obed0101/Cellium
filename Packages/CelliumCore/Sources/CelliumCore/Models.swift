import Foundation

public enum SensorQuality: String, Codable, CaseIterable, Sendable {
    case measured
    case calculated
    case estimated
    case stale
    case unavailable
    case rejected
}

public enum ThermalState: String, Codable, CaseIterable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unavailable
}

public enum PowerSourceState: String, Codable, CaseIterable, Sendable {
    case battery
    case adapter
    case unknown
}

public struct AdapterSnapshot: Codable, Equatable, Sendable {
    public let name: String?
    public let voltageMillivolts: Int?
    public let amperageMilliamps: Int64?
    public let powerWatts: Double?
    public let quality: SensorQuality

    public init(
        name: String? = nil,
        voltageMillivolts: Int? = nil,
        amperageMilliamps: Int64? = nil,
        powerWatts: Double? = nil,
        quality: SensorQuality = .unavailable
    ) {
        self.name = name
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamps = amperageMilliamps
        self.powerWatts = powerWatts
        self.quality = quality
    }
}

public struct BatterySnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let chargePercent: Int?
    public let currentCapacityMAh: Int?
    public let nominalChargeCapacityMAh: Int?
    public let designCapacityMAh: Int?
    public let rawCurrentCapacityMAh: Int?
    public let rawMaxCapacityMAh: Int?
    public let voltageMillivolts: Int?
    public let amperageMilliamps: Int64?
    public let instantAmperageMilliamps: Int64?
    public let temperatureCelsius: Double?
    public let virtualTemperatureCelsius: Double?
    public let cycleCount: Int?
    public let designCycleCount: Int?
    public let isCharging: Bool
    public let isFullyCharged: Bool
    public let externalPowerConnected: Bool
    public let atCriticalLevel: Bool
    public let timeToEmptyMinutes: Int?
    public let timeToFullMinutes: Int?
    public let adapter: AdapterSnapshot?
    public let sourceQuality: SensorQuality
    public let powerSourceState: PowerSourceState
    public let diagnostics: [String]

    public init(
        timestamp: Date = Date(),
        chargePercent: Int? = nil,
        currentCapacityMAh: Int? = nil,
        nominalChargeCapacityMAh: Int? = nil,
        designCapacityMAh: Int? = nil,
        rawCurrentCapacityMAh: Int? = nil,
        rawMaxCapacityMAh: Int? = nil,
        voltageMillivolts: Int? = nil,
        amperageMilliamps: Int64? = nil,
        instantAmperageMilliamps: Int64? = nil,
        temperatureCelsius: Double? = nil,
        virtualTemperatureCelsius: Double? = nil,
        cycleCount: Int? = nil,
        designCycleCount: Int? = nil,
        isCharging: Bool = false,
        isFullyCharged: Bool = false,
        externalPowerConnected: Bool = false,
        atCriticalLevel: Bool = false,
        timeToEmptyMinutes: Int? = nil,
        timeToFullMinutes: Int? = nil,
        adapter: AdapterSnapshot? = nil,
        sourceQuality: SensorQuality = .unavailable,
        powerSourceState: PowerSourceState = .unknown,
        diagnostics: [String] = []
    ) {
        self.timestamp = timestamp
        self.chargePercent = chargePercent
        self.currentCapacityMAh = currentCapacityMAh
        self.nominalChargeCapacityMAh = nominalChargeCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.rawCurrentCapacityMAh = rawCurrentCapacityMAh
        self.rawMaxCapacityMAh = rawMaxCapacityMAh
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamps = amperageMilliamps
        self.instantAmperageMilliamps = instantAmperageMilliamps
        self.temperatureCelsius = temperatureCelsius
        self.virtualTemperatureCelsius = virtualTemperatureCelsius
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.externalPowerConnected = externalPowerConnected
        self.atCriticalLevel = atCriticalLevel
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.timeToFullMinutes = timeToFullMinutes
        self.adapter = adapter
        self.sourceQuality = sourceQuality
        self.powerSourceState = powerSourceState
        self.diagnostics = diagnostics
    }
}

public struct SystemSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let thermalState: ThermalState
    public let lowPowerModeEnabled: Bool
    public let cpuUsagePercent: Double?
    public let memoryUsedPercent: Double?
    public let memoryUsedBytes: Int64?
    public let memoryTotalBytes: Int64?
    public let diskUsedPercent: Double?
    public let diskUsedBytes: Int64?
    public let diskTotalBytes: Int64?
    public let diskFreeBytes: Int64?
    public let diskReadBytesPerSecond: Double?
    public let diskWriteBytesPerSecond: Double?

    public init(
        timestamp: Date = Date(),
        thermalState: ThermalState,
        lowPowerModeEnabled: Bool,
        cpuUsagePercent: Double? = nil,
        memoryUsedPercent: Double? = nil,
        memoryUsedBytes: Int64? = nil,
        memoryTotalBytes: Int64? = nil,
        diskUsedPercent: Double? = nil,
        diskUsedBytes: Int64? = nil,
        diskTotalBytes: Int64? = nil,
        diskFreeBytes: Int64? = nil,
        diskReadBytesPerSecond: Double? = nil,
        diskWriteBytesPerSecond: Double? = nil
    ) {
        self.timestamp = timestamp
        self.thermalState = thermalState
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsedPercent = memoryUsedPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskUsedPercent = diskUsedPercent
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.diskFreeBytes = diskFreeBytes
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
    }
}
