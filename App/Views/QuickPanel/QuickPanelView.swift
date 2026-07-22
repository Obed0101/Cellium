import SwiftUI
import AppKit
import Charts
import Darwin
import CelliumCore
import CelliumDarwin
import CelliumStore

struct ProactiveAlert: Equatable {
    let identifier: String
    let title: String
    let body: String
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case twoHours = "2h"
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case year = "1y"
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twoHours:
            return "2 hours"
        case .day:
            return "24 hours"
        case .week:
            return "7 days"
        case .month:
            return "30 days"
        case .quarter:
            return "90 days"
        case .year:
            return "1 year"
        case .all:
            return "All data"
        }
    }

    var resolution: BatteryAggregateResolution {
        switch self {
        case .twoHours, .day:
            return .minute
        case .week, .month:
            return .quarterHour
        case .quarter, .year, .all:
            return .day
        }
    }

    var since: Date? {
        switch self {
        case .twoHours:
            return Date().addingTimeInterval(-2 * 3_600)
        case .day:
            return Date().addingTimeInterval(-24 * 3_600)
        case .week:
            return Date().addingTimeInterval(-7 * 86_400)
        case .month:
            return Date().addingTimeInterval(-30 * 86_400)
        case .quarter:
            return Date().addingTimeInterval(-90 * 86_400)
        case .year:
            return Date().addingTimeInterval(-365 * 86_400)
        case .all:
            return nil
        }
    }
}

@MainActor
final class BatteryViewModel: ObservableObject {
    @Published private(set) var battery: BatterySnapshot
    @Published private(set) var system: SystemSnapshot
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var recentSamples: [StoredBatterySample] = []
    @Published private(set) var recentSessions: [BatterySession] = []
    @Published private(set) var historyAggregates: [BatteryAggregate] = []
    @Published private(set) var learningAggregates: [BatteryAggregate] = []
    @Published private(set) var historyRange: HistoryRange = .twoHours
    @Published private(set) var processImpacts: [ProcessEnergyImpact] = []
    @Published private(set) var storeDiagnostics: StoreDiagnostics?
    @Published private(set) var storeError: String?
    @Published private(set) var samplingMode: SamplingMode = .idle
    @Published private(set) var pendingSampleCount = 0
    @Published private(set) var pendingSessionCount = 0
    @Published private(set) var storedSampleCount = 0
    @Published private(set) var learningDaysObserved = 0
    @Published private(set) var learningFirstDate: Date?
    @Published private(set) var learningLastDate: Date?
    @Published private(set) var showingSettings = false
    @Published private(set) var language: CelliumLanguage
    @Published private(set) var samplingPreference: SamplingPreference
    @Published private(set) var customSamplingIntervalSeconds: Int
    @Published private(set) var learningEnabled: Bool
    @Published private(set) var temperatureAlertCelsius: Double
    @Published private(set) var criticalChargePercent: Int
    @Published private(set) var historyMetric: DashboardHistoryMetric = .power
    @Published private(set) var weatherSnapshot: WeatherSnapshot?
    @Published private(set) var weatherError: String?
    @Published private(set) var weatherLocationMode: WeatherLocationMode
    @Published private(set) var manualWeatherLabel: String
    @Published private(set) var manualWeatherLatitude: String
    @Published private(set) var manualWeatherLongitude: String
    @Published private(set) var proactiveAlert: ProactiveAlert?
    @Published private(set) var isRefreshingHistory = false
    @Published private(set) var updateCheckEnabled: Bool
    @Published private(set) var updateState: GitHubUpdateState = .idle
    @Published private(set) var lastUpdateCheck: Date?

    var onProactiveAlert: ((ProactiveAlert) -> Void)?

    private let defaults: UserDefaults
    private let batteryReader: IOKitBatteryReader
    private let systemReader: SystemStateReader
    private let coordinator: SamplingCoordinator
    private let store: SQLiteStore?
    private let weatherCoordinator: WeatherCoordinator
    private let processMonitor = ProcessEnergyMonitor()
    private let updateChecker = GitHubUpdateChecker()
    private var updateTask: Task<Void, Never>?
    private var panelVisible = false
    private var liveRefreshTask: Task<Void, Never>?
    private var panelVisibilityTask: Task<Void, Never>?
    private var backgroundHealthTask: Task<Void, Never>?
    private var lastProcessImpactRefresh: Date?
    private var lastPersistedDataRefresh: Date?
    private var lastHistoryRefresh: Date?
    private var lastProactiveAlertKey: String?
    private var lastProactiveAlertDate: Date?

    init(
        batteryReader: IOKitBatteryReader = IOKitBatteryReader(),
        systemReader: SystemStateReader = SystemStateReader()
    ) {
        self.defaults = .standard
        self.batteryReader = batteryReader
        self.systemReader = systemReader
        self.language = CelliumLanguage(rawValue: defaults.string(forKey: "cellium.language") ?? "") ?? .english
        self.samplingPreference = SamplingPreference(
            rawValue: defaults.string(forKey: "cellium.samplingPreference") ?? ""
        ) ?? .systemDefault
        let storedSamplingInterval = defaults.object(forKey: "cellium.customSamplingIntervalSeconds") as? Int ?? 15
        self.customSamplingIntervalSeconds = min(3_600, max(1, storedSamplingInterval))
        self.learningEnabled = defaults.object(forKey: "cellium.learningEnabled") as? Bool ?? true
        self.temperatureAlertCelsius = defaults.object(forKey: "cellium.temperatureAlertCelsius") as? Double ?? 40
        self.criticalChargePercent = defaults.object(forKey: "cellium.criticalChargePercent") as? Int ?? 20
        self.updateCheckEnabled = defaults.object(forKey: "cellium.updateCheckEnabled") as? Bool ?? false
        self.lastUpdateCheck = defaults.object(forKey: "cellium.lastUpdateCheck") as? Date
        self.weatherCoordinator = WeatherCoordinator()
        self.weatherLocationMode = weatherCoordinator.mode
        self.manualWeatherLabel = weatherCoordinator.manualLabel
        self.manualWeatherLatitude = weatherCoordinator.manualLatitude
        self.manualWeatherLongitude = weatherCoordinator.manualLongitude
        self.weatherSnapshot = weatherCoordinator.snapshot
        self.weatherError = weatherCoordinator.errorMessage
        let date = Date()
        self.battery = batteryReader.readSnapshot(at: date)
        self.system = systemReader.readSnapshot(at: date)
        self.lastUpdated = date

        let source = SnapshotSource(
            readBattery: { date in batteryReader.readSnapshot(at: date) },
            readSystem: { date in systemReader.readSnapshot(at: date) }
        )
        let configuredStore: SQLiteStore?
        if let databaseURL = try? SQLiteStore.defaultDatabaseURL() {
            configuredStore = try? SQLiteStore(databaseURL: databaseURL)
        } else {
            configuredStore = nil
        }
        self.store = configuredStore
        self.coordinator = SamplingCoordinator(
            source: source,
            sink: configuredStore,
            flushBatchSize: 10
        )
        weatherCoordinator.onChange = { [weak self] in
            self?.syncWeatherState()
        }
    }

