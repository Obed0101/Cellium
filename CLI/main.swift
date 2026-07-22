import Foundation
import CelliumCore
import CelliumDarwin
import CelliumStore

private struct StatusPayload: Codable, Sendable {
    let schemaVersion: Int
    let battery: BatterySnapshot
    let system: SystemSnapshot
    let healthPercent: Double?
    let batteryPowerWatts: Double?
}

private struct DoctorCheck: Codable, Sendable {
    let name: String
    let passed: Bool
    let detail: String
}

private struct DoctorReport: Codable, Sendable {
    let sensorSourceQuality: SensorQuality
    let powerSourceState: PowerSourceState
    let thermalState: ThermalState
    let lowPowerModeEnabled: Bool
    let sensorDiagnostics: [String]
    let databasePath: String?
    let schemaVersion: Int?
    let databaseSizeBytes: Int64?
    let walSizeBytes: Int64?
    let sampleCount: Int?
    let sessionCount: Int?
    let storeError: String?
    let smcWritesEnabled: Bool
    let networkEnabled: Bool
    let checks: [DoctorCheck]
}

private struct HistoryPayload: Codable, Sendable {
    let samples: [StoredBatterySample]
    let sessions: [BatterySession]
    let diagnostics: StoreDiagnostics
}

private enum CLIError: LocalizedError {
    case missingValue(String)
    case invalidValue(option: String, value: String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(option):
            return "Missing value for \(option)."
        case let .invalidValue(option, value):
            return "Invalid value for \(option): \(value)."
        case let .unsupportedFormat(format):
            return "Unsupported export format: \(format). Use csv."
        }
    }
}

