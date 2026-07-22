import Foundation
import CelliumCore

public struct StoreConfiguration: Sendable, Equatable {
    public let rawRetentionDays: Int
    public let rawSampleLimit: Int
    public let minuteRetentionDays: Int
    public let quarterHourRetentionDays: Int
    public let dailyRetentionDays: Int?
    public let alertRetentionDays: Int

    public init(
        rawRetentionDays: Int = 7,
        rawSampleLimit: Int = 100_000,
        minuteRetentionDays: Int = 90,
        quarterHourRetentionDays: Int = 730,
        dailyRetentionDays: Int? = nil,
        alertRetentionDays: Int = 365
    ) {
        self.rawRetentionDays = max(1, rawRetentionDays)
        self.rawSampleLimit = max(1_000, rawSampleLimit)
        self.minuteRetentionDays = max(1, minuteRetentionDays)
        self.quarterHourRetentionDays = max(1, quarterHourRetentionDays)
        self.dailyRetentionDays = dailyRetentionDays.map { max(1, $0) }
        self.alertRetentionDays = max(1, alertRetentionDays)
    }
}

public typealias StoredBatterySample = BatterySample

public struct StoredProcessSample: Codable, Equatable, Sendable {
    public let processID: Int32
    public let name: String
    public let timestamp: Date
    public let cpuPercent: Double
    public let residentMemoryBytes: Int64?
    public let memoryPercent: Double?
    public let estimatedBatteryPercentPerMinute: Double?

    public init(
        processID: Int32,
        name: String,
        timestamp: Date,
        cpuPercent: Double,
        residentMemoryBytes: Int64? = nil,
        memoryPercent: Double? = nil,
        estimatedBatteryPercentPerMinute: Double? = nil
    ) {
        self.processID = processID
        self.name = name
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.residentMemoryBytes = residentMemoryBytes
        self.memoryPercent = memoryPercent
        self.estimatedBatteryPercentPerMinute = estimatedBatteryPercentPerMinute
    }
}

public struct SampleEvidence: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let observedDays: Int
    public let firstSampleDate: Date?
    public let lastSampleDate: Date?

    public init(
        sampleCount: Int,
        observedDays: Int,
        firstSampleDate: Date?,
        lastSampleDate: Date?
    ) {
        self.sampleCount = sampleCount
        self.observedDays = observedDays
        self.firstSampleDate = firstSampleDate
        self.lastSampleDate = lastSampleDate
    }
}

public enum AlertSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case critical
}

public struct StoredAlertEvent: Codable, Equatable, Sendable {
    public let identifier: String
    public let occurredAt: Date
    public let severity: AlertSeverity
    public let subject: String?
    public let measurements: [String: Double]

    public init(
        identifier: String,
        occurredAt: Date,
        severity: AlertSeverity = .warning,
        subject: String? = nil,
        measurements: [String: Double] = [:]
    ) {
        self.identifier = identifier
        self.occurredAt = occurredAt
        self.severity = severity
        self.subject = subject
        self.measurements = measurements
    }
}

public enum StoreError: Error, Sendable, Equatable {
    case unavailable
    case migrationFailed
    case invalidData
    case locked
    case diskFull
    case corrupted
    case unsupportedSchema(version: Int)
    case sqlite(message: String)

    public var diagnosticCode: String {
        switch self {
        case .unavailable:
            return "store_unavailable"
        case .migrationFailed:
            return "store_migration_failed"
        case .invalidData:
            return "store_invalid_data"
        case .locked:
            return "store_locked"
        case .diskFull:
            return "store_disk_full"
        case .corrupted:
            return "store_corrupted"
        case .unsupportedSchema:
            return "store_unsupported_schema"
        case .sqlite:
            return "store_sqlite_error"
        }
    }

    public var userMessage: String {
        switch self {
        case .unavailable:
            return "Local storage is unavailable."
        case .migrationFailed:
            return "Local storage migration failed."
        case .invalidData:
            return "The stored data is invalid."
        case .locked:
            return "Local storage is locked by another process."
        case .diskFull:
            return "There is not enough disk space for local storage."
        case .corrupted:
            return "Local storage is corrupted."
        case let .unsupportedSchema(version):
            return "Local storage schema version \(version) is not supported."
        case let .sqlite(message):
            return message
        }
    }
}