    var healthPercent: Double? {
        BatteryMath.healthPercent(
            nominalChargeCapacityMAh: battery.nominalChargeCapacityMAh,
            designCapacityMAh: battery.designCapacityMAh
        )
    }

    var batteryPowerWatts: Double? {
        guard let watts = BatteryMath.batteryPowerWatts(
            voltageMillivolts: battery.voltageMillivolts,
            signedAmperageMilliamps: battery.amperageMilliamps
        ), abs(watts) >= 0.05 else {
            return nil
        }
        return watts
    }

    var batteryPowerLabel: String {
        guard let watts = batteryPowerWatts else { return copy(.noReading) }
        return String(format: "%.1f W", watts)
    }

    var batteryPercentPerMinute: Double? {
        guard !battery.isCharging,
              let watts = batteryPowerWatts,
              watts > 0,
              let capacity = battery.nominalChargeCapacityMAh ?? battery.currentCapacityMAh,
              let voltageMillivolts = battery.voltageMillivolts,
              capacity > 0,
              voltageMillivolts > 0 else {
            return nil
        }
        let batteryEnergyWattHours = Double(capacity) * Double(voltageMillivolts) / 1_000_000
        guard batteryEnergyWattHours > 0 else { return nil }
        let rate = watts / batteryEnergyWattHours * 100 / 60
        guard rate.isFinite else { return nil }
        return rate
    }

    private var orderedRecentSamples: [(date: Date, charge: Int)] {
        recentSamples
            .compactMap { sample -> (Date, Int)? in
                guard let charge = sample.battery.chargePercent else { return nil }
                return (sample.battery.timestamp, charge)
            }
            .sorted { $0.0 < $1.0 }
            .map { (date: $0.0, charge: $0.1) }
    }

    private var configuredSamplingInterval: TimeInterval? {
        switch samplingPreference {
        case .custom:
            return TimeInterval(customSamplingIntervalSeconds)
        default:
            return samplingPreference.intervalOverride
        }
    }

    private var expectedSampleInterval: TimeInterval {
        if panelVisible { return configuredSamplingInterval ?? 15 }
        return configuredSamplingInterval ?? (battery.externalPowerConnected ? 60 : 30)
    }

    var activeSamplingIntervalSeconds: Int {
        Int(max(1, expectedSampleInterval).rounded())
    }

    var samplingGapMinutes: Int? {
        let ordered = orderedRecentSamples
        guard let newest = ordered.last else { return nil }
        let allowedGap = expectedSampleInterval * 2 + 30
        var largestGap = max(0, Date().timeIntervalSince(newest.date))
        for pair in zip(ordered, ordered.dropFirst()) {
            largestGap = max(largestGap, pair.1.date.timeIntervalSince(pair.0.date))
        }
        guard largestGap > allowedGap else { return nil }
        return max(1, Int(ceil(largestGap / 60)))
    }

    var observedBatteryPercentPerMinute: Double? {
        let ordered = orderedRecentSamples
        guard samplingGapMinutes == nil,
              let first = ordered.first,
              let last = ordered.last,
              ordered.count >= 2 else {
            return nil
        }
        let elapsedMinutes = last.date.timeIntervalSince(first.date) / 60
        let drop = first.charge - last.charge
        guard elapsedMinutes >= 0.5, drop > 0 else { return nil }
        let rate = Double(drop) / elapsedMinutes
        return rate.isFinite ? rate : nil
    }

    var effectiveBatteryPercentPerMinute: Double? {
        observedBatteryPercentPerMinute ?? batteryPercentPerMinute
    }

