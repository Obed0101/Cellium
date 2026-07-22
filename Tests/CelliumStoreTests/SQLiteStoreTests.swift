import XCTest
import SQLite3
@testable import CelliumCore
@testable import CelliumStore

final class SQLiteStoreTests: XCTestCase {
    func testMigratesSchemaAndEnablesWAL() async throws {
        let store = try makeStore()

        let schemaVersion = try await store.schemaVersion()
        let sampleCount = try await store.sampleCount()

        XCTAssertEqual(schemaVersion, 1)
        XCTAssertEqual(sampleCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path + "-wal"))
    }

    func testAppendsAndFetchesSamplesInNewestFirstOrder() async throws {
        let store = try makeStore()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(60)
        let first = StoredBatterySample(
            battery: makeBattery(at: firstDate, charge: 80),
            system: makeSystem(at: firstDate)
        )
        let second = StoredBatterySample(
            battery: makeBattery(at: secondDate, charge: 79),
            system: makeSystem(at: secondDate)
        )

        let firstID = try await store.append(first)
        let secondID = try await store.append(second)
        let samples = try await store.fetchBatterySamples(limit: 10)

        let sampleCount = try await store.sampleCount()

        XCTAssertLessThan(firstID, secondID)
        XCTAssertEqual(samples, [second, first])
        XCTAssertEqual(sampleCount, 2)
    }

    func testSampleEvidenceDoesNotLoadRawPayloads() async throws {
        let store = try makeStore()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(60)

        _ = try await store.append(StoredBatterySample(battery: makeBattery(at: firstDate, charge: 80)))
        _ = try await store.append(StoredBatterySample(battery: makeBattery(at: secondDate, charge: 79)))

        let evidence = try await store.sampleEvidence()

        XCTAssertEqual(evidence.sampleCount, 2)
        XCTAssertEqual(evidence.observedDays, 1)
        XCTAssertEqual(evidence.firstSampleDate, firstDate)
        XCTAssertEqual(evidence.lastSampleDate, secondDate)
    }

    func testBatchPersistsMinuteQuarterHourAndDailyAggregates() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let samples = [
            StoredBatterySample(battery: makeBattery(at: start, charge: 80)),
            StoredBatterySample(battery: makeBattery(at: start.addingTimeInterval(30), charge: 78)),
            StoredBatterySample(battery: makeBattery(at: start.addingTimeInterval(60), charge: 79))
        ]

        _ = try await store.appendBatch(samples)

        let minute = try await store.fetchAggregates(resolution: .minute)
        let quarterHour = try await store.fetchAggregates(resolution: .quarterHour)
        let day = try await store.fetchAggregates(resolution: .day)

        XCTAssertEqual(minute.count, 2)
        XCTAssertEqual(minute[0].sampleCount, 1)
        XCTAssertEqual(minute[0].minimumChargePercent, 79)
        XCTAssertEqual(minute[0].maximumChargePercent, 79)
        XCTAssertEqual(minute[1].sampleCount, 2)
        XCTAssertEqual(minute[1].minimumChargePercent, 78)
        XCTAssertEqual(minute[1].maximumChargePercent, 80)
        XCTAssertEqual(minute[1].averageChargePercent ?? -1, 79, accuracy: 0.001)
        XCTAssertEqual(quarterHour.count, 1)
        XCTAssertEqual(quarterHour[0].sampleCount, 3)
        XCTAssertEqual(quarterHour[0].averageChargePercent ?? -1, 79, accuracy: 0.001)
        XCTAssertEqual(day.count, 1)
        XCTAssertEqual(day[0].sampleCount, 3)
    }

    func testAggregatesPersistPowerAndSystemMetrics() async throws {
        let store = try makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        let battery = BatterySnapshot(
            timestamp: timestamp,
            chargePercent: 80,
            voltageMillivolts: 12_000,
            amperageMilliamps: -1_000,
            sourceQuality: .measured,
            powerSourceState: .battery
        )
        let system = SystemSnapshot(
            timestamp: timestamp,
            thermalState: .nominal,
            lowPowerModeEnabled: false,
            cpuUsagePercent: 25,
            memoryUsedPercent: 61,
            diskUsedPercent: 74,
            diskReadBytesPerSecond: 1_024,
            diskWriteBytesPerSecond: 2_048
        )

        _ = try await store.appendBatch([
            StoredBatterySample(battery: battery, system: system)
        ])

        let aggregate = try await store.fetchAggregates(resolution: .minute)

        XCTAssertEqual(aggregate.count, 1)
        XCTAssertEqual(aggregate[0].averageBatteryPowerWatts ?? -1, 12, accuracy: 0.001)
        XCTAssertEqual(aggregate[0].averageCPUUsagePercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(aggregate[0].averageMemoryUsedPercent ?? -1, 61, accuracy: 0.001)
        XCTAssertEqual(aggregate[0].averageDiskUsedPercent ?? -1, 74, accuracy: 0.001)
        XCTAssertEqual(aggregate[0].averageDiskReadBytesPerSecond ?? -1, 1_024, accuracy: 0.001)
        XCTAssertEqual(aggregate[0].averageDiskWriteBytesPerSecond ?? -1, 2_048, accuracy: 0.001)
    }

    func testNearZeroBatteryPowerIsUnavailableInsteadOfFakeZero() async throws {
        let store = try makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        let battery = BatterySnapshot(
            timestamp: timestamp,
            chargePercent: 80,
            voltageMillivolts: 12_000,
            amperageMilliamps: 1,
            sourceQuality: .measured,
            powerSourceState: .battery
        )

        _ = try await store.appendBatch([StoredBatterySample(battery: battery)])

        let aggregate = try await store.fetchAggregates(resolution: .minute)

        XCTAssertEqual(aggregate[0].powerSampleCount, 0)
        XCTAssertNil(aggregate[0].averageBatteryPowerWatts)
    }

    func testAggregatesMergeAcrossSeparateBatches() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSince1970: 1_700_000_040)

        _ = try await store.append(
            StoredBatterySample(battery: makeBattery(at: start, charge: 81))
        )
        _ = try await store.append(
            StoredBatterySample(
                battery: makeBattery(at: start.addingTimeInterval(10), charge: 79)
            )
        )

        let aggregates = try await store.fetchAggregates(resolution: .minute)

        XCTAssertEqual(aggregates.count, 1)
        XCTAssertEqual(aggregates[0].sampleCount, 2)
        XCTAssertEqual(aggregates[0].averageChargePercent ?? -1, 80, accuracy: 0.001)
    }

    func testFetchFiltersByTimestampAndLimit() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in 0..<3 {
            let timestamp = start.addingTimeInterval(Double(offset) * 60)
            _ = try await store.append(
                StoredBatterySample(battery: makeBattery(at: timestamp, charge: 80 - offset))
            )
        }

        let filtered = try await store.fetchBatterySamples(
            since: start.addingTimeInterval(60),
            limit: 1
        )

        let emptyResult = try await store.fetchBatterySamples(limit: 0)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].battery.chargePercent, 78)
        XCTAssertEqual(emptyResult, [])
    }

    func testRetentionRemovesOnlyExpiredRawSamples() async throws {
        let store = try makeStore(
            configuration: StoreConfiguration(
                rawRetentionDays: 1,
                minuteRetentionDays: 1,
                quarterHourRetentionDays: 1,
                dailyRetentionDays: 1
            )
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.append(
            StoredBatterySample(
                battery: makeBattery(at: now.addingTimeInterval(-2 * 86_400), charge: 50)
            )
        )
        _ = try await store.append(
            StoredBatterySample(
                battery: makeBattery(at: now.addingTimeInterval(-3_600), charge: 49)
            )
        )

        let deleted = try await store.applyRetention(now: now)

        let remainingCount = try await store.sampleCount()
        let remainingSamples = try await store.fetchBatterySamples()

        XCTAssertEqual(deleted, 4)
        XCTAssertEqual(remainingCount, 1)
        XCTAssertEqual(remainingSamples[0].battery.chargePercent, 49)
    }

    func testRetentionCapsRawSampleCount() async throws {
        let store = try makeStore(
            configuration: StoreConfiguration(
                rawRetentionDays: 7,
                rawSampleLimit: 1_000,
                minuteRetentionDays: 90,
                quarterHourRetentionDays: 730
            )
        )
        let now = Date()
        let samples = (0...1_000).map { index in
            StoredBatterySample(
                battery: makeBattery(
                    at: now.addingTimeInterval(Double(index - 1_000)),
                    charge: 50
                )
            )
        }

        _ = try await store.appendBatch(samples)
        let deleted = try await store.applyRetention(now: now)
        let remainingCount = try await store.sampleCount()

        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(remainingCount, 1_000)
    }

    func testCoordinatorFlushesSamplesThroughStoreBatchSink() async throws {
        let store = try makeStore()
        let source = SnapshotSource(
            readBattery: { date in
                BatterySnapshot(
                    timestamp: date,
                    chargePercent: 72,
                    sourceQuality: .measured,
                    powerSourceState: .battery
                )
            },
            readSystem: { date in
                SystemSnapshot(
                    timestamp: date,
                    thermalState: .nominal,
                    lowPowerModeEnabled: true
                )
            }
        )
        let coordinator = SamplingCoordinator(
            source: source,
            sink: store,
            flushBatchSize: 2
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        _ = await coordinator.sampleNow(at: start)
        _ = await coordinator.sampleNow(at: start.addingTimeInterval(30))
        let pendingBeforeFlush = await coordinator.pendingSampleCount()

        try await coordinator.flush()

        let pendingAfterFlush = await coordinator.pendingSampleCount()
        let sampleCount = try await store.sampleCount()
        let fetchedSamples = try await store.fetchBatterySamples()

        XCTAssertEqual(pendingBeforeFlush, 2)
        XCTAssertEqual(pendingAfterFlush, 0)
        XCTAssertEqual(sampleCount, 2)
        XCTAssertEqual(fetchedSamples.count, 2)
    }

    func testCoordinatorFlushesCompletedSessionsAtomicallyWithSamples() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = SnapshotSource(
            readBattery: { date in
                let charging = date < start.addingTimeInterval(120)
                return BatterySnapshot(
                    timestamp: date,
                    chargePercent: charging ? 80 : 79,
                    isCharging: charging,
                    externalPowerConnected: charging,
                    sourceQuality: .measured,
                    powerSourceState: charging ? .adapter : .battery
                )
            },
            readSystem: { date in
                SystemSnapshot(timestamp: date, thermalState: .nominal, lowPowerModeEnabled: false)
            }
        )
        let coordinator = SamplingCoordinator(
            source: source,
            sink: store,
            flushBatchSize: 100
        )

        _ = await coordinator.sampleNow(at: start)
        _ = await coordinator.sampleNow(at: start.addingTimeInterval(60))
        _ = await coordinator.sampleNow(at: start.addingTimeInterval(120))
        let pendingSessions = await coordinator.pendingSessionCount()
        XCTAssertEqual(pendingSessions, 1)

        try await coordinator.stopAndFlush(at: start.addingTimeInterval(180))

        let sessions = try await store.fetchSessions()
        let sampleCount = try await store.sampleCount()
        XCTAssertEqual(sampleCount, 3)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.kind), [.discharging, .charging])
        XCTAssertEqual(sessions.map(\.sampleCount), [1, 2])
    }

    func testReportsStoreDiagnostics() async throws {
        let store = try makeStore()

        let diagnostics = try await store.diagnostics()

        XCTAssertEqual(diagnostics.schemaVersion, 1)
        XCTAssertGreaterThan(diagnostics.databaseSizeBytes, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.walSizeBytes, 0)
    }

    func testRejectsCorruptDatabaseWithDiagnosticError() throws {
        let databaseURL = try makeDatabaseURL()
        try Data("not a sqlite database".utf8).write(to: databaseURL)

        XCTAssertThrowsError(try SQLiteStore(databaseURL: databaseURL)) { error in
            XCTAssertEqual(error as? StoreError, .corrupted)
        }
    }

    func testRejectsUnsupportedSchemaVersion() throws {
        let databaseURL = try makeDatabaseURL()
        var connection: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        defer {
            if let connection {
                sqlite3_close_v2(connection)
            }
        }
        XCTAssertEqual(openResult, SQLITE_OK)
        guard openResult == SQLITE_OK, let connection else { return }

        let schemaSQL = """
        CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at REAL NOT NULL);
        INSERT INTO schema_migrations (version, applied_at) VALUES (2, 0);
        """
        XCTAssertEqual(sqlite3_exec(connection, schemaSQL, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try SQLiteStore(databaseURL: databaseURL)) { error in
            XCTAssertEqual(error as? StoreError, .unsupportedSchema(version: 2))
        }
    }

    func testClassifiesSQLiteFailureModes() {
        XCTAssertEqual(
            SQLiteStore.classifySQLiteError(code: SQLITE_BUSY, message: "busy"),
            .locked
        )
        XCTAssertEqual(
            SQLiteStore.classifySQLiteError(code: SQLITE_FULL, message: "full"),
            .diskFull
        )
        XCTAssertEqual(
            SQLiteStore.classifySQLiteError(code: SQLITE_CORRUPT, message: "corrupt"),
            .corrupted
        )
    }

    private func makeStore(
        configuration: StoreConfiguration = StoreConfiguration()
    ) throws -> SQLiteStore {
        try SQLiteStore(databaseURL: makeDatabaseURL(), configuration: configuration)
    }

    private func makeDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CelliumStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("Cellium.sqlite", isDirectory: false)
    }

    private func makeBattery(at date: Date, charge: Int) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: date,
            chargePercent: charge,
            nominalChargeCapacityMAh: 6_000,
            designCapacityMAh: 6_249,
            temperatureCelsius: 30,
            cycleCount: 149,
            isCharging: false,
            externalPowerConnected: false,
            sourceQuality: .measured,
            powerSourceState: .battery
        )
    }

    private func makeSystem(at date: Date) -> SystemSnapshot {
        SystemSnapshot(
            timestamp: date,
            thermalState: .nominal,
            lowPowerModeEnabled: false
        )
    }
}
