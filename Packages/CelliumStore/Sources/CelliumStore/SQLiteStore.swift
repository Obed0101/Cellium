import Foundation
import SQLite3
import CelliumCore

public actor SQLiteStore {
    public nonisolated let databaseURL: URL
    public nonisolated let configuration: StoreConfiguration

    private var connection: SQLiteHandle?
    private var lastRetentionRun: Date?
    private var cycleUsageTracker: CycleUsageTracker

    public init(databaseURL: URL, configuration: StoreConfiguration = StoreConfiguration()) throws {
        self.databaseURL = databaseURL
        self.configuration = configuration
        self.connection = nil
        self.lastRetentionRun = nil
        self.cycleUsageTracker = CycleUsageTracker()

        do {
            try Self.createParentDirectory(for: databaseURL)
        } catch {
            throw StoreError.unavailable
        }

        var openedConnection: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &openedConnection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let openedConnection else {
            let message = openedConnection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            let error = Self.classifySQLiteError(code: result, message: message)
            if let openedConnection {
                sqlite3_close_v2(openedConnection)
            }
            throw error
        }

        self.connection = SQLiteHandle(openedConnection)

        do {
            try Self.configure(openedConnection)
            try Self.migrate(openedConnection)
            if let state = try Self.loadCycleUsageTrackerState(connection: openedConnection) {
                self.cycleUsageTracker = CycleUsageTracker(state: state)
            }
        } catch {
            throw error
        }
    }

    public static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.unavailable
        }

        return applicationSupport
            .appendingPathComponent("Cellium", isDirectory: true)
            .appendingPathComponent("Cellium.sqlite", isDirectory: false)
    }

    public func append(_ sample: StoredBatterySample) throws -> Int64 {
        guard let id = try appendBatchReturningIDs([sample]).first else {
            throw StoreError.invalidData
        }
        return id
    }

    @discardableResult
    public func appendBatch(_ samples: [StoredBatterySample]) throws -> Int {
        try appendBatchReturningIDs(samples).count
    }

    private func appendBatchReturningIDs(
        _ samples: [StoredBatterySample],
        sessions: [BatterySession] = []
    ) throws -> [Int64] {
        guard !samples.isEmpty || !sessions.isEmpty else { return [] }

        let connection = try requireConnection()
        var nextCycleUsageTracker = cycleUsageTracker
        let cycleUsageUpdates = nextCycleUsageTracker.ingest(samples)
        var ids: [Int64] = []
        do {
            try Self.execute("BEGIN IMMEDIATE;", connection: connection)

            if !samples.isEmpty {
                let statement = try Self.prepare(
                    "INSERT INTO battery_samples_raw (timestamp, payload) VALUES (?, ?);",
                    connection: connection
                )
                defer { sqlite3_finalize(statement) }

                for sample in samples {
                    let payload = try Self.encode(sample)
                    guard sqlite3_bind_double(statement, 1, sample.battery.timestamp.timeIntervalSince1970) == SQLITE_OK else {
                        throw Self.sqliteError(connection)
                    }

                    let bindResult = payload.withCString {
                        sqlite3_bind_text(statement, 2, $0, -1, Self.sqliteTransient)
                    }
                    guard bindResult == SQLITE_OK else {
                        throw Self.sqliteError(connection)
                    }
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw Self.sqliteError(connection)
                    }

                    ids.append(sqlite3_last_insert_rowid(connection))
                    guard sqlite3_reset(statement) == SQLITE_OK,
                          sqlite3_clear_bindings(statement) == SQLITE_OK else {
                        throw Self.sqliteError(connection)
                    }
                }

                for aggregate in try Self.aggregateBatches(samples) {
                    try Self.upsert(aggregate, connection: connection)
                }
                for bucket in cycleUsageUpdates {
                    try Self.upsertCycleUsage(bucket, connection: connection)
                }
                try Self.saveCycleUsageTrackerState(
                    nextCycleUsageTracker.state,
                    connection: connection
                )
            }

            try Self.insertSessions(sessions, connection: connection)
            try Self.execute("COMMIT;", connection: connection)
            cycleUsageTracker = nextCycleUsageTracker
        } catch {
            try? Self.execute("ROLLBACK;", connection: connection)
            throw error
        }

        return ids
    }

    @discardableResult
    public func appendSessions(_ sessions: [BatterySession]) throws -> Int {
        _ = try appendBatchReturningIDs([], sessions: sessions)
        return sessions.count
    }

    public func fetchBatterySamples(
        since: Date? = nil,
        limit: Int = 100
    ) throws -> [StoredBatterySample] {
        guard limit > 0 else { return [] }

        let connection = try requireConnection()
        let sql: String
        if since == nil {
            sql = """
            SELECT payload
            FROM battery_samples_raw
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT payload
            FROM battery_samples_raw
            WHERE timestamp >= ?
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        }

        let statement = try Self.prepare(sql, connection: connection)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if let since {
            guard sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }

        let boundedLimit = min(limit, 10_000)
        guard sqlite3_bind_int(statement, bindIndex, Int32(boundedLimit)) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }

        var samples: [StoredBatterySample] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw StoreError.invalidData
                }
                let byteCount = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: text, count: byteCount)
                do {
                    samples.append(try decoder.decode(StoredBatterySample.self, from: data))
                } catch {
                    throw StoreError.invalidData
                }
            case SQLITE_DONE:
                return samples
            default:
                throw Self.sqliteError(connection)
            }
        }
    }

    @discardableResult
    public func appendProcessSamples(_ samples: [StoredProcessSample]) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        guard samples.allSatisfy(Self.isValidProcessSample) else {
            throw StoreError.invalidData
        }

        let connection = try requireConnection()
        do {
            try Self.execute("BEGIN IMMEDIATE;", connection: connection)
            let statement = try Self.prepare(
                "INSERT INTO process_samples (timestamp, payload) VALUES (?, ?);",
                connection: connection
            )
            defer { sqlite3_finalize(statement) }

            for sample in samples {
                guard sqlite3_bind_double(statement, 1, sample.timestamp.timeIntervalSince1970) == SQLITE_OK else {
                    throw Self.sqliteError(connection)
                }
                let payload = try Self.encode(sample)
                let bindResult = payload.withCString {
                    sqlite3_bind_text(statement, 2, $0, -1, Self.sqliteTransient)
                }
                guard bindResult == SQLITE_OK,
                      sqlite3_step(statement) == SQLITE_DONE else {
                    throw Self.sqliteError(connection)
                }
                guard sqlite3_reset(statement) == SQLITE_OK,
                      sqlite3_clear_bindings(statement) == SQLITE_OK else {
                    throw Self.sqliteError(connection)
                }
            }

            try Self.execute("COMMIT;", connection: connection)
        } catch {
            try? Self.execute("ROLLBACK;", connection: connection)
            throw error
        }
        return samples.count
    }

    public func fetchProcessSamples(
        since: Date? = nil,
        limit: Int = 100
    ) throws -> [StoredProcessSample] {
        guard limit > 0 else { return [] }

        let connection = try requireConnection()
        let sql: String
        if since == nil {
            sql = """
            SELECT payload
            FROM process_samples
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT payload
            FROM process_samples
            WHERE timestamp >= ?
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        }

        let statement = try Self.prepare(sql, connection: connection)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if let since {
            guard sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }
        guard sqlite3_bind_int(statement, bindIndex, Int32(min(limit, 10_000))) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var samples: [StoredProcessSample] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw StoreError.invalidData
                }
                let data = Data(
                    bytes: text,
                    count: Int(sqlite3_column_bytes(statement, 0))
                )
                do {
                    samples.append(try decoder.decode(StoredProcessSample.self, from: data))
                } catch {
                    throw StoreError.invalidData
                }
            case SQLITE_DONE:
                return samples
            default:
                throw Self.sqliteError(connection)
            }
        }
    }

    public func processSampleCount() throws -> Int {
        try Self.scalarInt(
            "SELECT COUNT(*) FROM process_samples;",
            connection: requireConnection()
        )
    }

    public func fetchAggregates(
        resolution: BatteryAggregateResolution,
        since: Date? = nil,
        until: Date? = nil,
        limit: Int = 100
    ) throws -> [BatteryAggregate] {
        guard limit > 0 else { return [] }

        let connection = try requireConnection()
        let table = Self.aggregateTable(for: resolution)
        let sql: String
        switch (since, until) {
        case (nil, nil):
            sql = """
            SELECT payload
            FROM \(table)
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        case (.some, nil):
            sql = """
            SELECT payload
            FROM \(table)
            WHERE timestamp >= ?
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        case (nil, .some):
            sql = """
            SELECT payload
            FROM \(table)
            WHERE timestamp < ?
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        case (.some, .some):
            sql = """
            SELECT payload
            FROM \(table)
            WHERE timestamp >= ? AND timestamp < ?
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        }

        let statement = try Self.prepare(sql, connection: connection)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if let since {
            guard sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }
        if let until {
            guard sqlite3_bind_double(statement, bindIndex, until.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }

        let boundedLimit = min(limit, 10_000)
        guard sqlite3_bind_int(statement, bindIndex, Int32(boundedLimit)) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }

        var aggregates: [BatteryAggregate] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw StoreError.invalidData
                }
                let byteCount = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: text, count: byteCount)
                do {
                    let aggregate = try decoder.decode(BatteryAggregate.self, from: data)
                    guard aggregate.resolution == resolution else {
                        throw StoreError.invalidData
                    }
                    aggregates.append(aggregate)
                } catch let error as StoreError {
                    throw error
                } catch {
                    throw StoreError.invalidData
                }
            case SQLITE_DONE:
                return aggregates
            default:
                throw Self.sqliteError(connection)
            }
        }
    }

    public func fetchCycleUsage(
        resolution: CycleUsageResolution,
        since: Date? = nil,
        until: Date? = nil,
        limit: Int = 100
    ) throws -> [StoredCycleUsageBucket] {
        guard limit > 0 else { return [] }
        let connection = try requireConnection()
        let table = Self.cycleUsageTable(for: resolution)
        let predicates = [
            since.map { _ in "timestamp >= ?" },
            until.map { _ in "timestamp < ?" }
        ].compactMap { $0 }
        let whereClause = predicates.isEmpty ? "" : "WHERE " + predicates.joined(separator: " AND ")
        let statement = try Self.prepare(
            """
            SELECT payload
            FROM \(table)
            \(whereClause)
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """,
            connection: connection
        )
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if let since {
            guard sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }
        if let until {
            guard sqlite3_bind_double(statement, bindIndex, until.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }
        guard sqlite3_bind_int(statement, bindIndex, Int32(min(limit, 10_000))) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }

        var buckets: [StoredCycleUsageBucket] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw StoreError.invalidData
                }
                let data = Data(bytes: text, count: Int(sqlite3_column_bytes(statement, 0)))
                do {
                    let bucket = try decoder.decode(StoredCycleUsageBucket.self, from: data)
                    guard bucket.resolution == resolution else { throw StoreError.invalidData }
                    buckets.append(bucket)
                } catch let error as StoreError {
                    throw error
                } catch {
                    throw StoreError.invalidData
                }
            case SQLITE_DONE:
                return buckets
            default:
                throw Self.sqliteError(connection)
            }
        }
    }

    public func cycleUsageCount(resolution: CycleUsageResolution) throws -> Int {
        try Self.scalarInt(
            "SELECT COUNT(*) FROM \(Self.cycleUsageTable(for: resolution));",
            connection: requireConnection()
        )
    }

    public func fetchSessions(
        kind: BatterySessionKind? = nil,
        since: Date? = nil,
        limit: Int = 100
    ) throws -> [BatterySession] {
        guard limit > 0 else { return [] }
        let connection = try requireConnection()
        let tables: [String]
        if let kind {
            tables = [Self.sessionTable(for: kind)]
        } else {
            tables = ["charge_sessions", "discharge_sessions"]
        }

        var sessions: [BatterySession] = []
        for table in tables {
            sessions.append(contentsOf: try Self.fetchSessions(
                from: table,
                since: since,
                limit: min(limit, 10_000),
                connection: connection
            ))
        }

        return sessions
            .filter { kind == nil || $0.kind == kind }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(min(limit, 10_000))
            .map { $0 }
    }

    @discardableResult
    public func appendAlertEvent(_ event: StoredAlertEvent) throws -> Int64 {
        guard !event.identifier.isEmpty,
              event.measurements.values.allSatisfy({ $0.isFinite }) else {
            throw StoreError.invalidData
        }

        let connection = try requireConnection()
        let statement = try Self.prepare(
            "INSERT INTO alert_events (timestamp, payload) VALUES (?, ?);",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_double(statement, 1, event.occurredAt.timeIntervalSince1970) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }
        let payload = try Self.encode(event)
        let bindResult = payload.withCString {
            sqlite3_bind_text(statement, 2, $0, -1, Self.sqliteTransient)
        }
        guard bindResult == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw Self.sqliteError(connection)
        }
        return sqlite3_last_insert_rowid(connection)
    }

    public func fetchAlertEvents(
        since: Date? = nil,
        limit: Int = 100
    ) throws -> [StoredAlertEvent] {
        guard limit > 0 else { return [] }

        let connection = try requireConnection()
        let sql: String
        if since == nil {
            sql = """
            SELECT payload
            FROM alert_events
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT payload
            FROM alert_events
            WHERE timestamp >= ?
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        }

        let statement = try Self.prepare(sql, connection: connection)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if let since {
            guard sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }
        guard sqlite3_bind_int(statement, bindIndex, Int32(min(limit, 10_000))) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var events: [StoredAlertEvent] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw StoreError.invalidData
                }
                let data = Data(
                    bytes: text,
                    count: Int(sqlite3_column_bytes(statement, 0))
                )
                do {
                    events.append(try decoder.decode(StoredAlertEvent.self, from: data))
                } catch {
                    throw StoreError.invalidData
                }
            case SQLITE_DONE:
                return events
            default:
                throw Self.sqliteError(connection)
            }
        }
    }

    public func clearAlertEvents() throws {
        let connection = try requireConnection()
        let statement = try Self.prepare(
            "DELETE FROM alert_events;",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw Self.sqliteError(connection)
        }
    }

    public func clearIntelligenceAnalyses() throws {
        let connection = try requireConnection()
        let statement = try Self.prepare(
            "DELETE FROM intelligence_analysis_logs;",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw Self.sqliteError(connection)
        }
    }

    @discardableResult
    public func appendIntelligenceAnalysis(_ analysis: StoredIntelligenceAnalysis) throws -> Int64 {
        guard !analysis.prompt.isEmpty else {
            throw StoreError.invalidData
        }

        let connection = try requireConnection()
        let statement = try Self.prepare(
            "INSERT INTO intelligence_analysis_logs (run_id, timestamp, payload) VALUES (?, ?, ?);",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }

        let runID = analysis.id.uuidString
        let runIDResult = runID.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, Self.sqliteTransient)
        }
        guard runIDResult == SQLITE_OK,
              sqlite3_bind_double(statement, 2, analysis.requestedAt.timeIntervalSince1970) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }
        let payload = try Self.encode(analysis)
        let bindResult = payload.withCString {
            sqlite3_bind_text(statement, 3, $0, -1, Self.sqliteTransient)
        }
        guard bindResult == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw Self.sqliteError(connection)
        }
        return sqlite3_last_insert_rowid(connection)
    }

    public func updateIntelligenceAnalysis(_ analysis: StoredIntelligenceAnalysis) throws {
        guard !analysis.prompt.isEmpty else {
            throw StoreError.invalidData
        }

        let connection = try requireConnection()
        let statement = try Self.prepare(
            """
            INSERT INTO intelligence_analysis_logs (run_id, timestamp, payload)
            VALUES (?, ?, ?)
            ON CONFLICT(run_id) DO UPDATE SET
                timestamp = excluded.timestamp,
                payload = excluded.payload;
            """,
            connection: connection
        )
        defer { sqlite3_finalize(statement) }

        let runID = analysis.id.uuidString
        let runIDResult = runID.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, Self.sqliteTransient)
        }
        guard runIDResult == SQLITE_OK,
              sqlite3_bind_double(statement, 2, (analysis.completedAt ?? analysis.requestedAt).timeIntervalSince1970) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }
        let payload = try Self.encode(analysis)
        let payloadResult = payload.withCString {
            sqlite3_bind_text(statement, 3, $0, -1, Self.sqliteTransient)
        }
        guard payloadResult == SQLITE_OK,
              runIDResult == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw Self.sqliteError(connection)
        }
        guard sqlite3_changes(connection) == 1 else {
            throw StoreError.invalidData
        }
    }

    public func fetchIntelligenceAnalyses(
        since: Date? = nil,
        limit: Int = 100
    ) throws -> [StoredIntelligenceAnalysis] {
        guard limit > 0 else { return [] }

        let connection = try requireConnection()
        let sql: String
        if since == nil {
            sql = """
            SELECT payload
            FROM intelligence_analysis_logs
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT payload
            FROM intelligence_analysis_logs
            WHERE timestamp >= ?
            ORDER BY timestamp DESC, id DESC
            LIMIT ?;
            """
        }

        let statement = try Self.prepare(sql, connection: connection)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if let since {
            guard sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }
        guard sqlite3_bind_int(statement, bindIndex, Int32(min(limit, 10_000))) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var analyses: [StoredIntelligenceAnalysis] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw StoreError.invalidData
                }
                let data = Data(bytes: text, count: Int(sqlite3_column_bytes(statement, 0)))
                do {
                    analyses.append(try decoder.decode(StoredIntelligenceAnalysis.self, from: data))
                } catch {
                    throw StoreError.invalidData
                }
            case SQLITE_DONE:
                return analyses
            default:
                throw Self.sqliteError(connection)
            }
        }
    }

    public func intelligenceAnalysisCount() throws -> Int {
        try Self.scalarInt(
            "SELECT COUNT(*) FROM intelligence_analysis_logs;",
            connection: requireConnection()
        )
    }

    public func alertCount() throws -> Int {
        try Self.scalarInt(
            "SELECT COUNT(*) FROM alert_events;",
            connection: requireConnection()
        )
    }

    public func sampleCount() throws -> Int {
        try Self.scalarInt(
            "SELECT COUNT(*) FROM battery_samples_raw;",
            connection: requireConnection()
        )
    }

    public func sampleEvidence() throws -> SampleEvidence {
        let connection = try requireConnection()
        let statement = try Self.prepare(
            """
            SELECT
                COUNT(*),
                COUNT(DISTINCT strftime('%Y-%m-%d', timestamp, 'unixepoch', 'localtime')),
                MIN(timestamp),
                MAX(timestamp)
            FROM battery_samples_raw;
            """,
            connection: connection
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.sqliteError(connection)
        }

        let firstDate: Date?
        if sqlite3_column_type(statement, 2) == SQLITE_NULL {
            firstDate = nil
        } else {
            firstDate = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        }

        let lastDate: Date?
        if sqlite3_column_type(statement, 3) == SQLITE_NULL {
            lastDate = nil
        } else {
            lastDate = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        }

        return SampleEvidence(
            sampleCount: Int(sqlite3_column_int64(statement, 0)),
            observedDays: Int(sqlite3_column_int64(statement, 1)),
            firstSampleDate: firstDate,
            lastSampleDate: lastDate
        )
    }

    @discardableResult
    public func applyRetention(now: Date = Date()) throws -> Int {
        let connection = try requireConnection()
        var deleted = 0

        do {
            try Self.execute("BEGIN IMMEDIATE;", connection: connection)
            deleted += try Self.deleteSamples(
                before: now.addingTimeInterval(-Double(configuration.rawRetentionDays) * 86_400),
                table: "battery_samples_raw",
                connection: connection
            )
            deleted += try Self.deleteSamplesExceeding(
                limit: configuration.rawSampleLimit,
                table: "battery_samples_raw",
                connection: connection
            )
            deleted += try Self.deleteSamples(
                before: now.addingTimeInterval(-Double(configuration.rawRetentionDays) * 86_400),
                table: "process_samples",
                connection: connection
            )
            deleted += try Self.deleteSamplesExceeding(
                limit: configuration.rawSampleLimit,
                table: "process_samples",
                connection: connection
            )
            deleted += try Self.deleteSamples(
                before: now.addingTimeInterval(-Double(configuration.minuteRetentionDays) * 86_400),
                table: "battery_samples_minute",
                connection: connection
            )
            deleted += try Self.deleteSamples(
                before: now.addingTimeInterval(-Double(configuration.quarterHourRetentionDays) * 86_400),
                table: "battery_samples_quarter_hour",
                connection: connection
            )
            deleted += try Self.deleteSamples(
                before: now.addingTimeInterval(-Double(configuration.quarterHourRetentionDays) * 86_400),
                table: "cycle_usage_quarter_hour",
                connection: connection
            )
            if let dailyRetentionDays = configuration.dailyRetentionDays {
                deleted += try Self.deleteSamples(
                    before: now.addingTimeInterval(-Double(dailyRetentionDays) * 86_400),
                    table: "daily_summaries",
                    connection: connection
                )
                deleted += try Self.deleteSamples(
                    before: now.addingTimeInterval(-Double(dailyRetentionDays) * 86_400),
                    table: "cycle_usage_daily",
                    connection: connection
                )
            }
            deleted += try Self.deleteSamples(
                before: now.addingTimeInterval(-Double(configuration.alertRetentionDays) * 86_400),
                table: "alert_events",
                connection: connection
            )
            deleted += try Self.deleteSamples(
                before: now.addingTimeInterval(-Double(configuration.intelligenceAnalysisRetentionDays) * 86_400),
                table: "intelligence_analysis_logs",
                connection: connection
            )
            try Self.execute("COMMIT;", connection: connection)
        } catch {
            try? Self.execute("ROLLBACK;", connection: connection)
            throw error
        }

        return deleted
    }

    @discardableResult
    public func applyRetentionIfNeeded(
        now: Date = Date(),
        minimumInterval: TimeInterval = 3_600
    ) throws -> Int {
        if let lastRetentionRun,
           now.timeIntervalSince(lastRetentionRun) < max(60, minimumInterval) {
            return 0
        }
        let deleted = try applyRetention(now: now)
        lastRetentionRun = now
        return deleted
    }

    public func schemaVersion() throws -> Int {
        try Self.scalarInt(
            "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;",
            connection: requireConnection()
        )
    }

    public func diagnostics() throws -> StoreDiagnostics {
        let schemaVersion = try Self.scalarInt(
            "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;",
            connection: requireConnection()
        )
        guard let databaseSize = Self.fileSize(at: databaseURL) else {
            throw StoreError.unavailable
        }

        return StoreDiagnostics(
            schemaVersion: schemaVersion,
            databaseSizeBytes: databaseSize,
            walSizeBytes: Self.fileSize(
                at: URL(fileURLWithPath: databaseURL.path + "-wal")
            ) ?? 0
        )
    }

        private func requireConnection() throws -> OpaquePointer {
        guard let connection else { throw StoreError.unavailable }
        return connection.pointer
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private static func scalarInt(
_ sql: String, connection: OpaquePointer) throws -> Int {
        let statement = try Self.prepare(sql, connection: connection)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.sqliteError(connection)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func createParentDirectory(for databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private static func configure(_ connection: OpaquePointer) throws {
        try execute("PRAGMA journal_mode = WAL;", connection: connection)
        try execute("PRAGMA synchronous = NORMAL;", connection: connection)
        try execute("PRAGMA foreign_keys = ON;", connection: connection)
        try execute("PRAGMA busy_timeout = 250;", connection: connection)
    }

    private static func migrate(_ connection: OpaquePointer) throws {
        do {
            try execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version INTEGER PRIMARY KEY,
                    applied_at REAL NOT NULL
                );
                """,
                connection: connection
            )

            let currentVersion = try scalarInt(
                "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;",
                connection: connection
            )
            guard currentVersion <= 4 else {
                throw StoreError.unsupportedSchema(version: currentVersion)
            }

            if currentVersion >= 1 {
                if currentVersion < 2 {
                    try migrateAlertEvents(connection)
                }
                if currentVersion < 3 {
                    try migrateIntelligenceAnalyses(connection)
                }
                if currentVersion < 4 {
                    try migrateCycleUsage(connection)
                }
                return
            }

                try execute("BEGIN IMMEDIATE;", connection: connection)
                try execute(
                    """
                CREATE TABLE IF NOT EXISTS battery_samples_raw (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_battery_samples_raw_timestamp
                    ON battery_samples_raw(timestamp);

                CREATE TABLE IF NOT EXISTS battery_samples_minute (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_battery_samples_minute_timestamp
                    ON battery_samples_minute(timestamp);

                CREATE TABLE IF NOT EXISTS battery_samples_quarter_hour (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_battery_samples_quarter_hour_timestamp
                    ON battery_samples_quarter_hour(timestamp);

                 CREATE TABLE IF NOT EXISTS daily_summaries (
                     id INTEGER PRIMARY KEY AUTOINCREMENT,
                     timestamp REAL NOT NULL,
                     payload TEXT NOT NULL
                 );
                 CREATE INDEX IF NOT EXISTS idx_daily_summaries_timestamp
                     ON daily_summaries(timestamp);


                CREATE TABLE IF NOT EXISTS devices (
                    id TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS charge_sessions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    started_at REAL NOT NULL,
                    ended_at REAL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS discharge_sessions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    started_at REAL NOT NULL,
                    ended_at REAL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS power_source_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS thermal_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS process_samples (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS health_snapshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS recommendations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS automation_actions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS diagnostics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    payload TEXT NOT NULL
                );
                """,
                    connection: connection
                )
                try execute(
                    "INSERT INTO schema_migrations (version, applied_at) VALUES (1, ?);",
                    connection: connection,
                    bindDouble: Date().timeIntervalSince1970
                )
                try execute("COMMIT;", connection: connection)
            try migrateAlertEvents(connection)
            try migrateIntelligenceAnalyses(connection)
            try migrateCycleUsage(connection)
        } catch {
            try? execute("ROLLBACK;", connection: connection)
            guard let storeError = error as? StoreError else {
                throw StoreError.migrationFailed
            }
            switch storeError {
            case .unavailable, .locked, .diskFull, .corrupted, .unsupportedSchema:
                throw storeError
            default:
                throw StoreError.migrationFailed
            }
        }
    }

    private static func migrateAlertEvents(_ connection: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE;", connection: connection)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS alert_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                payload TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_alert_events_timestamp
                ON alert_events(timestamp);
            """,
            connection: connection
        )
        try execute(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (2, ?);",
            connection: connection,
            bindDouble: Date().timeIntervalSince1970
        )
        try execute("COMMIT;", connection: connection)
    }

    private static func migrateIntelligenceAnalyses(_ connection: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE;", connection: connection)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS intelligence_analysis_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL UNIQUE,
                timestamp REAL NOT NULL,
                payload TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_intelligence_analysis_logs_timestamp
                ON intelligence_analysis_logs(timestamp);
            """,
            connection: connection
        )
        try execute(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (3, ?);",
            connection: connection,
            bindDouble: Date().timeIntervalSince1970
        )
        try execute("COMMIT;", connection: connection)
    }

    private static func migrateCycleUsage(_ connection: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE;", connection: connection)
        do {
            try execute(
                """
                CREATE TABLE IF NOT EXISTS cycle_usage_quarter_hour (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL UNIQUE,
                    payload TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_cycle_usage_quarter_hour_timestamp
                    ON cycle_usage_quarter_hour(timestamp);

                CREATE TABLE IF NOT EXISTS cycle_usage_daily (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL UNIQUE,
                    payload TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_cycle_usage_daily_timestamp
                    ON cycle_usage_daily(timestamp);

                CREATE TABLE IF NOT EXISTS cycle_usage_state (
                    key TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                """,
                connection: connection
            )
            try backfillCycleUsageIfNeeded(connection: connection)
            try execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (4, ?);",
                connection: connection,
                bindDouble: Date().timeIntervalSince1970
            )
            try execute("COMMIT;", connection: connection)
        } catch {
            try? execute("ROLLBACK;", connection: connection)
            throw error
        }
    }

    private static func backfillCycleUsageIfNeeded(connection: OpaquePointer) throws {
        let existingBuckets = try scalarInt(
            "SELECT (SELECT COUNT(*) FROM cycle_usage_quarter_hour) + (SELECT COUNT(*) FROM cycle_usage_daily);",
            connection: connection
        )
        guard existingBuckets == 0,
              try tableExists("battery_samples_raw", connection: connection) else {
            return
        }

        let statement = try prepare(
            "SELECT payload FROM battery_samples_raw ORDER BY timestamp ASC, id ASC;",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var tracker = CycleUsageTracker()
        var updates: [String: StoredCycleUsageBucket] = [:]

        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw StoreError.invalidData
                }
                let data = Data(bytes: text, count: Int(sqlite3_column_bytes(statement, 0)))
                let sample: StoredBatterySample
                do {
                    sample = try decoder.decode(StoredBatterySample.self, from: data)
                } catch {
                    throw StoreError.invalidData
                }
                for bucket in tracker.ingest(sample) {
                    updates["\(bucket.resolution.rawValue):\(bucket.bucketStart.timeIntervalSince1970)"] = bucket
                }
            case SQLITE_DONE:
                for bucket in updates.values {
                    try upsertCycleUsage(bucket, connection: connection)
                }
                try saveCycleUsageTrackerState(tracker.state, connection: connection)
                return
            default:
                throw sqliteError(connection)
            }
        }
    }

    private static func tableExists(_ table: String, connection: OpaquePointer) throws -> Bool {
        let statement = try prepare(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?;",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }
        let bindResult = table.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
        }
        guard bindResult == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            throw sqliteError(connection)
        }
        return sqlite3_column_int64(statement, 0) > 0
    }

    private static func cycleUsageTable(for resolution: CycleUsageResolution) -> String {
        switch resolution {
        case .quarterHour: return "cycle_usage_quarter_hour"
        case .day: return "cycle_usage_daily"
        }
    }

    private static func upsertCycleUsage(
        _ bucket: StoredCycleUsageBucket,
        connection: OpaquePointer
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO \(cycleUsageTable(for: bucket.resolution)) (timestamp, payload)
            VALUES (?, ?)
            ON CONFLICT(timestamp) DO UPDATE SET payload = excluded.payload;
            """,
            connection: connection
        )
        defer { sqlite3_finalize(statement) }
        let payload = try encode(bucket)
        guard sqlite3_bind_double(statement, 1, bucket.bucketStart.timeIntervalSince1970) == SQLITE_OK else {
            throw sqliteError(connection)
        }
        let bindResult = payload.withCString {
            sqlite3_bind_text(statement, 2, $0, -1, sqliteTransient)
        }
        guard bindResult == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(connection)
        }
    }

    private static func saveCycleUsageTrackerState(
        _ state: StoredCycleUsageTrackerState,
        connection: OpaquePointer
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO cycle_usage_state (key, payload, updated_at)
            VALUES ('tracker', ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                payload = excluded.payload,
                updated_at = excluded.updated_at;
            """,
            connection: connection
        )
        defer { sqlite3_finalize(statement) }
        let payload = try encode(state)
        let bindResult = payload.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
        }
        guard bindResult == SQLITE_OK,
              sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(connection)
        }
    }

    private static func loadCycleUsageTrackerState(
        connection: OpaquePointer
    ) throws -> StoredCycleUsageTrackerState? {
        guard try tableExists("cycle_usage_state", connection: connection) else { return nil }
        let statement = try prepare(
            "SELECT payload FROM cycle_usage_state WHERE key = 'tracker' LIMIT 1;",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }
        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return nil
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0) else {
                throw StoreError.invalidData
            }
            let data = Data(bytes: text, count: Int(sqlite3_column_bytes(statement, 0)))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            do {
                return try decoder.decode(StoredCycleUsageTrackerState.self, from: data)
            } catch {
                throw StoreError.invalidData
            }
        default:
            throw sqliteError(connection)
        }
    }

    private static func sessionTable(for kind: BatterySessionKind) -> String {
        switch kind {
        case .charging:
            return "charge_sessions"
        case .discharging, .connectedDeficit, .sleepGap:
            return "discharge_sessions"
        }
    }

    private static func insertSessions(
        _ sessions: [BatterySession],
        connection: OpaquePointer
    ) throws {
        for session in sessions {
            guard let endedAt = session.endedAt else {
                throw StoreError.invalidData
            }
            let table = Self.sessionTable(for: session.kind)
            let statement = try Self.prepare(
                "INSERT INTO \(table) (started_at, ended_at, payload) VALUES (?, ?, ?);",
                connection: connection
            )
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_double(statement, 1, session.startedAt.timeIntervalSince1970) == SQLITE_OK,
                  sqlite3_bind_double(statement, 2, endedAt.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            let payload = try Self.encode(session)
            let bindResult = payload.withCString {
                sqlite3_bind_text(statement, 3, $0, -1, Self.sqliteTransient)
            }
            guard bindResult == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_DONE else {
                throw Self.sqliteError(connection)
            }
        }
    }

    private static func fetchSessions(
        from table: String,
        since: Date?,
        limit: Int,
        connection: OpaquePointer
    ) throws -> [BatterySession] {
        let sql: String
        if since == nil {
            sql = """
            SELECT payload
            FROM \(table)
            ORDER BY started_at DESC, id DESC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT payload
            FROM \(table)
            WHERE started_at >= ?
            ORDER BY started_at DESC, id DESC
            LIMIT ?;
            """
        }
        let statement = try Self.prepare(sql, connection: connection)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if let since {
            guard sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            bindIndex += 1
        }
        guard sqlite3_bind_int(statement, bindIndex, Int32(limit)) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var sessions: [BatterySession] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw StoreError.invalidData
                }
                let data = Data(
                    bytes: text,
                    count: Int(sqlite3_column_bytes(statement, 0))
                )
                do {
                    let session = try decoder.decode(BatterySession.self, from: data)
                    guard session.endedAt != nil else {
                        throw StoreError.invalidData
                    }
                    sessions.append(session)
                } catch let error as StoreError {
                    throw error
                } catch {
                    throw StoreError.invalidData
                }
            case SQLITE_DONE:
                return sessions
            default:
                throw Self.sqliteError(connection)
            }
        }
    }

    private static func aggregateTable(for resolution: BatteryAggregateResolution) -> String {
        switch resolution {
        case .minute:
            return "battery_samples_minute"
        case .quarterHour:
            return "battery_samples_quarter_hour"
        case .day:
            return "daily_summaries"
        }
    }

    private static func aggregateBatches(
        _ samples: [StoredBatterySample]
    ) throws -> [BatteryAggregate] {
        var aggregates: [String: BatteryAggregate] = [:]
        for sample in samples {
            for resolution in BatteryAggregateResolution.allCases {
                let aggregate = Self.aggregate(for: sample, resolution: resolution)
                let key = "\(resolution.rawValue):\(aggregate.bucketStart.timeIntervalSince1970)"
                if let existing = aggregates[key] {
                    aggregates[key] = Self.merge(existing, with: aggregate)
                } else {
                    aggregates[key] = aggregate
                }
            }
        }

        return aggregates.values.sorted {
            if $0.bucketStart != $1.bucketStart {
                return $0.bucketStart < $1.bucketStart
            }
            return $0.resolution.rawValue < $1.resolution.rawValue
        }
    }

    private static func aggregate(
        for sample: StoredBatterySample,
        resolution: BatteryAggregateResolution
    ) -> BatteryAggregate {
        let charge = sample.battery.chargePercent
        let temperature = sample.battery.temperatureCelsius.flatMap { $0.isFinite ? $0 : nil }
        let rawPower = BatteryMath.batteryPowerWatts(
            voltageMillivolts: sample.battery.voltageMillivolts,
            signedAmperageMilliamps: sample.battery.amperageMilliamps
        )
        let power = rawPower.flatMap { abs($0) >= 0.05 ? $0 : nil }
        let system = sample.system
        let diskRead = system?.diskReadBytesPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let diskWrite = system?.diskWriteBytesPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return BatteryAggregate(
            resolution: resolution,
            bucketStart: Self.bucketStart(for: sample.battery.timestamp, resolution: resolution),
            sampleCount: 1,
            chargeSampleCount: charge == nil ? 0 : 1,
            minimumChargePercent: charge,
            maximumChargePercent: charge,
            averageChargePercent: charge.map(Double.init),
            temperatureSampleCount: temperature == nil ? 0 : 1,
            averageTemperatureCelsius: temperature,
            minimumTemperatureCelsius: temperature,
            maximumTemperatureCelsius: temperature,
            chargingSampleCount: sample.battery.isCharging ? 1 : 0,
            externalPowerSampleCount: sample.battery.externalPowerConnected ? 1 : 0,
            powerSampleCount: power == nil ? 0 : 1,
            averageBatteryPowerWatts: power,
            cpuSampleCount: system?.cpuUsagePercent == nil ? 0 : 1,
            averageCPUUsagePercent: system?.cpuUsagePercent,
            memorySampleCount: system?.memoryUsedPercent == nil ? 0 : 1,
            averageMemoryUsedPercent: system?.memoryUsedPercent,
            diskSampleCount: system?.diskUsedPercent == nil ? 0 : 1,
            averageDiskUsedPercent: system?.diskUsedPercent,
            diskReadSampleCount: diskRead == nil ? 0 : 1,
            averageDiskReadBytesPerSecond: diskRead,
            diskWriteSampleCount: diskWrite == nil ? 0 : 1,
            averageDiskWriteBytesPerSecond: diskWrite
        )
    }

    private static func bucketStart(
        for date: Date,
        resolution: BatteryAggregateResolution
    ) -> Date {
        let interval: TimeInterval
        switch resolution {
        case .minute:
            interval = 60
        case .quarterHour:
            interval = 15 * 60
        case .day:
            interval = 24 * 60 * 60
        }
        return Date(
            timeIntervalSince1970: floor(date.timeIntervalSince1970 / interval) * interval
        )
    }

    private static func merge(
        _ existing: BatteryAggregate,
        with incoming: BatteryAggregate
    ) -> BatteryAggregate {
        let chargeSampleCount = existing.chargeSampleCount + incoming.chargeSampleCount
        let temperatureSampleCount = existing.temperatureSampleCount + incoming.temperatureSampleCount
        let powerSampleCount = existing.powerSampleCount + incoming.powerSampleCount
        let cpuSampleCount = existing.cpuSampleCount + incoming.cpuSampleCount
        let memorySampleCount = existing.memorySampleCount + incoming.memorySampleCount
        let diskSampleCount = existing.diskSampleCount + incoming.diskSampleCount
        let diskReadSampleCount = existing.diskReadSampleCount + incoming.diskReadSampleCount
        let diskWriteSampleCount = existing.diskWriteSampleCount + incoming.diskWriteSampleCount
        return BatteryAggregate(
            resolution: existing.resolution,
            bucketStart: existing.bucketStart,
            sampleCount: existing.sampleCount + incoming.sampleCount,
            chargeSampleCount: chargeSampleCount,
            minimumChargePercent: Self.minimum(existing.minimumChargePercent, incoming.minimumChargePercent),
            maximumChargePercent: Self.maximum(existing.maximumChargePercent, incoming.maximumChargePercent),
            averageChargePercent: Self.weightedAverage(
                existing.averageChargePercent,
                count: existing.chargeSampleCount,
                incoming.averageChargePercent,
                count: incoming.chargeSampleCount
            ),
            temperatureSampleCount: temperatureSampleCount,
            averageTemperatureCelsius: Self.weightedAverage(
                existing.averageTemperatureCelsius,
                count: existing.temperatureSampleCount,
                incoming.averageTemperatureCelsius,
                count: incoming.temperatureSampleCount
            ),
            minimumTemperatureCelsius: Self.minimum(
                existing.minimumTemperatureCelsius,
                incoming.minimumTemperatureCelsius
            ),
            maximumTemperatureCelsius: Self.maximum(
                existing.maximumTemperatureCelsius,
                incoming.maximumTemperatureCelsius
            ),
            chargingSampleCount: existing.chargingSampleCount + incoming.chargingSampleCount,
            externalPowerSampleCount: existing.externalPowerSampleCount + incoming.externalPowerSampleCount,
            powerSampleCount: powerSampleCount,
            averageBatteryPowerWatts: Self.weightedAverage(
                existing.averageBatteryPowerWatts,
                count: existing.powerSampleCount,
                incoming.averageBatteryPowerWatts,
                count: incoming.powerSampleCount
            ),
            cpuSampleCount: cpuSampleCount,
            averageCPUUsagePercent: Self.weightedAverage(
                existing.averageCPUUsagePercent,
                count: existing.cpuSampleCount,
                incoming.averageCPUUsagePercent,
                count: incoming.cpuSampleCount
            ),
            memorySampleCount: memorySampleCount,
            averageMemoryUsedPercent: Self.weightedAverage(
                existing.averageMemoryUsedPercent,
                count: existing.memorySampleCount,
                incoming.averageMemoryUsedPercent,
                count: incoming.memorySampleCount
            ),
            diskSampleCount: diskSampleCount,
            averageDiskUsedPercent: Self.weightedAverage(
                existing.averageDiskUsedPercent,
                count: existing.diskSampleCount,
                incoming.averageDiskUsedPercent,
                count: incoming.diskSampleCount
            ),
            diskReadSampleCount: diskReadSampleCount,
            averageDiskReadBytesPerSecond: Self.weightedAverage(
                existing.averageDiskReadBytesPerSecond,
                count: existing.diskReadSampleCount,
                incoming.averageDiskReadBytesPerSecond,
                count: incoming.diskReadSampleCount
            ),
            diskWriteSampleCount: diskWriteSampleCount,
            averageDiskWriteBytesPerSecond: Self.weightedAverage(
                existing.averageDiskWriteBytesPerSecond,
                count: existing.diskWriteSampleCount,
                incoming.averageDiskWriteBytesPerSecond,
                count: incoming.diskWriteSampleCount
            )
        )
    }

    private static func weightedAverage(
        _ first: Double?,
        count firstCount: Int,
        _ second: Double?,
        count secondCount: Int
    ) -> Double? {
        let totalCount = firstCount + secondCount
        guard totalCount > 0 else { return nil }
        return ((first ?? 0) * Double(firstCount) + (second ?? 0) * Double(secondCount))
            / Double(totalCount)
    }

    private static func minimum<T: Comparable>(_ first: T?, _ second: T?) -> T? {
        switch (first, second) {
        case let (first?, second?):
            return min(first, second)
        case let (first?, nil):
            return first
        case let (nil, second?):
            return second
        case (nil, nil):
            return nil
        }
    }

    private static func maximum<T: Comparable>(_ first: T?, _ second: T?) -> T? {
        switch (first, second) {
        case let (first?, second?):
            return max(first, second)
        case let (first?, nil):
            return first
        case let (nil, second?):
            return second
        case (nil, nil):
            return nil
        }
    }

    private static func upsert(
        _ incoming: BatteryAggregate,
        connection: OpaquePointer
    ) throws {
        let table = Self.aggregateTable(for: incoming.resolution)
        let existing = try existingAggregate(
            timestamp: incoming.bucketStart,
            resolution: incoming.resolution,
            connection: connection
        )
        let aggregate = existing.map { Self.merge($0, with: incoming) } ?? incoming
        let payload = try Self.encode(aggregate)

        if existing != nil {
            let statement = try Self.prepare(
                "UPDATE \(table) SET payload = ? WHERE timestamp = ?;",
                connection: connection
            )
            defer { sqlite3_finalize(statement) }
            let bindResult = payload.withCString {
                sqlite3_bind_text(statement, 1, $0, -1, Self.sqliteTransient)
            }
            guard bindResult == SQLITE_OK,
                  sqlite3_bind_double(statement, 2, aggregate.bucketStart.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw Self.sqliteError(connection)
            }
        } else {
            let statement = try Self.prepare(
                "INSERT INTO \(table) (timestamp, payload) VALUES (?, ?);",
                connection: connection
            )
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_double(statement, 1, aggregate.bucketStart.timeIntervalSince1970) == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            let bindResult = payload.withCString {
                sqlite3_bind_text(statement, 2, $0, -1, Self.sqliteTransient)
            }
            guard bindResult == SQLITE_OK else {
                throw Self.sqliteError(connection)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw Self.sqliteError(connection)
            }
        }
    }

    private static func existingAggregate(
        timestamp: Date,
        resolution: BatteryAggregateResolution,
        connection: OpaquePointer
    ) throws -> BatteryAggregate? {
        let table = Self.aggregateTable(for: resolution)
        let statement = try Self.prepare(
            "SELECT payload FROM \(table) WHERE timestamp = ? LIMIT 1;",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_double(statement, 1, timestamp.timeIntervalSince1970) == SQLITE_OK else {
            throw Self.sqliteError(connection)
        }

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0) else {
                throw StoreError.invalidData
            }
            let data = Data(
                bytes: text,
                count: Int(sqlite3_column_bytes(statement, 0))
            )
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                let aggregate = try decoder.decode(BatteryAggregate.self, from: data)
                guard aggregate.resolution == resolution else {
                    throw StoreError.invalidData
                }
                return aggregate
            } catch let error as StoreError {
                throw error
            } catch {
                throw StoreError.invalidData
            }
        case SQLITE_DONE:
            return nil
        default:
            throw Self.sqliteError(connection)
        }
    }

    private static func deleteSamplesExceeding(
        limit: Int,
        table: String,
        connection: OpaquePointer
    ) throws -> Int {
        let statement = try prepare(
            """
            DELETE FROM \(table)
            WHERE id IN (
                SELECT id FROM \(table)
                ORDER BY timestamp DESC, id DESC
                LIMIT -1 OFFSET ?
            );
            """,
            connection: connection
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int64(statement, 1, sqlite3_int64(max(1, limit))) == SQLITE_OK else {
            throw sqliteError(connection)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(connection)
        }
        return Int(sqlite3_changes(connection))
    }

    private static func deleteSamples(
        before date: Date,
        table: String,
        connection: OpaquePointer
    ) throws -> Int {
        let statement = try prepare(
            "DELETE FROM \(table) WHERE timestamp < ?;",
            connection: connection
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_double(statement, 1, date.timeIntervalSince1970) == SQLITE_OK else {
            throw sqliteError(connection)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(connection)
        }
        return Int(sqlite3_changes(connection))
    }

    private static func execute(
        _ sql: String,
        connection: OpaquePointer,
        bindDouble: Double? = nil
    ) throws {
        if let bindDouble {
            let statement = try prepare(sql, connection: connection)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_double(statement, 1, bindDouble) == SQLITE_OK else {
                throw sqliteError(connection)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw sqliteError(connection)
            }
            return
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorMessage)
        defer {
            if let errorMessage { sqlite3_free(errorMessage) }
        }
        guard result == SQLITE_OK else {
            throw sqliteError(connection)
        }
    }

    private static func prepare(
        _ sql: String,
        connection: OpaquePointer
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw sqliteError(connection)
        }
        return statement
    }

    private static func sqliteError(_ connection: OpaquePointer) -> StoreError {
        classifySQLiteError(
            code: sqlite3_extended_errcode(connection),
            message: String(cString: sqlite3_errmsg(connection))
        )
    }

    static func classifySQLiteError(code: Int32, message: String) -> StoreError {
        switch code & 0xFF {
        case SQLITE_BUSY, SQLITE_LOCKED:
            return .locked
        case SQLITE_FULL:
            return .diskFull
        case SQLITE_CORRUPT, SQLITE_NOTADB:
            return .corrupted
        case SQLITE_CANTOPEN, SQLITE_PERM, SQLITE_READONLY:
            return .unavailable
        default:
            return .sqlite(message: message)
        }
    }

    private static func encode(_ sample: StoredBatterySample) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(sample)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidData
            }
            return encoded
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.invalidData
        }
    }

    private static func encode(_ sample: StoredProcessSample) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(sample)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidData
            }
            return encoded
        } catch {
            throw StoreError.invalidData
        }
    }

    private static func isValidProcessSample(_ sample: StoredProcessSample) -> Bool {
        !sample.name.isEmpty
            && sample.cpuPercent.isFinite
            && (sample.memoryPercent?.isFinite ?? true)
            && (sample.estimatedBatteryPercentPerMinute?.isFinite ?? true)
    }

    private static func encode(_ aggregate: BatteryAggregate) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(aggregate)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidData
            }
            return encoded
        } catch {
            throw StoreError.invalidData
        }
    }

    private static func encode(_ bucket: StoredCycleUsageBucket) throws -> String {
        try encodeCycleUsageValue(bucket)
    }

    private static func encode(_ state: StoredCycleUsageTrackerState) throws -> String {
        try encodeCycleUsageValue(state)
    }

    private static func encodeCycleUsageValue<T: Encodable>(_ value: T) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(value)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidData
            }
            return encoded
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.invalidData
        }
    }

    private static func encode(_ session: BatterySession) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(session)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidData
            }
            return encoded
        } catch {
            throw StoreError.invalidData
        }
    }

    private static func encode(_ event: StoredAlertEvent) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(event)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidData
            }
            return encoded
        } catch {
            throw StoreError.invalidData
        }
    }

    private static func encode(_ analysis: StoredIntelligenceAnalysis) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(analysis)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidData
            }
            return encoded
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.invalidData
        }
    }

    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

}

private final class SQLiteHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close_v2(pointer)
    }
}

extension SQLiteStore: SamplingBatchSink, SessionSink {
    public func writeBatch(_ samples: [BatterySample]) async throws {
        _ = try appendBatch(samples)
    }

    public func writeBatch(
        _ samples: [BatterySample],
        sessions: [BatterySession]
    ) async throws {
        _ = try appendBatchReturningIDs(samples, sessions: sessions)
    }

    public func writeSessions(_ sessions: [BatterySession]) async throws {
        _ = try appendSessions(sessions)
    }
}