    var copy: CelliumCopy {
        CelliumCopy(language: language)
    }

    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
    }

    var updateReleaseURL: URL? {
        guard case let .available(_, _, url) = updateState else { return nil }
        return url
    }

    var isCheckingForUpdates: Bool {
        if case .checking = updateState { return true }
        return false
    }

    var updateStatusTitle: String {
        switch updateState {
        case .idle:
            return copy(.checkForUpdates)
        case .checking:
            return copy(.checkingForUpdates)
        case let .current(version):
            return String(format: copy(.updateCurrent), version)
        case let .available(version, _, _):
            return String(format: copy(.updateAvailable), version)
        case .failed:
            return copy(.updateCheckFailed)
        }
    }

    var updateStatusDetail: String {
        switch updateState {
        case .idle:
            return copy(.updateCheckDetail)
        case .checking:
            return copy(.checkingForUpdatesDetail)
        case let .current(version):
            return String(format: copy(.updateCurrentDetail), version)
        case let .available(_, name, _):
            return name.isEmpty ? copy(.updateAvailableDetail) : name
        case .failed:
            return copy(.updateFailedDetail)
        }
    }

    var historyRangeTitle: String {
        switch (language, historyRange) {
        case (.spanish, .twoHours): return "Últimas 2 horas"
        case (.spanish, .day): return "Últimas 24 horas"
        case (.spanish, .week): return "Últimos 7 días"
        case (.spanish, .month): return "Últimos 30 días"
        case (.spanish, .quarter): return "Últimos 90 días"
        case (.spanish, .year): return "Último año"
        case (.spanish, .all): return "Todo el historial"
        case (.english, .twoHours): return "Last 2 hours"
        case (.english, .day): return "Last 24 hours"
        case (.english, .week): return "Last 7 days"
        case (.english, .month): return "Last 30 days"
        case (.english, .quarter): return "Last 90 days"
        case (.english, .year): return "Last year"
        case (.english, .all): return "All history"
        }
    }

    var historyWindowLabel: String {
        guard let start = historyStartDate else {
            return language == .spanish ? "Sin fecha todavía" : "No date yet"
        }
        let end = historyEndDate
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
        dayFormatter.dateFormat = language == .spanish ? "d MMM" : "MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = dayFormatter.locale
        timeFormatter.dateFormat = "HH:mm"

        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(timeFormatter.string(from: start)) – \(timeFormatter.string(from: end)) · \(dayFormatter.string(from: start))"
        }
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = dayFormatter.locale
        dateTimeFormatter.dateFormat = language == .spanish ? "d MMM HH:mm" : "MMM d HH:mm"
        return "\(dateTimeFormatter.string(from: start)) – \(dateTimeFormatter.string(from: end))"
    }

    var historyAxisStartLabel: String {
        historyAxisLabel(for: historyStartDate)
    }

    var historyAxisEndLabel: String {
        historyAxisLabel(for: historyEndDate)
    }

    var historyAxisMidLabel: String {
        guard let start = historyStartDate else { return "—" }
        let midpoint = start.addingTimeInterval(historyEndDate.timeIntervalSince(start) / 2)
        return historyAxisLabel(for: midpoint)
    }

    private var historyStartDate: Date? {
        historyAggregates.first?.bucketStart ?? historyRange.since ?? learningFirstDate
    }

    private var historyEndDate: Date {
        historyAggregates.last?.bucketStart ?? Date()
    }

    private func historyAxisLabel(for date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
        formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: historyEndDate)
            ? "HH:mm"
            : (language == .spanish ? "d MMM HH:mm" : "MMM d HH:mm")
        return formatter.string(from: date)
    }

    var learningDaysLabel: String {
        if language == .spanish {
            return "\(learningDaysObserved)/7 días"
        }
        return "\(learningDaysObserved)/7 days"
    }

    var learnedBatterySymbol: String {
        if statusKind == .attention { return "exclamationmark.triangle" }
        if battery.isCharging { return "bolt.circle" }
        if learningDaysObserved == 0 { return "hourglass" }
        return "waveform.path.ecg"
    }

    var learnedBatteryTitle: String {
        guard learningEnabled else { return language == .spanish ? "Aprendizaje pausado" : "Learning paused" }
        switch learningDaysObserved {
        case 0:
            return language == .spanish ? "Reuniendo evidencia" : "Collecting evidence"
        case 1:
            return language == .spanish ? "Lectura provisional" : "Provisional reading"
        default:
            return language == .spanish ? "Patrón inicial" : "Initial pattern"
        }
    }

    var learnedBatteryDetail: String {
        guard learningEnabled else {
            return language == .spanish
                ? "Activa el aprendizaje para comparar días reales."
                : "Enable learning to compare real usage days."
        }
        guard learningDaysObserved > 0 else {
            return language == .spanish
                ? "Todavía no hay días completos para describir tu rutina."
                : "There are not enough complete days to describe your routine yet."
        }

        let charge = battery.chargePercent.map { "\($0)%" } ?? "—"
        let state = chargeStateLabel.lowercased()
        if let averagePower = learningAveragePowerWatts {
            let absolutePower = String(format: language == .spanish ? "%.1f" : "%.1f", abs(averagePower))
            let direction: String
            if averagePower > 0.05 {
                direction = language == .spanish ? "de descarga" : "of discharge"
            } else if averagePower < -0.05 {
                direction = language == .spanish ? "de entrada" : "of input"
            } else {
                direction = language == .spanish ? "estable" : "stable"
            }
            if learningDaysObserved < 2 {
                return language == .spanish
                    ? "Ahora: \(charge), \(state). Media observada: \(absolutePower) W \(direction). Falta comparar otro día."
                    : "Now: \(charge), \(state). Observed average: \(absolutePower) W \(direction). Another day is needed for comparison."
            }
            return language == .spanish
                ? "Ahora: \(charge), \(state). En \(learningDaysObserved) días: \(absolutePower) W \(direction) de media."
                : "Now: \(charge), \(state). Across \(learningDaysObserved) days: \(absolutePower) W \(direction) on average."
        }

        let dayWord = learningDaysObserved == 1 ? (language == .spanish ? "día" : "day") : (language == .spanish ? "días" : "days")
        return language == .spanish
            ? "Ahora: \(charge), \(state). Hay \(learningDaysObserved) \(dayWord), pero aún no hay potencia suficiente para inferir una tendencia."
            : "Now: \(charge), \(state). There are \(learningDaysObserved) observed \(dayWord), but not enough power data for a trend yet."
    }

    private var learningAveragePowerWatts: Double? {
        let values = learningAggregates.compactMap(\.averageBatteryPowerWatts)
            .filter { $0.isFinite && abs($0) >= 0.05 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var statusKind: DashboardStatus {
        if system.thermalState == .serious || system.thermalState == .critical {
            return .attention
        }
        if let temperature = battery.temperatureCelsius, temperature >= temperatureAlertCelsius {
            return .attention
        }
        if let charge = battery.chargePercent, charge <= criticalChargePercent {
            return .attention
        }
        if let dischargeRate = effectiveBatteryPercentPerMinute, dischargeRate >= 0.35 {
            return .attention
        }
        if samplingGapMinutes != nil {
            return .attention
        }
        if let cpu = system.cpuUsagePercent, cpu >= 90 {
            return .attention
        }
        if let memory = system.memoryUsedPercent, memory >= 90 {
            return .attention
        }
        if let disk = system.diskUsedPercent, disk >= 95 {
            return .attention
        }
        if battery.externalPowerConnected && battery.isCharging {
            return .charging
        }
        return .protected
    }

    var statusTitle: String {
        switch statusKind {
        case .protected:
            return copy(.protected)
        case .charging:
            return copy(.charging)
        case .attention:
            return copy(.attention)
        }
    }

    var statusExplanation: String {
        if system.thermalState == .critical {
            return copy(.thermalCritical)
        }
        if system.thermalState == .serious {
            return copy(.thermalSerious)
        }
        if let dischargeRate = effectiveBatteryPercentPerMinute, dischargeRate >= 0.35 {
            return String(format: copy(.rapidDischargeAlert), dischargeRate)
        }
        if let gapMinutes = samplingGapMinutes {
            return String(format: copy(.captureGapAlert), gapMinutes)
        }
        if let temperature = battery.temperatureCelsius, temperature >= temperatureAlertCelsius {
            return String(format: copy(.temperatureAlert), temperature, temperatureAlertCelsius)
        }
        if let charge = battery.chargePercent, charge <= criticalChargePercent {
            return String(format: copy(.criticalChargeAlert), charge, criticalChargePercent)
        }
        if let cpu = system.cpuUsagePercent, cpu >= 90 {
            return String(format: copy(.cpuAlert), cpu)
        }
        if let memory = system.memoryUsedPercent, memory >= 90 {
            return String(format: copy(.memoryAlert), memory)
        }
        if let disk = system.diskUsedPercent, disk >= 95 {
            return String(format: copy(.diskAlert), disk)
        }
        if battery.externalPowerConnected && battery.isCharging {
            return copy(.chargingExplanation)
        }
        guard let weatherSnapshot else { return copy(.protectedExplanation) }
        return "\(copy(.protectedExplanation)) \(String(format: copy(.weatherContext), weatherSnapshot.temperatureCelsius, weatherSnapshot.conditionLabel(for: language)))"
    }

    var chargeStateLabel: String {
        if battery.isFullyCharged { return copy(.fullyCharged) }
        if battery.isCharging { return copy(.charging) }
        return copy(.discharging)
    }

    var learningProgress: Double {
        guard learningEnabled else { return 0 }
        return min(1, Double(learningDaysObserved) / 7)
    }

    var learningTitle: String {
        guard learningEnabled else { return copy(.learningPaused) }
        switch learningDaysObserved {
        case 0:
            return copy(.learningStarting)
        case 1..<7:
            return copy(.learningCollecting)
        default:
            return copy(.learningReady)
        }
    }

    var learningDetail: String {
        guard learningEnabled else { return copy(.learningPausedDetail) }
        if learningDaysObserved == 0 {
            return copy(.learningNoEvidence)
        }
        let remaining = max(0, 7 - learningDaysObserved)
        if remaining == 0 {
            return String(format: copy(.learningEvidence), learningDaysObserved, storedSampleCount)
        }
        return String(format: copy(.learningProgress), learningDaysObserved, 7, storedSampleCount)
    }

    var learningConfidence: String {
        guard learningEnabled else { return copy(.notActive) }
        switch learningDaysObserved {
        case 0:
            return copy(.noEvidence)
        case 1..<7:
            return copy(.buildingConfidence)
        default:
            return copy(.confidenceReady)
        }
    }

    var updatedLabel: String {
        guard let lastUpdated else { return copy(.waitingForReading) }
        let seconds = max(0, Int(Date().timeIntervalSince(lastUpdated)))
        if seconds < 10 { return copy(.justNow) }
        if seconds < 60 { return String(format: copy(.secondsAgo), seconds) }
        return String(format: copy(.minutesAgo), max(1, seconds / 60))
    }

    var isLive: Bool {
        guard let lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) < 15
    }

    var chargeLimitCapability: ChargeLimitCapability {
        .unsupported
    }

    func refresh() {
        refreshLiveState(includeProcessImpacts: false)
        weatherCoordinator.refresh()
        syncWeatherState()
    }

    func refreshHistory() {
        guard !isRefreshingHistory else { return }
        lastHistoryRefresh = Date()
        isRefreshingHistory = true
        Task { @MainActor [weak self] in
            await self?.loadHistory()
        }
    }

    private func loadHistory() async {
        isRefreshingHistory = true
        defer { isRefreshingHistory = false }
        samplingMode = await coordinator.currentMode()
        pendingSampleCount = await coordinator.pendingSampleCount()
        pendingSessionCount = await coordinator.pendingSessionCount()
        guard let store else {
            recentSamples = []
            recentSessions = []
            historyAggregates = []
            learningAggregates = []
            processImpacts = []
            storeDiagnostics = nil
            storeError = "Local storage is unavailable."
            storedSampleCount = 0
            learningDaysObserved = 0
            learningFirstDate = nil
            learningLastDate = nil
            return
        }

        do {
            try? await coordinator.flush()
            _ = try? await store.applyRetentionIfNeeded()
            let sessionSince = Date().addingTimeInterval(-24 * 60 * 60)
            let aggregateSamples = try await store.fetchAggregates(
                resolution: historyRange.resolution,
                since: historyRange.since,
                limit: 2_000
            )
            let learnedSamples = try await store.fetchAggregates(
                resolution: .day,
                since: Date().addingTimeInterval(-7 * 86_400),
                limit: 7
            )
            let evidence = try await store.sampleEvidence()
            storedSampleCount = evidence.sampleCount
            learningDaysObserved = evidence.observedDays
            learningFirstDate = evidence.firstSampleDate
            learningLastDate = evidence.lastSampleDate
            let nextLearningAggregates = Array(learnedSamples.reversed())
            let nextRecentSamples = try await store.fetchBatterySamples(
                since: Date().addingTimeInterval(-30 * 60),
                limit: 60
            )
            let nextRecentSessions = try await store.fetchSessions(since: sessionSince, limit: 5)
            let nextHistoryAggregates = Array(aggregateSamples.reversed())
            let nextDiagnostics = try await store.diagnostics()
            if learningAggregates != nextLearningAggregates {
                learningAggregates = nextLearningAggregates
            }
            if recentSamples != nextRecentSamples {
                recentSamples = nextRecentSamples
            }
            if recentSessions != nextRecentSessions {
                recentSessions = nextRecentSessions
            }
            if historyAggregates != nextHistoryAggregates {
                historyAggregates = nextHistoryAggregates
            }
            if storeDiagnostics != nextDiagnostics {
                storeDiagnostics = nextDiagnostics
            }
            storeError = nil
        } catch {
            recentSamples = []
            recentSessions = []
            historyAggregates = []
            learningAggregates = []
            processImpacts = []
            storeDiagnostics = nil
            storedSampleCount = 0
            learningDaysObserved = 0
            learningFirstDate = nil
            learningLastDate = nil
            if let storeError = error as? StoreError {
                self.storeError = storeError.userMessage
            } else {
                self.storeError = String(describing: error)
            }
        }
    }

    func setHistoryRange(_ range: HistoryRange) {
        historyRange = range
        if panelVisible {
            refreshHistory()
        }
    }

    func setHistoryMetric(_ metric: DashboardHistoryMetric) {
        historyMetric = metric
    }

    func setShowingSettings(_ showing: Bool) {
        showingSettings = showing
    }

    func setUpdateCheckEnabled(_ enabled: Bool) {
        updateCheckEnabled = enabled
        defaults.set(enabled, forKey: "cellium.updateCheckEnabled")
        if enabled {
            checkForUpdatesIfNeeded(force: true)
        } else {
            updateTask?.cancel()
            updateTask = nil
            updateState = .idle
        }
    }

    func checkForUpdates() {
        checkForUpdatesIfNeeded(force: true)
    }

    func checkForUpdatesIfNeeded(force: Bool = false) {
        guard force || updateCheckEnabled else { return }
        if !force,
           let lastUpdateCheck,
           Date().timeIntervalSince(lastUpdateCheck) < 86_400 {
            return
        }

        updateTask?.cancel()
        updateState = .checking
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await updateChecker.check(currentVersion: installedVersion)
                guard !Task.isCancelled else { return }
                let checkedAt = Date()
                lastUpdateCheck = checkedAt
                defaults.set(checkedAt, forKey: "cellium.lastUpdateCheck")
                switch result {
                case let .current(version):
                    updateState = .current(version: version)
                case let .available(release):
                    updateState = .available(
                        version: release.tagName,
                        name: release.name,
                        url: release.htmlURL
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                lastUpdateCheck = Date()
                defaults.set(lastUpdateCheck, forKey: "cellium.lastUpdateCheck")
                updateState = .failed
            }
        }
    }

    func openUpdatePage() {
        guard let updateReleaseURL else { return }
        NSWorkspace.shared.open(updateReleaseURL)
    }

    func setWeatherLocationMode(_ mode: WeatherLocationMode) {
        weatherCoordinator.setMode(mode)
        syncWeatherState()
    }

    func saveManualWeatherLocation() {
        weatherCoordinator.saveManualLocation(
            label: manualWeatherLabel,
            latitude: manualWeatherLatitude,
            longitude: manualWeatherLongitude
        )
        syncWeatherState()
    }

    func setManualWeatherLabel(_ value: String) {
        manualWeatherLabel = value
    }

    func setManualWeatherLatitude(_ value: String) {
        manualWeatherLatitude = value
    }

    func setManualWeatherLongitude(_ value: String) {
        manualWeatherLongitude = value
    }

    func requestWeatherLocationAgain() {
        weatherCoordinator.requestLocationAgain()
        syncWeatherState()
    }

    func refreshWeather() {
        weatherCoordinator.refresh()
        syncWeatherState()
    }

    func setLanguage(_ language: CelliumLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: "cellium.language")
    }

    func setSamplingPreference(_ preference: SamplingPreference) {
        samplingPreference = preference
        defaults.set(preference.rawValue, forKey: "cellium.samplingPreference")
        Task { await coordinator.setIntervalOverride(configuredSamplingInterval) }
    }

    func setCustomSamplingInterval(_ value: String) {
        guard let seconds = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        setCustomSamplingInterval(Double(seconds))
    }

    func setCustomSamplingInterval(_ value: Double, activate: Bool = false) {
        if activate, samplingPreference != .custom {
            samplingPreference = .custom
            defaults.set(SamplingPreference.custom.rawValue, forKey: "cellium.samplingPreference")
        }
        customSamplingIntervalSeconds = min(3_600, max(1, Int(value.rounded())))
        defaults.set(customSamplingIntervalSeconds, forKey: "cellium.customSamplingIntervalSeconds")
        guard samplingPreference == .custom else { return }
        Task { await coordinator.setIntervalOverride(configuredSamplingInterval) }
    }

    func setLearningEnabled(_ enabled: Bool) {
        learningEnabled = enabled
        defaults.set(enabled, forKey: "cellium.learningEnabled")
    }

    func setTemperatureAlertCelsius(_ value: Double) {
        temperatureAlertCelsius = min(60, max(30, value))
        defaults.set(temperatureAlertCelsius, forKey: "cellium.temperatureAlertCelsius")
    }

    func setCriticalChargePercent(_ value: Double) {
        criticalChargePercent = min(40, max(5, Int(value.rounded())))
        defaults.set(criticalChargePercent, forKey: "cellium.criticalChargePercent")
    }

    func startMonitoring() {
        let mode = backgroundMode
        weatherCoordinator.start()
        checkForUpdatesIfNeeded()
        syncWeatherState()
        backgroundHealthTask?.cancel()
        backgroundHealthTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if !self.panelVisible {
                    self.refreshLiveState(includeBackgroundProcesses: true)
                    try? await self.coordinator.flush()
                    await self.refreshBackgroundSamples()
                    self.evaluateProactiveSignals()
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        let intervalOverride = configuredSamplingInterval
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.coordinator.setIntervalOverride(intervalOverride)
            await self.coordinator.setMode(mode)
            guard !self.panelVisible else { return }
            _ = await self.coordinator.sampleNow()
            try? await self.coordinator.flush()
            self.refreshLiveState(includeBackgroundProcesses: true)
        }
    }

    func setPanelVisible(_ isVisible: Bool) {
        guard panelVisible != isVisible else { return }
        panelVisible = isVisible
        panelVisibilityTask?.cancel()
        panelVisibilityTask = nil
        let mode = isVisible ? SamplingMode.quickPanelVisible : backgroundMode

        if isVisible {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
            lastPersistedDataRefresh = nil
            lastProcessImpactRefresh = nil
            weatherCoordinator.refresh()
            syncWeatherState()
        } else {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
            refreshLiveState(includeBackgroundProcesses: true)
            evaluateProactiveSignals()
        }

        panelVisibilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            guard !Task.isCancelled, self.panelVisible == isVisible else { return }
            await self.coordinator.setIntervalOverride(self.configuredSamplingInterval)
            await self.coordinator.setMode(mode)
            guard !Task.isCancelled, self.panelVisible == isVisible else { return }

            if isVisible {
                // Defer the first sample and SQLite refresh until AppKit has
                // had a chance to draw the panel with the latest in-memory data.
                _ = await self.coordinator.sampleNow()
                guard !Task.isCancelled, self.panelVisible else { return }
                try? await self.coordinator.flush()
                guard !Task.isCancelled, self.panelVisible else { return }
                self.lastHistoryRefresh = Date()
                await self.loadHistory()
                guard !Task.isCancelled, self.panelVisible else { return }
                self.startLiveRefresh()
            } else {
                try? await self.coordinator.flush()
            }
        }
    }

    func handleSleep() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        Task { await coordinator.setMode(.idle) }
    }

    func handleWake() {
        refreshAndApplyMode()
        if panelVisible { startLiveRefresh() }
    }

    func handlePowerStateChange() {
        refreshAndApplyMode()
    }

    func handleThermalStateChange() {
        refreshAndApplyMode()
    }

    func stopMonitoring() async {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        panelVisibilityTask?.cancel()
        panelVisibilityTask = nil
        backgroundHealthTask?.cancel()
        backgroundHealthTask = nil
        try? await coordinator.stopAndFlush()
    }

    private func refreshAndApplyMode() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            refreshLiveState()
            let mode = panelVisible ? SamplingMode.quickPanelVisible : backgroundMode
            await coordinator.setIntervalOverride(configuredSamplingInterval)
            await coordinator.setMode(mode)
            try? await coordinator.flush()
        }
    }

    private func refreshLiveState(
        includeBackgroundProcesses: Bool = false,
        includeProcessImpacts: Bool = true
    ) {
        let date = Date()
        battery = batteryReader.readSnapshot(at: date)
        system = systemReader.readSnapshot(at: date)
        lastUpdated = date
        if includeProcessImpacts {
            refreshProcessImpactsIfNeeded(
                at: date,
                allowBackground: includeBackgroundProcesses
            )
        }
        evaluateProactiveSignals()
    }

    private func refreshProcessImpactsIfNeeded(
        at date: Date,
        force: Bool = false,
        allowBackground: Bool = false
    ) {
        guard panelVisible || allowBackground else { return }
        let minimumInterval: TimeInterval = panelVisible
            ? (processImpacts.isEmpty ? 15 : 60)
            : 120
        if !force,
           let lastProcessImpactRefresh,
           date.timeIntervalSince(lastProcessImpactRefresh) < minimumInterval {
            return
        }
        self.lastProcessImpactRefresh = date
        let nextImpacts = processMonitor.topImpacts(
            limit: 6,
            batteryPercentPerMinute: effectiveBatteryPercentPerMinute,
            memoryTotalBytes: system.memoryTotalBytes
        )
        if !nextImpacts.isEmpty || processImpacts.isEmpty,
           processImpacts != nextImpacts {
            processImpacts = nextImpacts
        }
    }

    private func syncWeatherState() {
        weatherSnapshot = weatherCoordinator.snapshot
        weatherError = weatherCoordinator.errorMessage
        weatherLocationMode = weatherCoordinator.mode
        manualWeatherLabel = weatherCoordinator.manualLabel
        manualWeatherLatitude = weatherCoordinator.manualLatitude
        manualWeatherLongitude = weatherCoordinator.manualLongitude
    }

    private func refreshPersistedDataIfNeeded(force: Bool = false) async {
        let now = Date()
        if !force,
           let lastPersistedDataRefresh,
           now.timeIntervalSince(lastPersistedDataRefresh) < 30 {
            return
        }
        lastPersistedDataRefresh = now
        try? await coordinator.flush()
        guard let store else { return }
        do {
            _ = try? await store.applyRetentionIfNeeded(now: now)
            let nextRecentSamples = try await store.fetchBatterySamples(
                since: now.addingTimeInterval(-30 * 60),
                limit: 60
            )
            if recentSamples != nextRecentSamples {
                recentSamples = nextRecentSamples
            }
            refreshProcessImpactsIfNeeded(
                at: now,
                allowBackground: !panelVisible
            )
            if panelVisible,
               lastHistoryRefresh == nil || now.timeIntervalSince(lastHistoryRefresh ?? .distantPast) >= 60 {
                refreshHistory()
            }
        } catch {
            // The live snapshot remains available even when the local store is unavailable.
        }
    }

    private func refreshBackgroundSamples() async {
        await refreshPersistedDataIfNeeded(force: true)
    }

    private func evaluateProactiveSignals() {
        let candidate: ProactiveAlert?
        if let app = processImpacts.first(where: { isHighMemoryImpact($0) }) {
            let memory = memoryDescription(for: app)
            candidate = ProactiveAlert(
                identifier: "memory:\(app.id)",
                title: language == .spanish ? "RAM alta" : "High memory use",
                body: String(format: copy(.appMemoryAlert), app.name, memory)
            )
        } else if let gapMinutes = samplingGapMinutes {
            candidate = ProactiveAlert(
                identifier: "capture-gap",
                title: language == .spanish ? "Muestra perdida" : "Capture gap",
                body: String(format: copy(.captureGapAlert), gapMinutes)
            )
        } else if let dischargeRate = effectiveBatteryPercentPerMinute, dischargeRate >= 0.35 {
            candidate = ProactiveAlert(
                identifier: "discharge",
                title: language == .spanish ? "Descarga rápida" : "Fast battery drain",
                body: String(format: copy(.rapidDischargeAlert), dischargeRate)
            )
        } else if let app = processImpacts.first(where: { ($0.estimatedBatteryPercentPerMinute ?? 0) >= 0.05 }),
                  let rate = app.estimatedBatteryPercentPerMinute {
            candidate = ProactiveAlert(
                identifier: "energy:\(app.id)",
                title: language == .spanish ? "Impacto de energía" : "Energy impact",
                body: String(format: copy(.appEnergyAlert), app.name, rate)
            )
        } else if let memory = system.memoryUsedPercent, memory >= 90 {
            candidate = ProactiveAlert(
                identifier: "system-memory",
                title: language == .spanish ? "RAM alta" : "High memory use",
                body: String(format: copy(.memoryAlert), memory)
            )
        } else {
            candidate = nil
        }

        proactiveAlert = candidate
        guard let candidate else {
            lastProactiveAlertKey = nil
            lastProactiveAlertDate = nil
            return
        }
        let now = Date()
        if candidate.identifier == lastProactiveAlertKey,
           let lastProactiveAlertDate,
           now.timeIntervalSince(lastProactiveAlertDate) < 20 * 60 {
            return
        }
        lastProactiveAlertKey = candidate.identifier
        lastProactiveAlertDate = now
        onProactiveAlert?(candidate)
    }

    private func isHighMemoryImpact(_ impact: ProcessEnergyImpact) -> Bool {
        if let memoryPercent = impact.memoryPercent, memoryPercent >= 20 {
            return true
        }
        return (impact.residentMemoryBytes ?? 0) >= 4 * 1_024 * 1_024 * 1_024
    }

    private func memoryDescription(for impact: ProcessEnergyImpact) -> String {
        if let bytes = impact.residentMemoryBytes {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
        }
        return language == .spanish ? "mucha" : "high"
    }

    private func startLiveRefresh() {
        liveRefreshTask?.cancel()
        let refreshInterval = max(5, min(15, expectedSampleInterval))
        let refreshNanoseconds = UInt64(refreshInterval * 1_000_000_000)
        liveRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                refreshLiveState()
                await refreshPersistedDataIfNeeded()
                try? await Task.sleep(nanoseconds: refreshNanoseconds)
            }
        }
    }

    private var backgroundMode: SamplingMode {
        if system.thermalState == .serious || system.thermalState == .critical {
            return .idle
        }
        // Keep low-power mode observable: idling here would create exactly the
        // missing evidence needed to explain a sudden battery drop.
        return battery.externalPowerConnected ? .backgroundOnAC : .backgroundOnBattery
    }
}

