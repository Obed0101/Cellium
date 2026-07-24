import XCTest
import SQLite3
@testable import CelliumCore
@testable import CelliumStore

final class SQLiteStoreTests: XCTestCase {
    func testMigratesSchemaAndEnablesWAL() async throws {
        let store = try makeStore()

        let schemaVersion = try await store.schemaVersion()
        let sampleCount = try await store.sampleCount()
        let alertCount = try await store.alertCount()

        XCTAssertEqual(schemaVersion, 4)
        XCTAssertEqual(sampleCount, 0)
        XCTAssertEqual(alertCount, 0)
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

    func testFetchAggregatesFiltersByTimestampBounds() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSince1970: 1_700_000_040)

        _ = try await store.appendBatch([
            StoredBatterySample(battery: makeBattery(at: start, charge: 80)),
            StoredBatterySample(battery: makeBattery(at: start.addingTimeInterval(60), charge: 79)),
            StoredBatterySample(battery: makeBattery(at: start.addingTimeInterval(120), charge: 78))
        ])

        let bounded = try await store.fetchAggregates(
            resolution: .minute,
            since: start.addingTimeInterval(60),
            until: start.addingTimeInterval(120),
            limit: 10
        )

        XCTAssertEqual(bounded.count, 1)
        XCTAssertEqual(bounded[0].bucketStart, start.addingTimeInterval(60))
        XCTAssertEqual(bounded[0].averageChargePercent ?? -1, 79, accuracy: 0.001)
    }

    func testPersistsProcessSamplesNewestFirst() async throws {
        let store = try makeStore()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(60)
        let first = StoredProcessSample(
            processID: 10,
            name: "First App",
            kind: .application,
            timestamp: firstDate,
            cpuPercent: 12.5,
            residentMemoryBytes: 128 * 1_024 * 1_024,
            memoryPercent: 2.5,
            estimatedBatteryPercentPerMinute: 0.03
        )
        let second = StoredProcessSample(
            processID: 20,
            name: "Second App",
            kind: .daemon,
            timestamp: secondDate,
            cpuPercent: 32,
            residentMemoryBytes: 256 * 1_024 * 1_024,
            memoryPercent: 5,
            estimatedBatteryPercentPerMinute: nil
        )

        let written = try await store.appendProcessSamples([first, second])
        let samples = try await store.fetchProcessSamples(limit: 10)
        let filtered = try await store.fetchProcessSamples(since: secondDate, limit: 10)
        let count = try await store.processSampleCount()

        XCTAssertEqual(written, 2)
        XCTAssertEqual(samples, [second, first])
        XCTAssertEqual(filtered, [second])
        XCTAssertEqual(count, 2)
    }

    func testLegacyProcessSamplesDecodeWithoutKind() throws {
        let sample = StoredProcessSample(
            processID: 10,
            name: "Legacy App",
            kind: .application,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            cpuPercent: 12.5
        )
        let encoded = try JSONEncoder().encode(sample)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "kind")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(StoredProcessSample.self, from: legacyData)

        XCTAssertEqual(decoded.kind, .process)
        XCTAssertEqual(decoded.name, "Legacy App")
    }

    func testPersistsAlertEventsNewestFirst() async throws {
        let store = try makeStore()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(60)
        let first = StoredAlertEvent(
            identifier: "discharge",
            occurredAt: firstDate,
            measurements: ["percentPerMinute": 0.42]
        )
        let second = StoredAlertEvent(
            identifier: "memory:42",
            occurredAt: secondDate,
            subject: "Example",
            measurements: ["memoryPercent": 22]
        )

        let firstID = try await store.appendAlertEvent(first)
        let secondID = try await store.appendAlertEvent(second)
        let events = try await store.fetchAlertEvents(limit: 10)
        let alertCount = try await store.alertCount()
        let filteredEvents = try await store.fetchAlertEvents(since: secondDate, limit: 10)

        XCTAssertLessThan(firstID, secondID)
        XCTAssertEqual(events, [second, first])
        XCTAssertEqual(alertCount, 2)
        XCTAssertEqual(filteredEvents, [second])
    }

    func testClearAlertEventsRemovesPersistedAlerts() async throws {
        let store = try makeStore()
        _ = try await store.appendAlertEvent(
            StoredAlertEvent(identifier: "first", occurredAt: Date())
        )
        _ = try await store.appendAlertEvent(
            StoredAlertEvent(identifier: "second", occurredAt: Date())
        )

        try await store.clearAlertEvents()

        let events = try await store.fetchAlertEvents()
        let count = try await store.alertCount()
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testClearIntelligenceAnalysesRemovesPersistedLog() async throws {
        let store = try makeStore()
        let analysis = StoredIntelligenceAnalysis(
            requestedAt: Date(),
            kind: .analysis,
            provider: "openRouter",
            model: "test/model",
            languageCode: "en",
            prompt: "[system]\nRespond in English",
            status: .succeeded
        )

        _ = try await store.appendIntelligenceAnalysis(analysis)
        try await store.clearIntelligenceAnalyses()

        let logs = try await store.fetchIntelligenceAnalyses()
        let count = try await store.intelligenceAnalysisCount()
        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testRejectsInvalidAlertMeasurements() async throws {
        let store = try makeStore()
        let invalid = StoredAlertEvent(
            identifier: "invalid",
            occurredAt: Date(),
            measurements: ["value": .nan]
        )

        do {
            _ = try await store.appendAlertEvent(invalid)
            XCTFail("Expected invalid alert measurements to be rejected")
        } catch {
            XCTAssertEqual(error as? StoreError, .invalidData)
        }
        let alertCount = try await store.alertCount()
        XCTAssertEqual(alertCount, 0)
    }

    func testRetentionRemovesExpiredAlertEvents() async throws {
        let store = try makeStore(configuration: StoreConfiguration(alertRetentionDays: 1))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.appendAlertEvent(
            StoredAlertEvent(
                identifier: "old",
                occurredAt: now.addingTimeInterval(-2 * 86_400)
            )
        )
        _ = try await store.appendAlertEvent(
            StoredAlertEvent(
                identifier: "recent",
                occurredAt: now.addingTimeInterval(-3_600)
            )
        )

        let deleted = try await store.applyRetention(now: now)
        let alertCount = try await store.alertCount()
        let remainingEvents = try await store.fetchAlertEvents()

        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(alertCount, 1)
        XCTAssertEqual(remainingEvents[0].identifier, "recent")
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

        XCTAssertEqual(deleted, 6)
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

        XCTAssertEqual(diagnostics.schemaVersion, 4)
        XCTAssertGreaterThan(diagnostics.databaseSizeBytes, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.walSizeBytes, 0)
    }

    func testPersistsCycleUsageAndRestoresTrackerAcrossStoreInstances() async throws {
        let databaseURL = try makeDatabaseURL()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let firstStore = try SQLiteStore(databaseURL: databaseURL)
        _ = try await firstStore.appendBatch([
            makeCycleSample(at: start, cycleCount: 150),
            makeCycleSample(at: start.addingTimeInterval(300), cycleCount: 151)
        ])

        let secondStore = try SQLiteStore(databaseURL: databaseURL)
        _ = try await secondStore.append(
            makeCycleSample(at: start.addingTimeInterval(600), cycleCount: 151)
        )

        let daily = try await secondStore.fetchCycleUsage(resolution: .day, limit: 10)
        let quarterHours = try await secondStore.fetchCycleUsage(resolution: .quarterHour, limit: 10)
        XCTAssertEqual(daily.count, 1)
        XCTAssertEqual(daily.first?.equivalentCycles ?? 0, 1.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(daily.first?.hardwareCycleDelta, 1)
        XCTAssertEqual(quarterHours.count, 2)
        let dailyCount = try await secondStore.cycleUsageCount(resolution: .day)
        XCTAssertEqual(dailyCount, 1)
    }

    func testDailyCycleHistoryPreservesMeasuredCounterTransitions() async throws {
        let store = try makeStore()
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_700_006_400)
        let samples = (0...3).map { offset in
            makeCycleSample(
                at: calendar.date(byAdding: .day, value: offset, to: start)!,
                cycleCount: 150 + offset
            )
        }

        _ = try await store.appendBatch(samples)
        let daily = try await store.fetchCycleUsage(resolution: .day, limit: 10).reversed()

        XCTAssertEqual(daily.map(\.lastCycleCount), [150, 151, 152, 153])
        XCTAssertEqual(daily.map(\.hardwareCycleDelta), [0, 1, 1, 1])
        XCTAssertEqual(daily.dropFirst().map(\.hardwareCycleDeltaDuringGap), [1, 1, 1])
    }

    func testMigratesVersionThreeAndBackfillsCycleUsage() async throws {
        let databaseURL = try makeDatabaseURL()
        var connection: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path,
                &connection,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            ),
            SQLITE_OK
        )
        guard let connection else { return }
        defer { sqlite3_close_v2(connection) }
        XCTAssertEqual(sqlite3_exec(
            connection,
            """
            CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at REAL NOT NULL);
            INSERT INTO schema_migrations (version, applied_at) VALUES (3, 0);
            CREATE TABLE battery_samples_raw (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                payload TEXT NOT NULL
            );
            """,
            nil,
            nil,
            nil
        ), SQLITE_OK)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            makeCycleSample(at: start, cycleCount: 150),
            makeCycleSample(at: start.addingTimeInterval(300), cycleCount: 151),
            makeCycleSample(at: start.addingTimeInterval(600), cycleCount: 152)
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        for sample in samples {
            let payload = String(data: try encoder.encode(sample), encoding: .utf8)!
            var statement: OpaquePointer?
            XCTAssertEqual(
                sqlite3_prepare_v2(
                    connection,
                    "INSERT INTO battery_samples_raw (timestamp, payload) VALUES (?, ?);",
                    -1,
                    &statement,
                    nil
                ),
                SQLITE_OK
            )
            guard let statement else { continue }
            sqlite3_bind_double(statement, 1, sample.battery.timestamp.timeIntervalSince1970)
            _ = payload.withCString { pointer in
                sqlite3_bind_text(statement, 2, pointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_finalize(statement)
        }
        let store = try SQLiteStore(databaseURL: databaseURL)
        let schemaVersion = try await store.schemaVersion()
        XCTAssertEqual(schemaVersion, 4)
        let daily = try await store.fetchCycleUsage(resolution: .day, limit: 10)
        XCTAssertEqual(daily.count, 1)
        XCTAssertEqual(daily.first?.hardwareCycleDelta, 2)
        XCTAssertEqual(daily.first?.equivalentCycles ?? 0, 1.0 / 6.0, accuracy: 0.0001)
    }

    func testMigratesExistingSchemaVersionOneToAlertEvents() async throws {
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
        guard openResult == SQLITE_OK, let openedConnection = connection else { return }

        let schemaSQL = """
        CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at REAL NOT NULL);
        INSERT INTO schema_migrations (version, applied_at) VALUES (1, 0);
        """
        XCTAssertEqual(sqlite3_exec(openedConnection, schemaSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close_v2(openedConnection)
        connection = nil

        let store = try SQLiteStore(databaseURL: databaseURL)
        let schemaVersion = try await store.schemaVersion()
        XCTAssertEqual(schemaVersion, 4)
        _ = try await store.appendAlertEvent(
            StoredAlertEvent(identifier: "migrated", occurredAt: Date())
        )
        let alertCount = try await store.alertCount()
        XCTAssertEqual(alertCount, 1)
    }

    func testPersistsAndUpdatesIntelligenceAnalysisLogs() async throws {
        let store = try makeStore()
        let requestedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let running = StoredIntelligenceAnalysis(
            requestedAt: requestedAt,
            kind: .analysis,
            provider: "openRouter",
            model: "test/model",
            languageCode: "es",
            prompt: "[system]\nResponde en español",
            status: .running
        )

        _ = try await store.appendIntelligenceAnalysis(running)
        let completed = StoredIntelligenceAnalysis(
            id: running.id,
            requestedAt: requestedAt,
            completedAt: requestedAt.addingTimeInterval(4),
            kind: .analysis,
            provider: "openRouter",
            model: "test/model",
            languageCode: "es",
            prompt: running.prompt,
            response: "La batería está estable.",
            status: .succeeded,
            title: "Batería estable",
            severity: "info",
            confidence: "medium",
            evidence: ["Nivel medido: 80%"],
            recommendations: ["Continúa observando la tendencia."]
        )

        try await store.updateIntelligenceAnalysis(completed)
        let logs = try await store.fetchIntelligenceAnalyses()
        let analysisCount = try await store.intelligenceAnalysisCount()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first, completed)
        XCTAssertEqual(analysisCount, 1)
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
        INSERT INTO schema_migrations (version, applied_at) VALUES (5, 0);
        """
        XCTAssertEqual(sqlite3_exec(connection, schemaSQL, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try SQLiteStore(databaseURL: databaseURL)) { error in
            XCTAssertEqual(error as? StoreError, .unsupportedSchema(version: 5))
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

    private func makeCycleSample(at date: Date, cycleCount: Int) -> StoredBatterySample {
        StoredBatterySample(
            battery: BatterySnapshot(
                timestamp: date,
                chargePercent: 80,
                currentCapacityMAh: 4_000,
                nominalChargeCapacityMAh: 5_000,
                designCapacityMAh: 5_200,
                rawCurrentCapacityMAh: 4_000,
                rawMaxCapacityMAh: 5_000,
                voltageMillivolts: 12_000,
                amperageMilliamps: -5_000,
                instantAmperageMilliamps: -5_000,
                cycleCount: cycleCount,
                designCycleCount: 1_000,
                isCharging: false,
                externalPowerConnected: false,
                sourceQuality: .measured,
                powerSourceState: .battery
            ),
            system: makeSystem(at: date)
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