public struct StoreDiagnostics: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let databaseSizeBytes: Int64
    public let walSizeBytes: Int64

    public init(
        schemaVersion: Int,
        databaseSizeBytes: Int64,
        walSizeBytes: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.databaseSizeBytes = databaseSizeBytes
        self.walSizeBytes = walSizeBytes
    }
}

public enum BatteryAggregateResolution: String, Codable, CaseIterable, Sendable {
    case minute
    case quarterHour
    case day
}

public struct BatteryAggregate: Codable, Equatable, Sendable {
    public let resolution: BatteryAggregateResolution
    public let bucketStart: Date
    public let sampleCount: Int
    public let chargeSampleCount: Int
    public let minimumChargePercent: Int?
    public let maximumChargePercent: Int?
    public let averageChargePercent: Double?
    public let temperatureSampleCount: Int
    public let averageTemperatureCelsius: Double?
    public let minimumTemperatureCelsius: Double?
    public let maximumTemperatureCelsius: Double?
    public let chargingSampleCount: Int
    public let externalPowerSampleCount: Int
    public let powerSampleCount: Int
    public let averageBatteryPowerWatts: Double?
    public let cpuSampleCount: Int
    public let averageCPUUsagePercent: Double?
    public let memorySampleCount: Int
    public let averageMemoryUsedPercent: Double?
    public let diskSampleCount: Int
    public let averageDiskUsedPercent: Double?
    public let diskReadSampleCount: Int
    public let averageDiskReadBytesPerSecond: Double?
    public let diskWriteSampleCount: Int
    public let averageDiskWriteBytesPerSecond: Double?

    public init(
        resolution: BatteryAggregateResolution,
        bucketStart: Date,
        sampleCount: Int,
        chargeSampleCount: Int,
        minimumChargePercent: Int?,
        maximumChargePercent: Int?,
        averageChargePercent: Double?,
        temperatureSampleCount: Int,
        averageTemperatureCelsius: Double?,
        minimumTemperatureCelsius: Double?,
        maximumTemperatureCelsius: Double?,
        chargingSampleCount: Int,
        externalPowerSampleCount: Int,
        powerSampleCount: Int = 0,
        averageBatteryPowerWatts: Double? = nil,
        cpuSampleCount: Int = 0,
        averageCPUUsagePercent: Double? = nil,
        memorySampleCount: Int = 0,
        averageMemoryUsedPercent: Double? = nil,
        diskSampleCount: Int = 0,
        averageDiskUsedPercent: Double? = nil,
        diskReadSampleCount: Int = 0,
        averageDiskReadBytesPerSecond: Double? = nil,
        diskWriteSampleCount: Int = 0,
        averageDiskWriteBytesPerSecond: Double? = nil
    ) {
        self.resolution = resolution
        self.bucketStart = bucketStart
        self.sampleCount = sampleCount
        self.chargeSampleCount = chargeSampleCount
        self.minimumChargePercent = minimumChargePercent
        self.maximumChargePercent = maximumChargePercent
        self.averageChargePercent = averageChargePercent
        self.temperatureSampleCount = temperatureSampleCount
        self.averageTemperatureCelsius = averageTemperatureCelsius
        self.minimumTemperatureCelsius = minimumTemperatureCelsius
        self.maximumTemperatureCelsius = maximumTemperatureCelsius
        self.chargingSampleCount = chargingSampleCount
        self.externalPowerSampleCount = externalPowerSampleCount
        self.powerSampleCount = powerSampleCount
        self.averageBatteryPowerWatts = averageBatteryPowerWatts
        self.cpuSampleCount = cpuSampleCount
        self.averageCPUUsagePercent = averageCPUUsagePercent
        self.memorySampleCount = memorySampleCount
        self.averageMemoryUsedPercent = averageMemoryUsedPercent
        self.diskSampleCount = diskSampleCount
        self.averageDiskUsedPercent = averageDiskUsedPercent
        self.diskReadSampleCount = diskReadSampleCount
        self.averageDiskReadBytesPerSecond = averageDiskReadBytesPerSecond
        self.diskWriteSampleCount = diskWriteSampleCount
        self.averageDiskWriteBytesPerSecond = averageDiskWriteBytesPerSecond
    }