struct ProcessEnergyImpact: Identifiable, Equatable {
    let id: Int32
    let name: String
    let icon: NSImage?
    let averageCPUPercent: Double
    let residentMemoryBytes: Int64?
    let memoryPercent: Double?
    let estimatedBatteryPercentPerMinute: Double?

    static func == (lhs: ProcessEnergyImpact, rhs: ProcessEnergyImpact) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.averageCPUPercent == rhs.averageCPUPercent
            && lhs.residentMemoryBytes == rhs.residentMemoryBytes
            && lhs.memoryPercent == rhs.memoryPercent
            && lhs.estimatedBatteryPercentPerMinute == rhs.estimatedBatteryPercentPerMinute
    }

    var intensity: ProcessImpactIntensity {
        if let estimatedBatteryPercentPerMinute {
            switch estimatedBatteryPercentPerMinute {
            case ..<0.03: return .low
            case ..<0.08: return .medium
            default: return .high
            }
        }
        switch averageCPUPercent {
        case ..<5: return .low
        case ..<20: return .medium
        default: return .high
        }
    }
}

enum ProcessImpactIntensity {
    case low
    case medium
    case high
}

@MainActor
final class ProcessEnergyMonitor {
    private struct ProcessUsage {
        let application: NSRunningApplication
        let cpuPercent: Double
        let residentMemoryBytes: Int64?
    }