@main
struct CelliumCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "status"

        switch command {
        case "status":
            printStatus(json: arguments.contains("--json"))
        case "doctor":
            await printDoctor(json: arguments.contains("--json"))
        case "history":
            do {
                try await printHistory(arguments: Array(arguments.dropFirst()))
            } catch {
                fail(error, usage: "Usage: cellium history [--json] [--range RANGE] [--hours N] [--limit N]")
            }
        case "export":
            do {
                try await exportSamples(arguments: Array(arguments.dropFirst()))
            } catch {
                fail(error, usage: "Usage: cellium export [--format csv] [--range RANGE] [--hours N] [--limit N] [--output PATH]")
            }
        case "version":
            print("Cellium development build")
        case "help", "--help", "-h":
            printHelp()
        default:
            fputs("Unknown command: \(command)\n", stderr)
            printHelp()
            exit(64)
        }
    }

    private static func makePayload() -> StatusPayload {
        let reader = IOKitBatteryReader()
        let battery = reader.readSnapshot()
        let system = SystemStateReader().readSnapshot(at: battery.timestamp)
        let health = BatteryMath.healthPercent(
            nominalChargeCapacityMAh: battery.nominalChargeCapacityMAh,
            designCapacityMAh: battery.designCapacityMAh
        )
        let power = BatteryMath.batteryPowerWatts(
            voltageMillivolts: battery.voltageMillivolts,
            signedAmperageMilliamps: battery.amperageMilliamps
        )
        return StatusPayload(
            schemaVersion: 1,
            battery: battery,
            system: system,
            healthPercent: health,
            batteryPowerWatts: power
        )
    }

    private static func printStatus(json: Bool) {
        let payload = makePayload()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(payload)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                fputs("Could not encode status: \(error)\n", stderr)
                exit(1)
            }
            return
        }

        let charge = payload.battery.chargePercent.map { "\($0)%" } ?? "Unavailable"
        let health = payload.healthPercent.map { String(format: "%.1f%%", $0) } ?? "Unavailable"
        let temperature = payload.battery.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "Unavailable"
        let power = payload.batteryPowerWatts.map { String(format: "%.2f W", $0) } ?? "Unavailable"

        print("Cellium")
        print("Battery: \(charge)")
        print("Health (calculated): \(health)")
        print("Temperature: \(temperature)")
        print("Power (normalized): \(power)")
        print("Cycles: \(payload.battery.cycleCount.map(String.init) ?? "Unavailable")")
        print("State: \(payload.battery.powerSourceState.rawValue)")
        print("Thermal: \(payload.system.thermalState.rawValue)")
        print("Low Power Mode: \(payload.system.lowPowerModeEnabled ? "on" : "off")")
    }

    private static func printDoctor(json: Bool) async {
        let payload = makePayload()
        let databaseURL = try? SQLiteStore.defaultDatabaseURL()
        var schemaVersion: Int?
        var databaseSizeBytes: Int64?
        var walSizeBytes: Int64?
        var sampleCount: Int?
        var sessionCount: Int?
        var storeError: String?

        if let databaseURL {
            do {
                let store = try SQLiteStore(databaseURL: databaseURL)
                let diagnostics = try await store.diagnostics()
                schemaVersion = diagnostics.schemaVersion
                databaseSizeBytes = diagnostics.databaseSizeBytes
                walSizeBytes = diagnostics.walSizeBytes
                sampleCount = try await store.sampleCount()
                let sessions = try await store.fetchSessions(limit: 10_000)
                sessionCount = sessions.count
            } catch {
                storeError = describe(error)
            }
        } else {
            storeError = "Unable to resolve the default database location."
        }

        let sensorAvailable = payload.battery.sourceQuality != .unavailable
            && payload.battery.sourceQuality != .rejected
        let checks = [
            DoctorCheck(
                name: "read_only_sensor",
                passed: sensorAvailable,
                detail: payload.battery.sourceQuality.rawValue
            ),
            DoctorCheck(
                name: "local_store",
                passed: storeError == nil,
                detail: storeError ?? "readable"
            ),
            DoctorCheck(
                name: "smc_writes",
                passed: true,
                detail: "disabled"
            ),
            DoctorCheck(
                name: "network",
                passed: true,
                detail: "disabled in MVP"
            )
        ]
        let report = DoctorReport(
            sensorSourceQuality: payload.battery.sourceQuality,
            powerSourceState: payload.battery.powerSourceState,
            thermalState: payload.system.thermalState,
            lowPowerModeEnabled: payload.system.lowPowerModeEnabled,
            sensorDiagnostics: payload.battery.diagnostics,
            databasePath: databaseURL?.path,
            schemaVersion: schemaVersion,
            databaseSizeBytes: databaseSizeBytes,
            walSizeBytes: walSizeBytes,
            sampleCount: sampleCount,
            sessionCount: sessionCount,
            storeError: storeError,
            smcWritesEnabled: false,
            networkEnabled: false,
            checks: checks
        )

        if json {
            writeJSON(report)
        } else {
            print("Cellium doctor")
            print("Read-only sensor source: \(report.sensorSourceQuality.rawValue)")
            print("Power source: \(report.powerSourceState.rawValue)")
            print("Thermal state: \(report.thermalState.rawValue)")
            print("Low Power Mode: \(report.lowPowerModeEnabled ? "on" : "off")")
            print("Sensor diagnostics: \(report.sensorDiagnostics.isEmpty ? "none" : report.sensorDiagnostics.joined(separator: ", "))")
            print("Database: \(report.databasePath ?? "Unavailable")")
            print("Schema: \(report.schemaVersion.map(String.init) ?? "Unavailable")")
            print("Samples: \(report.sampleCount.map(String.init) ?? "Unavailable")")
            print("Sessions: \(report.sessionCount.map(String.init) ?? "Unavailable")")
            if let databaseSizeBytes = report.databaseSizeBytes {
                print("Database size: \(databaseSizeBytes) bytes")
            }
            if let walSizeBytes = report.walSizeBytes {
                print("WAL size: \(walSizeBytes) bytes")
            }
            for check in report.checks {
                print("\(check.passed ? "PASS" : "FAIL") \(check.name): \(check.detail)")
            }
            if !payload.battery.diagnostics.isEmpty {
                print("Sensor diagnostics: \(payload.battery.diagnostics.joined(separator: ", "))")
            }
        }

        if report.checks.contains(where: { !$0.passed }) {
            exit(1)
        }
    }

    private static func printHistory(arguments: [String]) async throws {
        let store = try openStore()
        let since = try parseSince(arguments: arguments)
        let limit = try parseLimit(arguments: arguments)
        let payload = HistoryPayload(
            samples: try await store.fetchBatterySamples(since: since, limit: limit),
            sessions: try await store.fetchSessions(since: since, limit: limit),
            diagnostics: try await store.diagnostics()
        )

        if arguments.contains("--json") {
            writeJSON(payload)
            return
        }

        print("Cellium history")
        print("Samples: \(payload.samples.count)")
        for sample in payload.samples.prefix(10) {
            let charge = sample.battery.chargePercent.map { "\($0)%" } ?? "—"
            let temperature = sample.battery.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—"
            print("  \(formatDate(sample.battery.timestamp))  \(charge)  \(temperature)")
        }
        print("Sessions: \(payload.sessions.count)")
        for session in payload.sessions.prefix(10) {
            let end = session.endedAt.map(formatDate) ?? "active"
            print("  \(session.kind.rawValue): \(formatDate(session.startedAt)) → \(end)")
        }
        print("Store: schema \(payload.diagnostics.schemaVersion), \(payload.diagnostics.databaseSizeBytes) bytes")
    }

    private static func exportSamples(arguments: [String]) async throws {
        if let format = optionValue("--format", arguments: arguments) {
            guard !format.isEmpty else { throw CLIError.missingValue("--format") }
            guard format.lowercased() == "csv" else {
                throw CLIError.unsupportedFormat(format)
            }
        }

        let store = try openStore()
        let since = try parseSince(arguments: arguments)
        let limit = try parseLimit(arguments: arguments)
        let fetchedSamples = try await store.fetchBatterySamples(since: since, limit: limit)
        let sortedSamples = fetchedSamples.sorted { $0.battery.timestamp < $1.battery.timestamp }
        let csv = makeCSV(samples: sortedSamples)
        guard let output = optionValue("--output", arguments: arguments), output != "-" else {
            FileHandle.standardOutput.write(Data(csv.utf8))
            return
        }

        guard !output.isEmpty else { throw CLIError.missingValue("--output") }
        let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try Data(csv.utf8).write(to: outputURL, options: .atomic)
        print("Exported \(sortedSamples.count) samples to \(outputURL.path)")
    }

    private static func openStore() throws -> SQLiteStore {
        try SQLiteStore(databaseURL: try SQLiteStore.defaultDatabaseURL())
    }

    private static func parseSince(arguments: [String]) throws -> Date? {
        if let rawRange = optionValue("--range", arguments: arguments) {
            guard !rawRange.isEmpty else { throw CLIError.missingValue("--range") }
            switch rawRange.lowercased() {
            case "all":
                return nil
            case "2h":
                return Date().addingTimeInterval(-2 * 3_600)
            case "24h":
                return Date().addingTimeInterval(-24 * 3_600)
            case "7d":
                return Date().addingTimeInterval(-7 * 86_400)
            case "30d":
                return Date().addingTimeInterval(-30 * 86_400)
            case "90d":
                return Date().addingTimeInterval(-90 * 86_400)
            case "1y":
                return Date().addingTimeInterval(-365 * 86_400)
            default:
                throw CLIError.invalidValue(option: "--range", value: rawRange)
            }
        }

        guard let rawHours = optionValue("--hours", arguments: arguments) else { return nil }
        guard !rawHours.isEmpty else { throw CLIError.missingValue("--hours") }
        guard let hours = Double(rawHours), hours.isFinite, hours >= 0 else {
            throw CLIError.invalidValue(option: "--hours", value: rawHours)
        }
        return Date().addingTimeInterval(-hours * 3_600)
    }

    private static func parseLimit(arguments: [String]) throws -> Int {
        guard let rawLimit = optionValue("--limit", arguments: arguments) else { return 1_000 }
        guard !rawLimit.isEmpty else { throw CLIError.missingValue("--limit") }
        guard let limit = Int(rawLimit), (1...10_000).contains(limit) else {
            throw CLIError.invalidValue(option: "--limit", value: rawLimit)
        }
        return limit
    }

    private static func optionValue(_ option: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return "" }
        return arguments[valueIndex]
    }

    private static func makeCSV(samples: [StoredBatterySample]) -> String {
        let header = [
            "timestamp",
            "charge_percent",
            "temperature_celsius",
            "voltage_millivolts",
            "amperage_milliamps",
            "is_charging",
            "external_power_connected",
            "power_source_state",
            "source_quality",
            "thermal_state",
            "low_power_mode",
            "health_percent",
            "power_watts"
        ]
        var lines = [header.joined(separator: ",")]
        for sample in samples {
            let battery = sample.battery
            let values: [String?] = [
                formatDate(battery.timestamp),
                battery.chargePercent.map { String($0) },
                battery.temperatureCelsius.map { String($0) },
                battery.voltageMillivolts.map { String($0) },
                battery.amperageMilliamps.map { String($0) },
                String(battery.isCharging),
                String(battery.externalPowerConnected),
                battery.powerSourceState.rawValue,
                battery.sourceQuality.rawValue,
                sample.system?.thermalState.rawValue,
                sample.system.map { String($0.lowPowerModeEnabled) },
                BatteryMath.healthPercent(
                    nominalChargeCapacityMAh: battery.nominalChargeCapacityMAh,
                    designCapacityMAh: battery.designCapacityMAh
                ).map { String($0) },
                BatteryMath.batteryPowerWatts(
                    voltageMillivolts: battery.voltageMillivolts,
                    signedAmperageMilliamps: battery.amperageMilliamps
                ).map { String($0) }
            ]
            lines.append(values.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String?) -> String {
        guard let value else { return "" }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func describe(_ error: Error) -> String {
        if let storeError = error as? StoreError {
            return storeError.userMessage
        }
        return String(describing: error)
    }

    private static func writeJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            fail(error)
        }
    }

    private static func fail(_ error: Error, usage: String? = nil) -> Never {
        fputs("Cellium: \(describe(error))\n", stderr)
        if let usage {
            fputs("\(usage)\n", stderr)
            exit(64)
        }
        exit(1)
    }

    private static func printHelp() {
        print("Usage: cellium [status [--json] | doctor [--json] | history [--json] [--range RANGE] [--hours N] [--limit N] | export [--format csv] [--range RANGE] [--hours N] [--limit N] [--output PATH] | version | help]")
    }
}