    private enum CodingKeys: String, CodingKey {
        case resolution
        case bucketStart
        case sampleCount
        case chargeSampleCount
        case minimumChargePercent
        case maximumChargePercent
        case averageChargePercent
        case temperatureSampleCount
        case averageTemperatureCelsius
        case minimumTemperatureCelsius
        case maximumTemperatureCelsius
        case chargingSampleCount
        case externalPowerSampleCount
        case powerSampleCount
        case averageBatteryPowerWatts
        case cpuSampleCount
        case averageCPUUsagePercent
        case memorySampleCount
        case averageMemoryUsedPercent
        case diskSampleCount
        case averageDiskUsedPercent
        case diskReadSampleCount
        case averageDiskReadBytesPerSecond
        case diskWriteSampleCount
        case averageDiskWriteBytesPerSecond
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.resolution = try container.decode(BatteryAggregateResolution.self, forKey: .resolution)
        self.bucketStart = try container.decode(Date.self, forKey: .bucketStart)
        self.sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        self.chargeSampleCount = try container.decode(Int.self, forKey: .chargeSampleCount)
        self.minimumChargePercent = try container.decodeIfPresent(Int.self, forKey: .minimumChargePercent)
        self.maximumChargePercent = try container.decodeIfPresent(Int.self, forKey: .maximumChargePercent)
        self.averageChargePercent = try container.decodeIfPresent(Double.self, forKey: .averageChargePercent)
        self.temperatureSampleCount = try container.decode(Int.self, forKey: .temperatureSampleCount)
        self.averageTemperatureCelsius = try container.decodeIfPresent(Double.self, forKey: .averageTemperatureCelsius)
        self.minimumTemperatureCelsius = try container.decodeIfPresent(Double.self, forKey: .minimumTemperatureCelsius)
        self.maximumTemperatureCelsius = try container.decodeIfPresent(Double.self, forKey: .maximumTemperatureCelsius)
        self.chargingSampleCount = try container.decode(Int.self, forKey: .chargingSampleCount)
        self.externalPowerSampleCount = try container.decode(Int.self, forKey: .externalPowerSampleCount)
        self.powerSampleCount = try container.decodeIfPresent(Int.self, forKey: .powerSampleCount) ?? 0
        self.averageBatteryPowerWatts = try container.decodeIfPresent(Double.self, forKey: .averageBatteryPowerWatts)
        self.cpuSampleCount = try container.decodeIfPresent(Int.self, forKey: .cpuSampleCount) ?? 0
        self.averageCPUUsagePercent = try container.decodeIfPresent(Double.self, forKey: .averageCPUUsagePercent)
        self.memorySampleCount = try container.decodeIfPresent(Int.self, forKey: .memorySampleCount) ?? 0
        self.averageMemoryUsedPercent = try container.decodeIfPresent(Double.self, forKey: .averageMemoryUsedPercent)
        self.diskSampleCount = try container.decodeIfPresent(Int.self, forKey: .diskSampleCount) ?? 0
        self.averageDiskUsedPercent = try container.decodeIfPresent(Double.self, forKey: .averageDiskUsedPercent)
        self.diskReadSampleCount = try container.decodeIfPresent(Int.self, forKey: .diskReadSampleCount) ?? 0
        self.averageDiskReadBytesPerSecond = try container.decodeIfPresent(Double.self, forKey: .averageDiskReadBytesPerSecond)
        self.diskWriteSampleCount = try container.decodeIfPresent(Int.self, forKey: .diskWriteSampleCount) ?? 0
        self.averageDiskWriteBytesPerSecond = try container.decodeIfPresent(Double.self, forKey: .averageDiskWriteBytesPerSecond)
    }
}

public enum CelliumStoreModule {
    public static let name = "CelliumStore"
}