    private struct ProcessObservation {
        let date: Date
        let cpuPercent: Double
        let residentMemoryBytes: Int64?
        let estimatedBatteryPercentPerMinute: Double?
    }

    private let observationWindow: TimeInterval = 60 * 60
    private var previousCPUSeconds: [Int32: (seconds: Double, date: Date)] = [:]
    private var observations: [Int32: [ProcessObservation]] = [:]
    private var lastRankOrder: [Int32: Int] = [:]

    func topImpacts(
        limit: Int,
        batteryPercentPerMinute: Double?,
        memoryTotalBytes: Int64?
    ) -> [ProcessEnergyImpact] {
        guard limit > 0 else { return [] }
        let now = Date()
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter { application in
            application.processIdentifier != currentProcessID
                && application.activationPolicy == .regular
                && !application.isTerminated
                && !(application.localizedName ?? "").isEmpty
        }
        let activeIDs = Set(applications.map(\.processIdentifier))
        previousCPUSeconds = previousCPUSeconds.filter { activeIDs.contains($0.key) }
        observations = observations.filter { activeIDs.contains($0.key) }
        lastRankOrder = lastRankOrder.filter { activeIDs.contains($0.key) }

        let usages = applications.compactMap { processUsage(for: $0, at: now) }
        let totalCPU = max(1, usages.reduce(0) { $0 + $1.cpuPercent })
        let cutoff = now.addingTimeInterval(-observationWindow)

        for usage in usages {
            let processID = usage.application.processIdentifier
            let cpuShare = max(0, min(1, usage.cpuPercent / totalCPU))
            let estimatedBatteryPercentPerMinute = batteryPercentPerMinute.map {
                max(0, $0) * cpuShare
            }
            var processObservations = observations[processID, default: []]
            processObservations.append(
                ProcessObservation(
                    date: now,
                    cpuPercent: usage.cpuPercent,
                    residentMemoryBytes: usage.residentMemoryBytes,
                    estimatedBatteryPercentPerMinute: estimatedBatteryPercentPerMinute
                )
            )
            processObservations.removeAll { $0.date < cutoff }
            if processObservations.count > 60 {
                processObservations.removeFirst(processObservations.count - 60)
            }
            observations[processID] = processObservations
        }

        let impacts = usages.compactMap { usage -> ProcessEnergyImpact? in
            let processID = usage.application.processIdentifier
            guard let history = observations[processID], !history.isEmpty else { return nil }
            let averageCPU = history.reduce(0) { $0 + $1.cpuPercent } / Double(history.count)
            let memorySamples = history.compactMap(\.residentMemoryBytes)
            let averageMemoryBytes: Int64? = memorySamples.isEmpty
                ? nil
                : memorySamples.reduce(0, +) / Int64(memorySamples.count)
            let batterySamples = history.compactMap(\.estimatedBatteryPercentPerMinute)
            let averageBatteryRate: Double? = batterySamples.isEmpty
                ? nil
                : batterySamples.reduce(0, +) / Double(batterySamples.count)
            let memoryPercent: Double?
            if let averageMemoryBytes, let memoryTotalBytes, memoryTotalBytes > 0 {
                memoryPercent = Double(averageMemoryBytes) / Double(memoryTotalBytes) * 100
            } else {
                memoryPercent = nil
            }
            return ProcessEnergyImpact(
                id: processID,
                name: usage.application.localizedName ?? "Unknown",
                icon: nil,
                averageCPUPercent: averageCPU,
                residentMemoryBytes: averageMemoryBytes,
                memoryPercent: memoryPercent,
                estimatedBatteryPercentPerMinute: averageBatteryRate
            )
        }

        let sorted = impacts.sorted { left, right in
            let leftEnergy = left.estimatedBatteryPercentPerMinute ?? 0
            let rightEnergy = right.estimatedBatteryPercentPerMinute ?? 0
            if abs(leftEnergy - rightEnergy) > 0.005 {
                return leftEnergy > rightEnergy
            }
            if abs(left.averageCPUPercent - right.averageCPUPercent) > 0.25 {
                return left.averageCPUPercent > right.averageCPUPercent
            }
            let leftRank = lastRankOrder[left.id] ?? Int.max
            let rightRank = lastRankOrder[right.id] ?? Int.max
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
        let result = Array(sorted.prefix(limit))
        lastRankOrder = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.element.id, $0.offset) })
        return result.map { impact in
            guard let application = applications.first(where: { $0.processIdentifier == impact.id }) else {
                return impact
            }
            return ProcessEnergyImpact(
                id: impact.id,
                name: impact.name,
                icon: application.icon,
                averageCPUPercent: impact.averageCPUPercent,
                residentMemoryBytes: impact.residentMemoryBytes,
                memoryPercent: impact.memoryPercent,
                estimatedBatteryPercentPerMinute: impact.estimatedBatteryPercentPerMinute
            )
        }
    }

    private func processUsage(for application: NSRunningApplication, at date: Date) -> ProcessUsage? {
        let processID = application.processIdentifier
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<rusage_info_v4>.size,
            alignment: MemoryLayout<rusage_info_v4>.alignment
        )
        defer { raw.deallocate() }

        let result = proc_pid_rusage(
            processID,
            RUSAGE_INFO_V4,
            raw.assumingMemoryBound(to: rusage_info_t?.self)
        )
        guard result == 0 else { return nil }

        let usage = raw.assumingMemoryBound(to: rusage_info_v4.self).pointee
        let cpuSeconds = (Double(usage.ri_user_time) + Double(usage.ri_system_time)) / 1_000_000_000
        guard let previous = previousCPUSeconds[processID] else {
            previousCPUSeconds[processID] = (cpuSeconds, date)
            return nil
        }
        let elapsed = max(1, date.timeIntervalSince(previous.date))
        let delta = max(0, cpuSeconds - previous.seconds)
        let cpuPercent = min(400, max(0, delta / elapsed * 100))
        previousCPUSeconds[processID] = (cpuSeconds, date)

        return ProcessUsage(
            application: application,
            cpuPercent: cpuPercent,
            residentMemoryBytes: residentMemoryBytes(for: processID)
        )
    }

    private func residentMemoryBytes(for processID: Int32) -> Int64? {
        var info = proc_taskallinfo()
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(
                processID,
                PROC_PIDTASKALLINFO,
                0,
                $0,
                Int32(MemoryLayout<proc_taskallinfo>.size)
            )
        }
        guard result >= Int32(MemoryLayout<proc_taskallinfo>.size) else { return nil }
        return Int64(info.ptinfo.pti_resident_size)
    }
}

