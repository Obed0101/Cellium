import Foundation

public struct BatterySample: Codable, Equatable, Sendable {
    public let battery: BatterySnapshot
    public let system: SystemSnapshot?

    public init(battery: BatterySnapshot, system: SystemSnapshot? = nil) {
        self.battery = battery
        self.system = system
    }
}

public enum SamplingMode: String, Codable, CaseIterable, Sendable {
    case idle
    case backgroundOnAC
    case backgroundOnBattery
    case quickPanelVisible
    case dashboardVisible
    case transition
    case diagnostics

    public var interval: TimeInterval? {
        switch self {
        case .idle:
            return nil
        case .backgroundOnAC:
            return 60
        case .backgroundOnBattery:
            return 30
        case .quickPanelVisible:
            // The panel refreshes live at 5s, but persistence stays sparse so
            // opening the popover does not turn into a disk writer.
            return 15
        case .dashboardVisible:
            return 2
        case .transition:
            return 2
        case .diagnostics:
            return 1
        }
    }
}

public struct SnapshotSource: Sendable {
    public let readBattery: @Sendable (Date) -> BatterySnapshot
    public let readSystem: @Sendable (Date) -> SystemSnapshot

    public init(
        readBattery: @escaping @Sendable (Date) -> BatterySnapshot,
        readSystem: @escaping @Sendable (Date) -> SystemSnapshot
    ) {
        self.readBattery = readBattery
        self.readSystem = readSystem
    }
}

public protocol SampleSink: Sendable {
    func writeBatch(_ samples: [BatterySample]) async throws
}

public protocol SessionSink: Sendable {
    func writeSessions(_ sessions: [BatterySession]) async throws
}

public protocol SamplingBatchSink: SampleSink {
    func writeBatch(
        _ samples: [BatterySample],
        sessions: [BatterySession]
    ) async throws
}

public enum SamplingError: Error, Equatable, Sendable {
    case sessionSinkUnavailable
}

public actor SamplingCoordinator {
    public let source: SnapshotSource
    public let ringBufferCapacity: Int
    public let flushBatchSize: Int

    private let sink: (any SampleSink)?
    private var mode: SamplingMode = .idle
    private var buffer: [BatterySample] = []
    private var pendingSamples: [BatterySample] = []
    private var pendingSessions: [BatterySession] = []
    private var sessionTracker = BatterySessionTracker()
    private var samplingTask: Task<Void, Never>?
    private var intervalOverride: TimeInterval?

    public init(
        source: SnapshotSource,
        ringBufferCapacity: Int = 120,
        sink: (any SampleSink)? = nil,
        flushBatchSize: Int = 10
    ) {
        self.source = source
        self.ringBufferCapacity = max(1, ringBufferCapacity)
        self.sink = sink
        self.flushBatchSize = max(1, flushBatchSize)
        self.intervalOverride = nil
    }

    public func setMode(_ mode: SamplingMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        samplingTask?.cancel()
        samplingTask = nil
        if mode.interval != nil {
            start()
        }
    }

    public func currentMode() -> SamplingMode {
        mode
    }

    public func setIntervalOverride(_ interval: TimeInterval?) {
        if let interval, interval.isFinite, interval > 0 {
            intervalOverride = interval
        } else {
            intervalOverride = nil
        }

        samplingTask?.cancel()
        samplingTask = nil
        if mode.interval != nil {
            start()
        }
    }

    public func currentInterval() -> TimeInterval? {
        samplingInterval(for: mode)
    }

    @discardableResult
    public func sampleNow(at date: Date = Date()) -> BatterySample {
        let sample = BatterySample(
            battery: source.readBattery(date),
            system: source.readSystem(date)
        )
        buffer.append(sample)
        if buffer.count > ringBufferCapacity {
            buffer.removeFirst(buffer.count - ringBufferCapacity)
        }
        let completedSessions = sessionTracker.ingest(sample).compactMap { event in
            if case let .completed(session) = event {
                return session
            }
            return nil
        }
        if sink != nil {
            pendingSamples.append(sample)
            pendingSessions.append(contentsOf: completedSessions)
        }
        return sample
    }

    public func bufferedSamples() -> [BatterySample] {
        buffer
    }

    public func pendingSampleCount() -> Int {
        pendingSamples.count
    }

    public func pendingSessionCount() -> Int {
        pendingSessions.count
    }

    public func flush() async throws {
        guard let sink, !pendingSamples.isEmpty || !pendingSessions.isEmpty else { return }

        let batch = pendingSamples
        let sessions = pendingSessions
        pendingSamples.removeAll(keepingCapacity: true)
        pendingSessions.removeAll(keepingCapacity: true)
        var samplesWritten = false
        do {
            if let batchSink = sink as? any SamplingBatchSink {
                try await batchSink.writeBatch(batch, sessions: sessions)
                samplesWritten = true
            } else {
                try await sink.writeBatch(batch)
                samplesWritten = true
                if !sessions.isEmpty {
                    guard let sessionSink = sink as? any SessionSink else {
                        throw SamplingError.sessionSinkUnavailable
                    }
                    try await sessionSink.writeSessions(sessions)
                }
            }
        } catch {
            if samplesWritten {
                pendingSessions.insert(contentsOf: sessions, at: 0)
            } else {
                pendingSamples.insert(contentsOf: batch, at: 0)
                pendingSessions.insert(contentsOf: sessions, at: 0)
            }
            throw error
        }
    }

    public func stopAndFlush(at date: Date = Date()) async throws {
        stop()
        let completedSessions = sessionTracker.finish(at: date).compactMap { event in
            if case let .completed(session) = event {
                return session
            }
            return nil
        }
        if sink != nil {
            pendingSessions.append(contentsOf: completedSessions)
        }
        try await flush()
    }

    public func start() {
        guard mode.interval != nil, samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            await self?.runSamplingLoop()
        }
    }

    public func stop() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    private func runSamplingLoop() async {
        while !Task.isCancelled {
            guard let interval = samplingInterval(for: mode) else {
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }
                continue
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            _ = sampleNow()
            if pendingSamples.count >= flushBatchSize || !pendingSessions.isEmpty {
                try? await flush()
            }
        }
    }

    private func samplingInterval(for mode: SamplingMode) -> TimeInterval? {
        guard let defaultInterval = mode.interval else { return nil }
        return intervalOverride ?? defaultInterval
    }
}