struct QuickPanelView: View {
    @ObservedObject var model: BatteryViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CelliumDashboardView(model: model)
    }

    private var header: some View {
        HStack(alignment: .center) {
            BrandMark()
                .frame(width: 24, height: 24)
            Text("Cellium")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            Text(chargeText)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(CelliumBrand.accentStrong)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(0.8)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            Text(statusExplanation)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CelliumBrand.border, lineWidth: 1)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            MetricView(title: "Health", value: healthText, quality: "calculated")
            MetricView(title: "Temperature", value: temperatureText, quality: "measured")
            MetricView(title: "Cycles", value: cycleText, quality: "measured")
        }
    }

    private var drivers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System state")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            HStack(spacing: 8) {
                StatePill(title: model.system.thermalState.rawValue.capitalized, color: CelliumBrand.accent)
                StatePill(title: model.system.lowPowerModeEnabled ? "Low Power" : "Automatic", color: CelliumBrand.info)
                if let watts = model.batteryPowerWatts {
                    StatePill(title: String(format: "%.1f W", watts), color: watts > 0 ? CelliumBrand.warning : CelliumBrand.accent)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Text("Read-only monitoring")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            Spacer()
            Text("Diagnostics →")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CelliumBrand.accentStrong)
        }
    }

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History & diagnostics")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                Spacer()
                Picker("History range", selection: Binding(
                    get: { model.historyRange },
                    set: { model.setHistoryRange($0) }
                )) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .pickerStyle(.menu)
                Button {
                    model.refreshHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CelliumBrand.accentStrong)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh history and diagnostics")
            }

            if let storeError = model.storeError {
                Label(storeError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CelliumBrand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if model.historyAggregates.isEmpty {
                    Text("No data recorded for this range.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                } else {
                    HistoryChart(aggregates: model.historyAggregates)
                        .frame(height: 96)
                        .accessibilityLabel("Battery charge history for \(model.historyRange.label)")
                }

                if model.recentSamples.isEmpty {
                    Text("No recent samples recorded.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                } else {
                    ForEach(Array(model.recentSamples.prefix(3).enumerated()), id: \.offset) { _, sample in
                        HistorySampleRow(sample: sample)
                    }
                }
                if !model.recentSessions.isEmpty {
                    ForEach(Array(model.recentSessions.prefix(2).enumerated()), id: \.offset) { _, session in
                        SessionHistoryRow(session: session)
                    }
                }

                HStack(spacing: 8) {
                    Text("Quality")
                    Text(model.battery.sourceQuality.rawValue)
                    Spacer()
                    Text("Sampling")
                    Text(model.samplingMode.rawValue)
                }
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)

                if let diagnostics = model.storeDiagnostics {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SQLite v\(diagnostics.schemaVersion) · \(ByteCountFormatter.string(fromByteCount: diagnostics.databaseSizeBytes, countStyle: .file)) · WAL \(ByteCountFormatter.string(fromByteCount: diagnostics.walSizeBytes, countStyle: .file))")
                        Text("Pending writes: \(model.pendingSampleCount) samples · \(model.pendingSessionCount) sessions")
                        Text("Diagnostics: \(model.battery.diagnostics.isEmpty ? "none" : model.battery.diagnostics.joined(separator: ", "))")
                    }
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("SQLite schema \(diagnostics.schemaVersion), database size \(diagnostics.databaseSizeBytes) bytes, WAL size \(diagnostics.walSizeBytes) bytes")
                }
            }
        }
        .padding(14)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CelliumBrand.border, lineWidth: 1)
        }
    }

    private var chargeText: String {
        model.battery.chargePercent.map { "\($0)%" } ?? "—"
    }

    private var healthText: String {
        model.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—"
    }

    private var temperatureText: String {
        model.battery.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—"
    }

    private var cycleText: String {
        model.battery.cycleCount.map(String.init) ?? "—"
    }

    private var statusTitle: String {
        if model.battery.atCriticalLevel { return "ATTENTION" }
        if model.battery.externalPowerConnected && model.battery.isCharging { return "CHARGING" }
        return "PROTECTED"
    }

    private var statusExplanation: String {
        if model.battery.atCriticalLevel {
            return "Battery reports a critical level. Connect power when possible."
        }
        if model.battery.externalPowerConnected && model.battery.isCharging {
            return "The Mac is charging through its connected power source."
        }
        return "Everything looks normal. No action is required."
    }

    private var statusColor: Color {
        model.battery.atCriticalLevel ? CelliumBrand.critical : CelliumBrand.accent
    }
}

private struct MetricView: View {
    let title: String
    let value: String
    let quality: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(CelliumBrand.foreground)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            Text(quality)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatePill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct HistorySampleRow: View {
    let sample: StoredBatterySample

    var body: some View {
        HStack(spacing: 8) {
            Text(sample.battery.timestamp, style: .time)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
            Text(sample.battery.chargePercent.map { "\($0)%" } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Spacer()
            Text(sample.battery.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery sample, \(sample.battery.chargePercent.map { "\($0) percent" } ?? "charge unavailable")")
    }
}

private struct SessionHistoryRow: View {
    let session: BatterySession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.kind == .charging ? "bolt.fill" : "battery.100")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(session.kind == .charging ? CelliumBrand.warning : CelliumBrand.accent)
            Text(session.kind.rawValue.capitalized)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Spacer()
            Text("\(session.sampleCount) samples")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.kind.rawValue) session, \(session.sampleCount) samples")
    }
}

private struct HistoryChart: View {
    let aggregates: [BatteryAggregate]

    var body: some View {
        Chart {
            ForEach(Array(aggregates.enumerated()), id: \.offset) { _, aggregate in
                if let charge = aggregate.averageChargePercent {
                    LineMark(
                        x: .value("Time", aggregate.bucketStart),
                        y: .value("Charge", charge)
                    )
                    .foregroundStyle(CelliumBrand.accentStrong)
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                    .foregroundStyle(CelliumBrand.border)
                AxisValueLabel {
                    if let charge = value.as(Int.self) {
                        Text("\(charge)%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(CelliumBrand.muted)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BrandMark: View {
    var body: some View {
        if let url = CelliumAppResources.bundle.url(forResource: "Cellium_symbol_white", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Cellium")
        } else {
            Image(systemName: "battery.100")
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Cellium")
        }
    }
}
