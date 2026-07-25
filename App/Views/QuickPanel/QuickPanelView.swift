import SwiftUI
import AppKit
import Charts
import Darwin
import CelliumCore
import CelliumDarwin
import CelliumStore
import CelliumIntelligence

struct ProactiveAlert: Equatable {
    let identifier: String
    let title: String
    let body: String
    let severity: AlertSeverity
    let subject: String?
    let measurements: [String: Double]

    init(
        identifier: String,
        title: String,
        body: String,
        severity: AlertSeverity = .warning,
        subject: String? = nil,
        measurements: [String: Double] = [:]
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.severity = severity
        self.subject = subject
        self.measurements = measurements
    }
}

struct CelliumAgentSession: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var messages: [AgentChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [AgentChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case hour = "1h"
    case twoHours = "2h"
    case sixHours = "6h"
    case twelveHours = "12h"
    case day = "24h"
    case threeDays = "3d"
    case week = "7d"
    case twoWeeks = "14d"
    case month = "30d"
    case quarter = "90d"
    case halfYear = "6m"
    case year = "1y"
    case all

    var id: String { rawValue }

    func label(for language: CelliumLanguage) -> String {
        switch (self, language) {
        case (.hour, .spanish): return "1 hora"
        case (.twoHours, .spanish): return "2 horas"
        case (.sixHours, .spanish): return "6 horas"
        case (.twelveHours, .spanish): return "12 horas"
        case (.day, .spanish): return "24 horas"
        case (.threeDays, .spanish): return "3 días"
        case (.week, .spanish): return "7 días"
        case (.twoWeeks, .spanish): return "14 días"
        case (.month, .spanish): return "30 días"
        case (.quarter, .spanish): return "90 días"
        case (.halfYear, .spanish): return "6 meses"
        case (.year, .spanish): return "1 año"
        case (.all, .spanish): return "Todo el historial"
        case (.hour, .english): return "1 hour"
        case (.twoHours, .english): return "2 hours"
        case (.sixHours, .english): return "6 hours"
        case (.twelveHours, .english): return "12 hours"
        case (.day, .english): return "24 hours"
        case (.threeDays, .english): return "3 days"
        case (.week, .english): return "7 days"
        case (.twoWeeks, .english): return "14 days"
        case (.month, .english): return "30 days"
        case (.quarter, .english): return "90 days"
        case (.halfYear, .english): return "6 months"
        case (.year, .english): return "1 year"
        case (.all, .english): return "All history"
        }
    }

    var resolution: BatteryAggregateResolution {
        switch self {
        case .hour, .twoHours, .sixHours, .twelveHours, .day:
            return .minute
        case .threeDays, .week, .twoWeeks, .month:
            return .quarterHour
        case .quarter, .halfYear, .year, .all:
            return .day
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .hour:
            return 60 * 60
        case .twoHours:
            return 2 * 60 * 60
        case .sixHours:
            return 6 * 60 * 60
        case .twelveHours:
            return 12 * 60 * 60
        case .day:
            return 24 * 60 * 60
        case .threeDays:
            return 3 * 86_400
        case .week:
            return 7 * 86_400
        case .twoWeeks:
            return 14 * 86_400
        case .month:
            return 30 * 86_400
        case .quarter:
            return 90 * 86_400
        case .halfYear:
            return 182 * 86_400
        case .year:
            return 365 * 86_400
        case .all:
            return nil
        }
    }

    var since: Date? {
        duration.map { Date().addingTimeInterval(-$0) }
    }

    var aggregateFetchLimit: Int {
        guard let duration else { return 10_000 }
        let interval: TimeInterval
        switch resolution {
        case .minute:
            interval = 60
        case .quarterHour:
            interval = 15 * 60
        case .day:
            interval = 86_400
        }
        return min(10_000, max(100, Int(ceil(duration / interval)) + 2))
    }

     var displayPointLimit: Int {
         switch self {
         case .hour: return 60
         case .twoHours: return 120
         case .sixHours: return 360
         case .twelveHours: return 720
         case .day: return 720
         case .threeDays: return 720
         case .week: return 720
         case .twoWeeks: return 720
         case .month, .quarter, .halfYear, .year, .all: return 720
         }
     }

}

 private struct IntelligenceUsageBucketKey: Hashable {
     let day: Date
     let hour: Int
 }

 private struct IntelligenceUsageBucketSummary {
     let key: IntelligenceUsageBucketKey
     let activityScore: Double?
     let cpuPercent: Double?
     let memoryPercent: Double?
 }

 @MainActor
 final class BatteryViewModel: ObservableObject {
    @Published private(set) var battery: BatterySnapshot
    @Published private(set) var healthPercent: Double?
    @Published private(set) var system: SystemSnapshot
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var recentSamples: [StoredBatterySample] = [] {
        didSet {
            cachedOrderedRecentSamples = makeOrderedRecentSamples(from: recentSamples)
        }
    }
    @Published private(set) var recentSessions: [BatterySession] = []
    @Published private(set) var processHistorySamples: [StoredProcessSample] = []
    @Published private(set) var alertEvents: [StoredAlertEvent] = []
    @Published private(set) var intelligenceAnalysisLogs: [StoredIntelligenceAnalysis] = []
    @Published private(set) var historyAggregates: [BatteryAggregate] = [] {
        didSet { cachedHistoryLabels = nil }
    }
     @Published private(set) var hourlyAggregates: [BatteryAggregate] = []
     @Published private(set) var computerUseDate: Date = Calendar.autoupdatingCurrent.startOfDay(for: Date())
     @Published private(set) var learningAggregates: [BatteryAggregate] = []
     @Published private(set) var learningHourlyAggregates: [BatteryAggregate] = []
     @Published private(set) var cycleUsageQuarterHourBuckets: [StoredCycleUsageBucket] = []
     @Published private(set) var cycleUsageDailyBuckets: [StoredCycleUsageBucket] = []
     @Published private(set) var cycleUsageSummary: CycleUsageSummary?
     @Published private(set) var cyclePlanConfiguration = CyclePlanConfiguration()

    @Published private(set) var historyRange: HistoryRange = .day {
        didSet { cachedHistoryLabels = nil }
    }
    @Published private(set) var processImpacts: [ProcessEnergyImpact] = []
    @Published private(set) var storeDiagnostics: StoreDiagnostics?
    @Published private(set) var storeError: String?
    @Published private(set) var samplingMode: SamplingMode = .idle
    @Published private(set) var pendingSampleCount = 0
    @Published private(set) var pendingSessionCount = 0
    @Published private(set) var storedSampleCount = 0
    @Published private(set) var learningDaysObserved = 0
    @Published private(set) var learningFirstDate: Date? {
        didSet { cachedHistoryLabels = nil }
    }
    @Published private(set) var learningLastDate: Date?
    @Published private(set) var showingSettings = false
    @Published private(set) var language: CelliumLanguage {
        didSet { cachedHistoryLabels = nil }
    }
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
    @Published private(set) var intelligenceConfiguration: IntelligenceConfiguration
    @Published private(set) var intelligenceAPIKeyConfigured = false
    @Published private(set) var localIntelligenceInsight: BatteryInsight?
    @Published private(set) var intelligenceInsight: BatteryInsight?
    @Published private(set) var intelligenceError: String?
     @Published private(set) var intelligenceMessages: [AgentChatMessage] = []
     @Published private(set) var intelligenceSessions: [CelliumAgentSession] = []
     @Published private(set) var activeIntelligenceSessionID: UUID?
     @Published private(set) var isGeneratingIntelligence = false
     @Published private(set) var isGeneratingAnalysis = false

    @Published private(set) var showingAgent = false
    @Published private(set) var wifiAvailable = false
    @Published private(set) var isValidatingIntelligenceProvider = false
    @Published private(set) var intelligenceValidationMessage: String?

    var onProactiveAlert: ((ProactiveAlert) -> Void)?

    var isIntelligenceProviderConfigured: Bool {
        let model = intelligenceConfiguration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }

        switch intelligenceConfiguration.provider {
        case .openRouter:
            return intelligenceAPIKeyConfigured
        case .ollama:
            guard let url = intelligenceConfiguration.ollamaURL,
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                return false
            }
            return true
        }
    }

    var isIntelligenceReady: Bool {
        intelligenceConfiguration.enabled && isIntelligenceProviderConfigured
    }

    var latestIntelligenceAnalysis: StoredIntelligenceAnalysis? {
        intelligenceAnalysisLogs.first {
            $0.kind == .analysis && $0.status == .succeeded
        }
    }

    var runningIntelligenceAnalysis: StoredIntelligenceAnalysis? {
        intelligenceAnalysisLogs.first {
            $0.kind == .analysis && $0.status == .running
        }
    }

    var intelligenceAnalysisCount: Int {
        intelligenceAnalysisLogs.count
    }

    private let defaults: UserDefaults
    private var healthStabilizer = BatteryHealthStabilizer()
    private let batteryReader: IOKitBatteryReader
    private let systemReader: SystemStateReader
    private let coordinator: SamplingCoordinator
    private let store: SQLiteStore?
    private let weatherCoordinator: WeatherCoordinator
    private let cycleBudgetCoordinator = CycleBudgetCoordinator()
    private let processMonitor = ProcessEnergyMonitor()
    private let updateChecker = GitHubUpdateChecker()
    private let updateInstaller = GitHubUpdateInstaller()
    private let intelligenceService = BatteryIntelligenceService()
    private let wifiMonitor = WiFiNetworkMonitor()
    private var updateTask: Task<Void, Never>?
    private var availableUpdateAsset: GitHubReleaseAsset? = nil
    private var intelligenceTask: Task<Void, Never>?
    private var activeIntelligenceRunID: UUID?
    private var lastAutomaticIntelligenceAnalysis: Date?
    private var panelVisible = false
    private var liveRefreshTask: Task<Void, Never>?
    private var panelVisibilityTask: Task<Void, Never>?
    private var backgroundHealthTask: Task<Void, Never>?
    private var historyLoadTask: Task<Void, Never>?
    private var historyRequestID = UUID()
    private var lastProcessImpactRefresh: Date?
    private var lastPersistedDataRefresh: Date?
    private var lastHistoryRefresh: Date?
    private var cachedOrderedRecentSamples: [(date: Date, charge: Int)] = []
     private var cachedHistoryLabels: HistoryLabels?
     private var lastProactiveAlertKey: String?
     private var lastIntelligenceActionNotificationKey: String?
     private var lastIntelligenceActionNotificationDate: Date?

     private struct HistoryLabels {

        let window: String
        let start: String
        let middle: String
        let end: String
    }
    private var lastProactiveAlertDate: Date?

    init(
        batteryReader: IOKitBatteryReader = IOKitBatteryReader(),
        systemReader: SystemStateReader = SystemStateReader()
    ) {
        self.defaults = .standard
        self.batteryReader = batteryReader
        self.systemReader = systemReader
        self.cyclePlanConfiguration = Self.loadCyclePlanConfiguration(from: .standard)
        let initialLanguage = CelliumLanguage(rawValue: defaults.string(forKey: "cellium.language") ?? "") ?? .english
        self.language = initialLanguage
        let historyRangeMigrationKey = "cellium.historyRange.default24h.migrated"
        if !defaults.bool(forKey: historyRangeMigrationKey) {
            self.historyRange = .day
            defaults.set(HistoryRange.day.rawValue, forKey: "cellium.historyRange")
            defaults.set(true, forKey: historyRangeMigrationKey)
        } else {
            self.historyRange = HistoryRange(
                rawValue: defaults.string(forKey: "cellium.historyRange") ?? ""
            ) ?? .day
        }
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
         self.lastAutomaticIntelligenceAnalysis = defaults.object(forKey: "cellium.intelligence.lastAnalysis") as? Date
         self.lastIntelligenceActionNotificationKey = defaults.string(forKey: "cellium.intelligence.lastActionNotificationKey")
         self.lastIntelligenceActionNotificationDate = defaults.object(forKey: "cellium.intelligence.lastActionNotificationDate") as? Date
         self.intelligenceConfiguration = IntelligenceConfiguration(

            enabled: defaults.object(forKey: "cellium.intelligence.enabled") as? Bool ?? false,
            provider: IntelligenceProvider(
                rawValue: defaults.string(forKey: "cellium.intelligence.provider") ?? ""
            ) ?? .openRouter,
            model: defaults.string(forKey: "cellium.intelligence.model") ?? "openrouter/auto",
            automaticAnalysisEnabled: defaults.object(forKey: "cellium.intelligence.automatic") as? Bool ?? false,
            ollamaEndpoint: defaults.string(forKey: "cellium.intelligence.ollamaEndpoint") ?? "http://127.0.0.1:11434"
        )
         let sessions = Self.loadIntelligenceSessions(from: defaults, language: initialLanguage)
         self.intelligenceSessions = sessions
         self.activeIntelligenceSessionID = sessions.first?.id
         self.intelligenceMessages = sessions.first?.messages ?? []
         self.wifiAvailable = wifiMonitor.isWiFiAvailable

        self.weatherCoordinator = WeatherCoordinator()
        self.weatherCoordinator.setLanguage(initialLanguage)
        self.weatherLocationMode = weatherCoordinator.mode
        self.manualWeatherLabel = weatherCoordinator.manualLabel
        self.manualWeatherLatitude = weatherCoordinator.manualLatitude
        self.manualWeatherLongitude = weatherCoordinator.manualLongitude
        self.weatherSnapshot = weatherCoordinator.snapshot
        self.weatherError = weatherCoordinator.errorMessage
        let date = Date()
        let initialBattery = batteryReader.readSnapshot(at: date)
        self.battery = initialBattery
        let initialHealth = defaults.object(forKey: Self.healthDefaultsKey(for: initialBattery.designCapacityMAh)) as? Double
        self.healthStabilizer = BatteryHealthStabilizer(initialPercent: initialHealth)
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
        refreshHealthEstimate()
    }

    private static func loadIntelligenceMessages(from defaults: UserDefaults) -> [AgentChatMessage] {
        guard let data = defaults.data(forKey: "cellium.intelligence.chatHistory") else { return [] }
        let decoder = JSONDecoder()
        guard let messages = try? decoder.decode([AgentChatMessage].self, from: data) else { return [] }
        return Array(messages.suffix(100))
    }

    private static func loadCyclePlanConfiguration(from defaults: UserDefaults) -> CyclePlanConfiguration {
        guard let data = defaults.data(forKey: "cellium.cyclePlan.configuration"),
              let configuration = try? JSONDecoder().decode(CyclePlanConfiguration.self, from: data) else {
            return CyclePlanConfiguration()
        }
        return configuration
    }

    private func persistCyclePlanConfiguration() {
        guard let data = try? JSONEncoder().encode(cyclePlanConfiguration) else { return }
        defaults.set(data, forKey: "cellium.cyclePlan.configuration")
    }

    private static func loadIntelligenceSessions(
        from defaults: UserDefaults,
        language: CelliumLanguage
    ) -> [CelliumAgentSession] {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: "cellium.intelligence.sessions"),
           let sessions = try? decoder.decode([CelliumAgentSession].self, from: data),
           !sessions.isEmpty {
            return sessions
                .filter { !$0.messages.isEmpty }
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        let legacyMessages = loadIntelligenceMessages(from: defaults)
        guard !legacyMessages.isEmpty else { return [] }
        let title = language == .spanish ? "Nuevo chat" : "New chat"
        return [CelliumAgentSession(title: title, messages: legacyMessages)]
    }

    private static func sessionTitle(
        for messages: [AgentChatMessage],
        language: CelliumLanguage,
        fallback: String
    ) -> String {
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else {
            return fallback
        }
        let normalized = firstUserMessage.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return fallback }
        let limit = 32
        if normalized.count <= limit { return normalized }
        return String(normalized.prefix(limit - 1)) + "…"
    }

    private func persistIntelligenceSessions() {
        guard !intelligenceSessions.isEmpty,
              let data = try? JSONEncoder().encode(intelligenceSessions) else {
            defaults.removeObject(forKey: "cellium.intelligence.sessions")
            defaults.removeObject(forKey: "cellium.intelligence.chatHistory")
            return
        }
        defaults.set(data, forKey: "cellium.intelligence.sessions")
        defaults.removeObject(forKey: "cellium.intelligence.chatHistory")
    }

    private func persistIntelligenceMessages() {
        guard let activeIntelligenceSessionID,
              let index = intelligenceSessions.firstIndex(where: { $0.id == activeIntelligenceSessionID }) else {
            persistIntelligenceSessions()
            return
        }

        let messages = Array(intelligenceMessages.suffix(100))
        if messages.isEmpty {
            intelligenceSessions.remove(at: index)
            self.activeIntelligenceSessionID = nil
            persistIntelligenceSessions()
            return
        }

        let fallback = language == .spanish ? "Nuevo chat" : "New chat"
        intelligenceSessions[index].messages = messages
        intelligenceSessions[index].title = Self.sessionTitle(
            for: messages,
            language: language,
            fallback: fallback
        )
        intelligenceSessions[index].updatedAt = Date()
        intelligenceSessions.sort { $0.updatedAt > $1.updatedAt }
        persistIntelligenceSessions()
    }

    private func refreshHealthEstimate() {
        let rawHealth = BatteryMath.healthPercent(
            nominalChargeCapacityMAh: battery.nominalChargeCapacityMAh,
            designCapacityMAh: battery.designCapacityMAh
        )
        let nextHealth = healthStabilizer.update(rawHealth)
        if healthPercent != nextHealth {
            healthPercent = nextHealth
        }
        if let nextHealth {
            defaults.set(nextHealth, forKey: Self.healthDefaultsKey(for: battery.designCapacityMAh))
        }
    }

    private static func healthDefaultsKey(for designCapacityMAh: Int?) -> String {
        guard let designCapacityMAh, designCapacityMAh > 0 else {
            return "cellium.battery.health.stablePercent.unknown"
        }
        return "cellium.battery.health.stablePercent.\(designCapacityMAh)"
    }

    var chargeLimitPercent: Int? {
        guard let limit = battery.chargeLimitPercent,
              limit > 0,
              limit < 100 else {
            return nil
        }
        return limit
    }

    var isChargingToLimit: Bool {
        guard let limit = chargeLimitPercent,
              let charge = battery.chargePercent else {
            return false
        }
        return battery.externalPowerConnected && battery.isCharging && charge < limit
    }

    var isChargeLimitActive: Bool {
        guard let limit = battery.chargeLimitPercent,
              let charge = battery.chargePercent,
              limit > 0,
              limit < 100 else {
            return false
        }
        return battery.externalPowerConnected && charge >= limit
    }

    /// Equivalent-use history can remain elevated after the Mac is plugged in.
    /// Keep that historical value, but do not present it as an active discharge
    /// warning while external power is holding the battery at its limit.
    var isBatteryUseCurrentlyPausedByExternalPower: Bool {
        guard battery.externalPowerConnected else { return false }
        if battery.isCharging || isChargingToLimit || isChargeLimitActive {
            return true
        }
        guard let watts = batteryPowerWatts else {
            return true
        }
        return watts <= 0.05
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
        guard let watts = batteryPowerWatts else {
            return battery.externalPowerConnected && !battery.isCharging
                ? copy(.powerNotMeasured)
                : copy(.noReading)
        }
        return String(format: "%.1f W", watts)
    }

    var batteryPercentPerMinute: Double? {
        guard !battery.isCharging,
              !isChargeLimitActive,
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
        cachedOrderedRecentSamples
    }

    private func makeOrderedRecentSamples(
        from samples: [StoredBatterySample]
    ) -> [(date: Date, charge: Int)] {
        samples
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
        if isChargeLimitActive { return nil }
        return observedBatteryPercentPerMinute ?? batteryPercentPerMinute
    }

    var copy: CelliumCopy {
        CelliumCopy(language: language)
    }

    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2"
    }

    var updateReleaseURL: URL? {
        guard case let .available(_, _, url) = updateState else { return nil }
        return url
    }

    var isCheckingForUpdates: Bool {
        switch updateState {
        case .checking, .updating:
            return true
        default:
            return false
        }
    }

    var canInstallUpdate: Bool {
        guard case .available = updateState else { return false }
        return availableUpdateAsset != nil
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
        case .updating:
            return copy(.updating)
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
        case .updating:
            return copy(.updatingDetail)
        case .failed:
            return copy(.updateFailedDetail)
        }
    }

    var historyRangeTitle: String {
        switch (language, historyRange) {
        case (.spanish, .hour): return "Última hora"
        case (.spanish, .twoHours): return "Últimas 2 horas"
        case (.spanish, .sixHours): return "Últimas 6 horas"
        case (.spanish, .twelveHours): return "Últimas 12 horas"
        case (.spanish, .day): return "Últimas 24 horas"
        case (.spanish, .threeDays): return "Últimos 3 días"
        case (.spanish, .week): return "Últimos 7 días"
        case (.spanish, .twoWeeks): return "Últimos 14 días"
        case (.spanish, .month): return "Últimos 30 días"
        case (.spanish, .quarter): return "Últimos 90 días"
        case (.spanish, .halfYear): return "Últimos 6 meses"
        case (.spanish, .year): return "Último año"
        case (.spanish, .all): return "Todo el historial"
        case (.english, .hour): return "Last hour"
        case (.english, .twoHours): return "Last 2 hours"
        case (.english, .sixHours): return "Last 6 hours"
        case (.english, .twelveHours): return "Last 12 hours"
        case (.english, .day): return "Last 24 hours"
        case (.english, .threeDays): return "Last 3 days"
        case (.english, .week): return "Last 7 days"
        case (.english, .twoWeeks): return "Last 14 days"
        case (.english, .month): return "Last 30 days"
        case (.english, .quarter): return "Last 90 days"
        case (.english, .halfYear): return "Last 6 months"
        case (.english, .year): return "Last year"
        case (.english, .all): return "All history"
        }
    }

    var historyWindowLabel: String {
        historyLabels.window
    }

    var historyAxisStartLabel: String {
        historyLabels.start
    }

    var historyAxisEndLabel: String {
        historyLabels.end
    }

    var historyAxisMidLabel: String {
        historyLabels.middle
    }

    private var historyLabels: HistoryLabels {
        if let cachedHistoryLabels {
            return cachedHistoryLabels
        }

        let start = historyStartDate
        let end = historyEndDate
        let locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.dateFormat = language == .spanish ? "d MMM" : "MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateFormat = "HH:mm"
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = locale
        dateTimeFormatter.dateFormat = language == .spanish ? "d MMM HH:mm" : "MMM d HH:mm"
        let axisFormatter = DateFormatter()
        axisFormatter.locale = locale
        axisFormatter.dateFormat = Calendar.current.isDate(start ?? end, inSameDayAs: end)
            ? "HH:mm"
            : (language == .spanish ? "d MMM HH:mm" : "MMM d HH:mm")

        let window: String
        if let start {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                window = "\(timeFormatter.string(from: start)) – \(timeFormatter.string(from: end)) · \(dayFormatter.string(from: start))"
            } else {
                window = "\(dateTimeFormatter.string(from: start)) – \(dateTimeFormatter.string(from: end))"
            }
        } else {
            window = language == .spanish ? "Sin fecha todavía" : "No date yet"
        }

        let labels = HistoryLabels(
            window: window,
            start: start.map(axisFormatter.string(from:)) ?? "—",
            middle: start.map { axisFormatter.string(from: $0.addingTimeInterval(end.timeIntervalSince($0) / 2)) } ?? "—",
            end: axisFormatter.string(from: end)
        )
        cachedHistoryLabels = labels
        return labels
    }

    private var historyStartDate: Date? {
        historyAggregates.first?.bucketStart ?? historyRange.since ?? learningFirstDate
    }

    private var historyEndDate: Date {
        historyAggregates.last?.bucketStart ?? Date()
    }

    var learningDaysLabel: String {
        if language == .spanish {
            return "\(learningDaysObserved)/7 días con datos"
        }
        return "\(learningDaysObserved)/7 days with data"
    }

    var learnedBatterySymbol: String {
        if statusKind == .attention { return "exclamationmark.octagon" }
        if statusKind == .elevated { return "exclamationmark.triangle" }
        if battery.isCharging || isChargingToLimit || isChargeLimitActive { return "bolt.circle" }
        if learningDaysObserved == 0 { return "hourglass" }
        return "waveform.path.ecg"
    }

    var learnedBatteryTitle: String {
        guard learningEnabled else { return language == .spanish ? "Aprendizaje pausado" : "Learning paused" }
        if isBatteryUseCurrentlyPausedByExternalPower {
            return language == .spanish ? "Alimentación externa activa" : "External power active"
        }
        if let cycleUsageSummary {
            switch cycleUsageSummary.status {
            case .high:
                return language == .spanish ? "Uso de batería alto" : "High battery use"
            case .elevated:
                return language == .spanish ? "Uso de batería elevado" : "Elevated battery use"
            case .onTrack:
                return language == .spanish ? "Uso de batería en ritmo" : "Battery use on track"
            case .insufficientData:
                break
            }
        }
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
        if isBatteryUseCurrentlyPausedByExternalPower {
            return language == .spanish
                ? "Uso acumulado de hoy: la batería está conectada y no hay descarga activa ahora."
                : "Today's accumulated use: the battery is connected and there is no active discharge now."
        }
        if let cycleUsageSummary,
           cycleUsageSummary.status != .insufficientData {
            return cycleUsageDetail(cycleUsageSummary)
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

    private func cycleUsageDetail(_ summary: CycleUsageSummary) -> String {
        let usage = String(format: "%.0f%% (%.2f EFC)", summary.todayUsagePercent, summary.todayEquivalentCycles)
        let rolling = String(format: "%.2f EFC", summary.rolling24HourEquivalentCycles)
        let hardware = "+\(summary.rolling24HourHardwareCycleDelta)"
        let absolutePaceIsElevated = summary.todayEquivalentCycles > 0.20
            || summary.rolling24HourEquivalentCycles > 0.20

        switch summary.status {
        case .high:
            return language == .spanish
                ? "Hoy: \(usage); últimas 24 h: \(rolling), contador medido \(hardware). Ritmo alto de uso, no diagnóstico de daño."
                : "Today: \(usage); last 24h: \(rolling), measured counter \(hardware). High usage pace, not a damage diagnosis."
        case .elevated:
            if absolutePaceIsElevated {
                return language == .spanish
                    ? "Hoy: \(usage); últimas 24 h: \(rolling). Supera el umbral absoluto del 20% de uso equivalente; revisa las apps antes de atribuirlo a desgaste."
                    : "Today: \(usage); last 24h: \(rolling). It is above the absolute 20% equivalent-use threshold; review apps before attributing it to wear."
            }
            return language == .spanish
                ? "Hoy: \(usage); últimas 24 h: \(rolling). El plan configurado está por encima de su presupuesto, aunque el uso absoluto sigue bajo."
                : "Today: \(usage); last 24h: \(rolling). The configured plan is above budget, although absolute use remains low."
        case .onTrack:
            return language == .spanish
                ? "Hoy: \(usage); últimas 24 h: \(rolling), contador medido \(hardware). Dentro del umbral absoluto del 20%; el baseline solo aporta contexto."
                : "Today: \(usage); last 24h: \(rolling), measured counter \(hardware). Within the absolute 20% threshold; the baseline is context only."
        case .insufficientData:
            return language == .spanish
                ? "Aún no hay datos suficientes para clasificar el ritmo de ciclos."
                : "There is not enough data yet to classify cycle pace."
        }
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
        if let cpu = system.cpuUsagePercent, cpu >= 80 {
            return .attention
        }
        if let memory = system.memoryUsedPercent, memory >= 90 {
            return .attention
        }
        if let disk = system.diskUsedPercent, disk >= 95 {
            return .attention
        }
        if isBatteryUseCurrentlyPausedByExternalPower {
            if isChargeLimitActive {
                return .connectedNotCharging
            }
            return .charging
        }
        if cycleUsageSummary?.status == .high {
            return .attention
        }
        if cycleUsageSummary?.status == .elevated {
            return .elevated
        }
        if isChargeLimitActive {
            return .connectedNotCharging
        }
        if battery.externalPowerConnected && (battery.isCharging || isChargingToLimit) {
            return .charging
        }
        if battery.externalPowerConnected {
            return .connectedNotCharging
        }
        return .protected
    }

    var cycleUsageIsPrimaryStatus: Bool {
        guard !isBatteryUseCurrentlyPausedByExternalPower else { return false }
        guard let cycleStatus = cycleUsageSummary?.status,
              cycleStatus == .elevated || cycleStatus == .high else {
            return false
        }
        if system.thermalState == .serious || system.thermalState == .critical {
            return false
        }
        if let temperature = battery.temperatureCelsius, temperature >= temperatureAlertCelsius {
            return false
        }
        if let charge = battery.chargePercent, charge <= criticalChargePercent {
            return false
        }
        if let dischargeRate = effectiveBatteryPercentPerMinute, dischargeRate >= 0.35 {
            return false
        }
        if let cpu = system.cpuUsagePercent, cpu >= 80 {
            return false
        }
        if let memory = system.memoryUsedPercent, memory >= 90 {
            return false
        }
        if let disk = system.diskUsedPercent, disk >= 95 {
            return false
        }
        return true
    }

    var statusTitle: String {
        switch statusKind {
        case .protected:
            return copy(.protected)
        case .charging:
            if let limit = chargeLimitPercent, isChargingToLimit {
                return String(format: copy(.chargingToLimit), limit)
            }
            return copy(.charging)
        case .connectedNotCharging:
            if let limit = chargeLimitPercent, isChargeLimitActive {
                return String(format: copy(.chargeLimitActive), limit)
            }
            return copy(.connectedNotCharging)
        case .elevated:
            return language == .spanish ? "Uso elevado" : "Elevated use"
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
        if let temperature = battery.temperatureCelsius, temperature >= temperatureAlertCelsius {
            return String(format: copy(.temperatureAlert), temperature, temperatureAlertCelsius)
        }
        if let charge = battery.chargePercent, charge <= criticalChargePercent {
            return String(format: copy(.criticalChargeAlert), charge, criticalChargePercent)
        }
        if let cpu = system.cpuUsagePercent, cpu >= 80 {
            return String(format: copy(.cpuAlert), cpu)
        }
        if let memory = system.memoryUsedPercent, memory >= 90 {
            return String(format: copy(.memoryAlert), memory)
        }
        if let disk = system.diskUsedPercent, disk >= 95 {
            return String(format: copy(.diskAlert), disk)
        }
        if !isBatteryUseCurrentlyPausedByExternalPower,
           let cycleUsageSummary, cycleUsageSummary.status == .high {
            return language == .spanish
                ? String(
                    format: "Uso alto: %.2f ciclos equivalentes y +%d ciclos medidos en las últimas 24 h. Esto indica ritmo alto, no daño confirmado.",
                    cycleUsageSummary.rolling24HourEquivalentCycles,
                    cycleUsageSummary.rolling24HourHardwareCycleDelta
                )
                : String(
                    format: "High use: %.2f equivalent cycles and +%d measured cycles in the last 24h. This indicates a high pace, not confirmed damage.",
                    cycleUsageSummary.rolling24HourEquivalentCycles,
                    cycleUsageSummary.rolling24HourHardwareCycleDelta
                )
        }
        if !isBatteryUseCurrentlyPausedByExternalPower,
           let cycleUsageSummary, cycleUsageSummary.status == .elevated {
            return language == .spanish
                ? String(
                    format: "Uso elevado: %.0f%% de una carga completa equivalente hoy. Revisa el ritmo y la proyección semanal.",
                    cycleUsageSummary.todayUsagePercent
                )
                : String(
                    format: "Elevated use: %.0f%% of a full-capacity equivalent today. Review the pace and weekly projection.",
                    cycleUsageSummary.todayUsagePercent
                )
        }
        if battery.externalPowerConnected,
           isChargeLimitActive,
           let limit = chargeLimitPercent {
            return String(format: copy(.chargeLimitActiveExplanation), limit)
        }
        if battery.externalPowerConnected && isChargingToLimit,
           let limit = chargeLimitPercent {
            return String(format: copy(.chargingToLimitExplanation), limit)
        }
        if battery.externalPowerConnected && battery.isCharging {
            return copy(.chargingExplanation)
        }
        if battery.externalPowerConnected {
            return copy(.connectedNotChargingExplanation)
        }
        guard let weatherSnapshot else { return copy(.protectedExplanation) }
        return "\(copy(.protectedExplanation)) \(String(format: copy(.weatherContext), weatherSnapshot.temperatureCelsius, weatherSnapshot.conditionLabel(for: language)))"
    }

    var chargeStateLabel: String {
        if let limit = chargeLimitPercent, isChargeLimitActive {
            return String(format: copy(.chargeLimitActive), limit)
        }
        if battery.isFullyCharged { return copy(.fullyCharged) }
        if let limit = chargeLimitPercent, isChargingToLimit {
            return String(format: copy(.chargingToLimit), limit)
        }
        if battery.isCharging { return copy(.charging) }
        if battery.externalPowerConnected { return copy(.connectedNotCharging) }
        return copy(.discharging)
    }

    var thermalStateLabel: String {
        if system.thermalState == .nominal,
           let cpu = system.cpuUsagePercent,
           cpu >= 80 {
            return language == .spanish ? "Carga alta" : "High load"
        }
        switch (language, system.thermalState) {
        case (.spanish, .nominal): return "Normal"
        case (.spanish, .fair): return "Moderado"
        case (.spanish, .serious): return "Serio"
        case (.spanish, .critical): return "Crítico"
        case (.spanish, .unavailable): return "No disponible"
        case (.english, .nominal): return "Nominal"
        case (.english, .fair): return "Fair"
        case (.english, .serious): return "Serious"
        case (.english, .critical): return "Critical"
        case (.english, .unavailable): return "Unavailable"
        }
    }

    var thermalStateDetail: String {
        switch (language, system.thermalState) {
        case (.spanish, .nominal): return "Sin presión térmica"
        case (.spanish, .fair): return "Presión leve"
        case (.spanish, .serious): return "Presión térmica"
        case (.spanish, .critical): return "Presión crítica"
        case (.spanish, .unavailable): return "Sensor no disponible"
        case (.english, .nominal): return "No thermal pressure"
        case (.english, .fair): return "Light pressure"
        case (.english, .serious): return "Thermal pressure"
        case (.english, .critical): return "Critical pressure"
        case (.english, .unavailable): return "Sensor unavailable"
        }
    }

    var powerModeLabel: String {
        system.lowPowerModeEnabled ? copy(.lowPower) : copy(.automaticPower)
    }

    var powerModeDetail: String {
        if system.lowPowerModeEnabled {
            return language == .spanish
                ? "macOS está limitando el consumo"
                : "macOS is limiting power use"
        }
        return copy(.powerModeUnavailable)
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

    func refreshHistory(includeSupportingData: Bool = true) {
        startHistoryLoad(
            includeSupportingData: includeSupportingData,
            includeRangeSupportingData: includeSupportingData,
            includeAlerts: includeSupportingData
        )
    }

    func refreshHistoryRangeSupportingData() {
        startHistoryLoad(
            includeSupportingData: false,
            includeRangeSupportingData: true,
            includeAlerts: false
        )
    }

    func refreshAlerts() {
        startHistoryLoad(
            includeSupportingData: false,
            includeRangeSupportingData: false,
            includeAlerts: true
        )
    }

    private func startHistoryLoad(
        includeSupportingData: Bool,
        includeRangeSupportingData: Bool,
        includeAlerts: Bool
    ) {
        historyLoadTask?.cancel()
        let requestID = UUID()
        historyRequestID = requestID
        let requestedRange = historyRange
        lastHistoryRefresh = Date()
        isRefreshingHistory = true
        historyLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadHistory(
                for: requestedRange,
                requestID: requestID,
                includeSupportingData: includeSupportingData,
                includeRangeSupportingData: includeRangeSupportingData,
                includeAlerts: includeAlerts
            )
            guard self.historyRequestID == requestID else { return }
            self.historyLoadTask = nil
        }
    }

    private func loadHistory() async {
        await loadHistory(
            for: historyRange,
            requestID: nil,
            includeSupportingData: true,
            includeRangeSupportingData: true,
            includeAlerts: true
        )
    }

    private func loadHistory(
        for requestedRange: HistoryRange,
        requestID: UUID?,
        includeSupportingData: Bool,
        includeRangeSupportingData: Bool,
        includeAlerts: Bool
    ) async {
        isRefreshingHistory = true
        defer {
            if requestID == nil || historyRequestID == requestID {
                isRefreshingHistory = false
            }
        }

        func isCurrentRequest() -> Bool {
            !Task.isCancelled && (requestID == nil || historyRequestID == requestID)
        }

        if includeSupportingData {
            samplingMode = await coordinator.currentMode()
            pendingSampleCount = await coordinator.pendingSampleCount()
            pendingSessionCount = await coordinator.pendingSessionCount()
        }
        guard isCurrentRequest() else { return }

        guard let store else {
            if includeSupportingData {
                recentSamples = []
                recentSessions = []
                processHistorySamples = []
                hourlyAggregates = []
                 learningAggregates = []
                 learningHourlyAggregates = []
                 cycleUsageQuarterHourBuckets = []
                 cycleUsageDailyBuckets = []
                 cycleUsageSummary = nil
                 processImpacts = []

                storeDiagnostics = nil
                storedSampleCount = 0
                learningDaysObserved = 0
                learningFirstDate = nil
                learningLastDate = nil
            } else if includeRangeSupportingData {
                hourlyAggregates = []
                processHistorySamples = []
            }
            if includeAlerts {
                alertEvents = []
                intelligenceAnalysisLogs = []
            }
            historyAggregates = []
            storeError = "Local storage is unavailable."
            return
        }

        do {
            if includeSupportingData {
                try? await coordinator.flush()
                _ = try? await store.applyRetentionIfNeeded()
                try await refreshCycleBudget(from: store, now: Date())
                guard isCurrentRequest() else { return }
            } else if includeRangeSupportingData {
                try? await coordinator.flush()
                guard isCurrentRequest() else { return }
            }

            let aggregateSamples = try await store.fetchAggregates(
                resolution: requestedRange.resolution,
                since: requestedRange.since,
                limit: requestedRange.aggregateFetchLimit
            )
            guard isCurrentRequest() else { return }
            let nextHistoryAggregates = downsample(
                Array(aggregateSamples.reversed()),
                maxCount: requestedRange.displayPointLimit
            )
            if historyAggregates != nextHistoryAggregates {
                historyAggregates = nextHistoryAggregates
            }
            storeError = nil

            if includeRangeSupportingData {
                let computerUseWindow = makeComputerUseWindow(
                    for: requestedRange,
                    endingOn: computerUseDate
                )
                let computerUseSamples = try await store.fetchAggregates(
                    resolution: computerUseWindow.resolution,
                    since: computerUseWindow.start,
                    until: computerUseWindow.end,
                    limit: computerUseWindow.limit
                )
                guard isCurrentRequest() else { return }
                let nextHourlyAggregates = Array(computerUseSamples.reversed())
                if hourlyAggregates != nextHourlyAggregates {
                    hourlyAggregates = nextHourlyAggregates
                }

                let nextProcessHistorySamples = try await store.fetchProcessSamples(
                    since: requestedRange.since ?? Date().addingTimeInterval(-7 * 86_400),
                    limit: min(2_000, max(240, requestedRange.aggregateFetchLimit * 4))
                )
                guard isCurrentRequest() else { return }
                if processHistorySamples != nextProcessHistorySamples {
                    processHistorySamples = nextProcessHistorySamples
                }
            }

            if includeSupportingData {
                let sessionSince = Date().addingTimeInterval(-24 * 60 * 60)
                let learnedSamples = try await store.fetchAggregates(
                    resolution: .day,
                    since: Date().addingTimeInterval(-7 * 86_400),
                    limit: 7
                )
                guard isCurrentRequest() else { return }
                let learningHourlySamples = try await store.fetchAggregates(
                    resolution: .minute,
                    since: Date().addingTimeInterval(-7 * 86_400),
                    limit: 10_000
                )
                guard isCurrentRequest() else { return }
                let evidence = try await store.sampleEvidence()
                guard isCurrentRequest() else { return }
                storedSampleCount = evidence.sampleCount
                learningDaysObserved = evidence.observedDays
                learningFirstDate = evidence.firstSampleDate
                learningLastDate = evidence.lastSampleDate

                let nextLearningAggregates = Array(learnedSamples.reversed())
                let nextLearningHourlyAggregates = Array(learningHourlySamples.reversed())
                if learningAggregates != nextLearningAggregates {
                    learningAggregates = nextLearningAggregates
                }
                if learningHourlyAggregates != nextLearningHourlyAggregates {
                    learningHourlyAggregates = nextLearningHourlyAggregates
                }

                let nextRecentSamples = try await store.fetchBatterySamples(
                    since: Date().addingTimeInterval(-30 * 60),
                    limit: 60
                )
                guard isCurrentRequest() else { return }
                let nextRecentSessions = try await store.fetchSessions(since: sessionSince, limit: 5)
                guard isCurrentRequest() else { return }
                if recentSamples != nextRecentSamples {
                    recentSamples = nextRecentSamples
                }
                if recentSessions != nextRecentSessions {
                    recentSessions = nextRecentSessions
                }
            }

            if includeAlerts {
                let nextAlertEvents = try await store.fetchAlertEvents(
                    since: Date().addingTimeInterval(-30 * 86_400),
                    limit: 100
                )
                guard isCurrentRequest() else { return }
                let fetchedIntelligenceAnalysisLogs = try await store.fetchIntelligenceAnalyses(
                    since: Date().addingTimeInterval(-365 * 86_400),
                    limit: 200
                )
                guard isCurrentRequest() else { return }
                let nextIntelligenceAnalysisLogs = recoverInterruptedIntelligenceAnalyses(
                    fetchedIntelligenceAnalysisLogs
                )
                if lastAutomaticIntelligenceAnalysis == nil,
                   let latestAnalysis = nextIntelligenceAnalysisLogs.first(where: { $0.kind == .analysis }) {
                    lastAutomaticIntelligenceAnalysis = latestAnalysis.requestedAt
                    defaults.set(latestAnalysis.requestedAt, forKey: "cellium.intelligence.lastAnalysis")
                }
                if alertEvents != nextAlertEvents {
                    alertEvents = nextAlertEvents
                }
                if intelligenceAnalysisLogs != nextIntelligenceAnalysisLogs {
                    intelligenceAnalysisLogs = nextIntelligenceAnalysisLogs
                }
                restoreLatestIntelligenceInsight(from: nextIntelligenceAnalysisLogs)
            }

            if includeSupportingData {
                let nextDiagnostics = try await store.diagnostics()
                guard isCurrentRequest() else { return }
                if storeDiagnostics != nextDiagnostics {
                    storeDiagnostics = nextDiagnostics
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentRequest() else { return }
            if includeSupportingData {
                recentSamples = []
                recentSessions = []
                processHistorySamples = []
                hourlyAggregates = []
                 learningAggregates = []
                 learningHourlyAggregates = []
                 cycleUsageQuarterHourBuckets = []
                 cycleUsageDailyBuckets = []
                 cycleUsageSummary = nil
                 processImpacts = []

                storeDiagnostics = nil
                storedSampleCount = 0
                learningDaysObserved = 0
                learningFirstDate = nil
                learningLastDate = nil
            } else if includeRangeSupportingData {
                hourlyAggregates = []
                processHistorySamples = []
            }
            if includeAlerts {
                alertEvents = []
                intelligenceAnalysisLogs = []
            }
            historyAggregates = []
            if let storeError = error as? StoreError {
                self.storeError = storeError.userMessage
            } else {
                self.storeError = String(describing: error)
            }
        }
    }

    private func refreshCycleBudget(from store: SQLiteStore, now: Date) async throws {
        let snapshot = try await cycleBudgetCoordinator.load(
            from: store,
            currentCycleCount: battery.cycleCount,
            configuration: cyclePlanConfiguration,
            now: now
        )
        if cycleUsageQuarterHourBuckets != snapshot.quarterHourBuckets {
            cycleUsageQuarterHourBuckets = snapshot.quarterHourBuckets
        }
        if cycleUsageDailyBuckets != snapshot.dailyBuckets {
            cycleUsageDailyBuckets = snapshot.dailyBuckets
        }
        if cycleUsageSummary != snapshot.summary {
            cycleUsageSummary = snapshot.summary
        }
    }

    private func downsample(
        _ aggregates: [BatteryAggregate],
        maxCount: Int
    ) -> [BatteryAggregate] {
        guard maxCount > 1, aggregates.count > maxCount else { return aggregates }
        let lastIndex = aggregates.count - 1
        let denominator = Double(maxCount - 1)
        return (0..<maxCount).map { index in
            let position = Double(index) / denominator * Double(lastIndex)
            return aggregates[Int(position.rounded())]
        }
     }

     private func makeComputerUseWindow(
         for range: HistoryRange,
         endingOn date: Date
     ) -> (
         start: Date,
         end: Date,
         resolution: BatteryAggregateResolution,
         limit: Int
     ) {
         let calendar = Calendar.autoupdatingCurrent
         let dayStart = calendar.startOfDay(for: date)
         let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
             ?? dayStart.addingTimeInterval(86_400)

         guard range.resolution != .day,
               let duration = range.duration else {
             return (dayStart, dayEnd, .minute, 1_500)
         }

         let start = calendar.date(
             byAdding: .second,
             value: -Int(duration),
             to: dayEnd
         ) ?? dayEnd.addingTimeInterval(-duration)
         return (start, dayEnd, range.resolution, range.aggregateFetchLimit)
     }

      func setHistoryRange(_ range: HistoryRange) {

          guard historyRange != range else { return }
          historyRange = range
          hourlyAggregates = []
          defaults.set(range.rawValue, forKey: "cellium.historyRange")

          if panelVisible {
              refreshHistoryRangeSupportingData()
          }
     }

      var isComputerUseToday: Bool {
          Calendar.autoupdatingCurrent.isDateInToday(computerUseDate)
      }

      var computerUseDisplayWindow: (start: Date, end: Date) {
          let window = makeComputerUseWindow(
              for: historyRange,
              endingOn: computerUseDate
          )
          return (window.start, window.end)
      }

      func setComputerUseDate(_ date: Date) {

         let calendar = Calendar.autoupdatingCurrent
         let normalizedDate = calendar.startOfDay(for: date)
         let today = calendar.startOfDay(for: Date())
         guard normalizedDate <= today, normalizedDate != computerUseDate else { return }

         computerUseDate = normalizedDate
          hourlyAggregates = []
          if panelVisible {
              refreshHistoryRangeSupportingData()
          }
     }

     func moveComputerUseDate(by days: Int) {
         guard days != 0,
               let date = Calendar.autoupdatingCurrent.date(
                   byAdding: .day,
                   value: days,
                   to: computerUseDate
               ) else {
             return
         }
         setComputerUseDate(date)
     }

     func setHistoryMetric(_ metric: DashboardHistoryMetric) {

        historyMetric = metric
    }

    func setShowingSettings(_ showing: Bool) {
        showingSettings = showing
        if showing {
            showingAgent = false
        }
    }

    func setShowingAgent(_ showing: Bool) {
        showingAgent = showing
        guard showing else { return }
        showingSettings = false
        refreshLocalIntelligenceInsight()
    }

    func createAgentSession() {
        persistIntelligenceMessages()
        activeIntelligenceSessionID = nil
        intelligenceMessages = []
        intelligenceError = nil
    }

    private func ensureActiveAgentSession() {
        guard activeIntelligenceSessionID == nil else { return }
        let title = language == .spanish ? "Nuevo chat" : "New chat"
        let session = CelliumAgentSession(title: title)
        intelligenceSessions.insert(session, at: 0)
        activeIntelligenceSessionID = session.id
    }

    func selectAgentSession(_ sessionID: UUID) {
        guard sessionID != activeIntelligenceSessionID,
              let session = intelligenceSessions.first(where: { $0.id == sessionID }) else {
            return
        }
        persistIntelligenceMessages()
        activeIntelligenceSessionID = session.id
        intelligenceMessages = session.messages
        intelligenceError = nil
    }

    func deleteAgentSession(_ sessionID: UUID) {
        guard let index = intelligenceSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let wasActive = activeIntelligenceSessionID == sessionID
        intelligenceSessions.remove(at: index)

        if wasActive {
            if let replacement = intelligenceSessions.first {
                activeIntelligenceSessionID = replacement.id
                intelligenceMessages = replacement.messages
            } else {
                activeIntelligenceSessionID = nil
                intelligenceMessages = []
            }
            intelligenceError = nil
        }
        persistIntelligenceSessions()
    }

    func setIntelligenceEnabled(_ enabled: Bool) {
        intelligenceConfiguration.enabled = enabled
        defaults.set(enabled, forKey: "cellium.intelligence.enabled")
        intelligenceError = nil
        intelligenceValidationMessage = nil
        refreshLocalIntelligenceInsight()
        if enabled {
            refreshIntelligenceAPIKeyState()
        } else {
            intelligenceInsight = localIntelligenceInsight
        }
    }

    func setIntelligenceProvider(_ provider: IntelligenceProvider) {
        intelligenceConfiguration.provider = provider
        defaults.set(provider.rawValue, forKey: "cellium.intelligence.provider")
        intelligenceValidationMessage = nil
        refreshIntelligenceAPIKeyState()
    }

    func setIntelligenceModel(_ model: String) {
        intelligenceConfiguration.model = model
        defaults.set(model, forKey: "cellium.intelligence.model")
        intelligenceValidationMessage = nil
    }

    func setIntelligenceAutomaticAnalysisEnabled(_ enabled: Bool) {
        intelligenceConfiguration.automaticAnalysisEnabled = enabled
        defaults.set(enabled, forKey: "cellium.intelligence.automatic")
        if !enabled {
            lastAutomaticIntelligenceAnalysis = nil
            defaults.removeObject(forKey: "cellium.intelligence.lastAnalysis")
        }
    }

    func setOllamaEndpoint(_ endpoint: String) {
        intelligenceConfiguration.ollamaEndpoint = endpoint
        defaults.set(endpoint, forKey: "cellium.intelligence.ollamaEndpoint")
        intelligenceValidationMessage = nil
    }

    func unlockIntelligenceSecrets() {
        let provider = intelligenceConfiguration.provider
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                intelligenceAPIKeyConfigured = try await intelligenceService.unlockAPIKey(
                    for: provider
                )
                intelligenceError = intelligenceAPIKeyConfigured
                    ? nil
                    : (language == .spanish ? "No hay una API key cifrada para desbloquear." : "No encrypted API key is available to unlock.")
                intelligenceValidationMessage = nil
            } catch {
                intelligenceAPIKeyConfigured = false
                intelligenceError = intelligenceErrorMessage(error)
            }
        }
    }

    func saveIntelligenceAPIKey(_ value: String) {
        let provider = intelligenceConfiguration.provider
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await intelligenceService.saveAPIKey(value, for: provider)
                intelligenceAPIKeyConfigured = await intelligenceService.hasAPIKey(for: provider)
                intelligenceError = nil
                intelligenceValidationMessage = nil
            } catch {
                intelligenceError = intelligenceErrorMessage(error)
            }
        }
    }

    func clearIntelligenceAPIKey() {
        let provider = intelligenceConfiguration.provider
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await intelligenceService.deleteAPIKey(for: provider)
                intelligenceAPIKeyConfigured = false
                intelligenceError = nil
                intelligenceValidationMessage = nil
            } catch {
                intelligenceError = intelligenceErrorMessage(error)
            }
        }
    }

    func clearAlerts() {
        alertEvents = []
        proactiveAlert = nil
        lastProactiveAlertKey = nil
        lastProactiveAlertDate = nil
        Task {
            try? await store?.clearAlertEvents()
        }
    }

    func clearIntelligenceAnalysisLog() {
        intelligenceAnalysisLogs = []
        Task {
            try? await store?.clearIntelligenceAnalyses()
        }
    }

     func requestIntelligenceAnalysis() {
         refreshLocalIntelligenceInsight()
         wifiAvailable = wifiMonitor.isWiFiAvailable
         guard wifiAvailable else {
             intelligenceError = nil
             return
         }
         guard isIntelligenceReady else {

            intelligenceError = language == .spanish
                ? (intelligenceConfiguration.enabled
                    ? "Configura un proveedor antes de solicitar un análisis."
                    : "Activa y configura el agente para solicitar un análisis.")
                : (intelligenceConfiguration.enabled
                    ? "Configure a provider before requesting an analysis."
                    : "Enable and configure the agent before requesting an analysis.")
            return
        }
        guard !isGeneratingIntelligence else { return }

        let configuration = intelligenceConfiguration
        let evidence = makeIntelligenceEvidence()
        let languageCode = language.rawValue
        let runID = UUID()
        let requestedAt = Date()
        lastAutomaticIntelligenceAnalysis = requestedAt
        defaults.set(requestedAt, forKey: "cellium.intelligence.lastAnalysis")
        activeIntelligenceRunID = runID
        let runningLog = StoredIntelligenceAnalysis(
            id: runID,
            requestedAt: requestedAt,
            kind: .analysis,
            provider: configuration.provider.rawValue,
            model: configuration.model,
            languageCode: languageCode,
            prompt: language == .spanish ? "Preparando el prompt…" : "Preparing prompt…",
            status: .running
        )
        upsertIntelligenceAnalysis(runningLog)
         persistIntelligenceAnalysis(runningLog, updating: false)
         isGeneratingAnalysis = true
         isGeneratingIntelligence = true
         intelligenceError = nil
        Task { @MainActor [weak self] in
             guard let self else { return }
             defer {
                 isGeneratingAnalysis = false
                 isGeneratingIntelligence = false
                 if activeIntelligenceRunID == runID {
                    activeIntelligenceRunID = nil
                }
            }
            do {
                let result = try await intelligenceService.generateAnalysis(
                    from: evidence,
                    configuration: configuration,
                    languageCode: languageCode
                )
                intelligenceInsight = result.insight
                let completedLog = StoredIntelligenceAnalysis(
                    id: runID,
                    requestedAt: requestedAt,
                    completedAt: Date(),
                    kind: .analysis,
                    provider: configuration.provider.rawValue,
                    model: configuration.model,
                    languageCode: languageCode,
                    prompt: result.prompt,
                    response: result.response,
                    status: .succeeded,
                    title: result.insight.title,
                    severity: result.insight.severity.rawValue,
                    confidence: result.insight.confidence.rawValue,
                    evidence: result.insight.evidence,
                    recommendations: result.insight.recommendations
                )
                 upsertIntelligenceAnalysis(completedLog)
                 persistIntelligenceAnalysis(completedLog, updating: true)
                 publishIntelligenceActionIfNeeded(result)
                 intelligenceError = nil
             } catch {

                let message = intelligenceErrorMessage(error)
                let failedLog = StoredIntelligenceAnalysis(
                    id: runID,
                    requestedAt: requestedAt,
                    completedAt: Date(),
                    kind: .analysis,
                    provider: configuration.provider.rawValue,
                    model: configuration.model,
                    languageCode: languageCode,
                    prompt: language == .spanish
                        ? "La solicitud se inició, pero no se obtuvo el prompt final antes del fallo."
                        : "The request started, but the final prompt was unavailable before the failure.",
                    status: .failed,
                    errorMessage: message
                )
                upsertIntelligenceAnalysis(failedLog)
                persistIntelligenceAnalysis(failedLog, updating: true)
                intelligenceError = message
                intelligenceInsight = localIntelligenceInsight
            }
        }
    }

     func sendAgentMessage(_ text: String) {
         let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !trimmedText.isEmpty else { return }
         wifiAvailable = wifiMonitor.isWiFiAvailable
         guard wifiAvailable else {
             intelligenceError = language == .spanish
                 ? "No se pudo enviar el mensaje porque no hay Wi-Fi."
                 : "The message could not be sent because Wi-Fi is unavailable."
             return
         }
         guard isIntelligenceReady else {

            intelligenceError = language == .spanish
                ? (intelligenceConfiguration.enabled
                    ? "Configura un proveedor antes de chatear."
                    : "Activa y configura el agente en Configuración para chatear.")
                : (intelligenceConfiguration.enabled
                    ? "Configure a provider before chatting."
                    : "Enable and configure the agent in Settings to chat.")
            return
        }
        guard !isGeneratingIntelligence else { return }

        ensureActiveAgentSession()
        let configuration = intelligenceConfiguration
         let evidence = makeIntelligenceEvidence()
         let languageCode = language.rawValue
         let history = Array(intelligenceMessages.suffix(10))
         let runID = UUID()

        let requestedAt = Date()
        activeIntelligenceRunID = runID
        let runningLog = StoredIntelligenceAnalysis(
            id: runID,
            requestedAt: requestedAt,
            kind: .chat,
            provider: configuration.provider.rawValue,
            model: configuration.model,
            languageCode: languageCode,
            prompt: trimmedText,
            status: .running
        )
        upsertIntelligenceAnalysis(runningLog)
        persistIntelligenceAnalysis(runningLog, updating: false)
        intelligenceMessages.append(
            AgentChatMessage(role: .user, content: trimmedText)
        )
        persistIntelligenceMessages()
        isGeneratingIntelligence = true
        intelligenceError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                isGeneratingIntelligence = false
                if activeIntelligenceRunID == runID {
                    activeIntelligenceRunID = nil
                }
            }
            do {
                let result = try await intelligenceService.chatAnalysis(
                    message: trimmedText,
                    history: history,
                    evidence: evidence,
                    configuration: configuration,
                    languageCode: languageCode
                )
                intelligenceMessages.append(
                    AgentChatMessage(role: .assistant, content: result.response)
                )
                persistIntelligenceMessages()
                let completedLog = StoredIntelligenceAnalysis(
                    id: runID,
                    requestedAt: requestedAt,
                    completedAt: Date(),
                    kind: .chat,
                    provider: configuration.provider.rawValue,
                    model: configuration.model,
                    languageCode: result.languageCode,
                    prompt: result.prompt,
                    response: result.response,
                    status: .succeeded
                )
                upsertIntelligenceAnalysis(completedLog)
                persistIntelligenceAnalysis(completedLog, updating: true)
            } catch {
                let message = intelligenceErrorMessage(error)
                let failedLog = StoredIntelligenceAnalysis(
                    id: runID,
                    requestedAt: requestedAt,
                    completedAt: Date(),
                    kind: .chat,
                    provider: configuration.provider.rawValue,
                    model: configuration.model,
                    languageCode: languageCode,
                    prompt: trimmedText,
                    status: .failed,
                    errorMessage: message
                )
                upsertIntelligenceAnalysis(failedLog)
                persistIntelligenceAnalysis(failedLog, updating: true)
                intelligenceError = message
            }
        }
    }

     func clearAgentHistory() {
         intelligenceMessages = []
         intelligenceError = nil
         persistIntelligenceMessages()
     }


     func validateIntelligenceProvider() {
         guard !isValidatingIntelligenceProvider else { return }
         wifiAvailable = wifiMonitor.isWiFiAvailable
         guard wifiAvailable else {
             intelligenceValidationMessage = copy(.wifiUnavailable)
             return
         }
         let configuration = intelligenceConfiguration

        isValidatingIntelligenceProvider = true
        intelligenceValidationMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isValidatingIntelligenceProvider = false }
            do {
                try await intelligenceService.validateProvider(configuration)
                intelligenceValidationMessage = language == .spanish ? "Proveedor disponible" : "Provider available"
            } catch {
                intelligenceValidationMessage = intelligenceErrorMessage(error)
            }
        }
    }

    private func upsertIntelligenceAnalysis(_ analysis: StoredIntelligenceAnalysis) {
        if let index = intelligenceAnalysisLogs.firstIndex(where: { $0.id == analysis.id }) {
            intelligenceAnalysisLogs[index] = analysis
        } else {
            intelligenceAnalysisLogs.insert(analysis, at: 0)
        }
        intelligenceAnalysisLogs.sort { $0.requestedAt > $1.requestedAt }
    }

    private func recoverInterruptedIntelligenceAnalyses(
        _ logs: [StoredIntelligenceAnalysis]
    ) -> [StoredIntelligenceAnalysis] {
        let recoveredAt = Date()
        return logs.map { log in
            guard log.status == .running, log.id != activeIntelligenceRunID else {
                return log
            }

            let message = language == .spanish
                ? "La aplicación no terminó esta solicitud; se marcó como fallida para evitar un estado atascado."
                : "The app did not finish this request; it was marked failed to avoid a stuck state."
            let recovered = StoredIntelligenceAnalysis(
                id: log.id,
                requestedAt: log.requestedAt,
                completedAt: recoveredAt,
                kind: log.kind,
                provider: log.provider,
                model: log.model,
                languageCode: log.languageCode,
                prompt: log.prompt,
                response: log.response,
                status: .failed,
                errorMessage: message,
                title: log.title,
                severity: log.severity,
                confidence: log.confidence,
                evidence: log.evidence,
                recommendations: log.recommendations
            )
            persistIntelligenceAnalysis(recovered, updating: true)
            return recovered
        }
    }

     private func persistIntelligenceAnalysis(
         _ analysis: StoredIntelligenceAnalysis,
         updating: Bool
     ) {
         guard let store else { return }
         Task {
             do {
                 if updating {
                     try await store.updateIntelligenceAnalysis(analysis)
                 } else {
                     _ = try await store.appendIntelligenceAnalysis(analysis)
                 }
             } catch {
                 // The in-memory log remains visible even if local persistence is unavailable.
             }
         }
     }

     private func publishIntelligenceActionIfNeeded(_ result: IntelligenceAnalysisResult) {
         guard result.actionRequired,
                let action = result.actionMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                !action.isEmpty,
                learningDaysObserved >= 7 || cycleUsageSummary?.isActionableHighPace == true,
                wifiAvailable else {
             return
         }

         let actionKey = action.lowercased()
         let now = Date()
         if actionKey == lastIntelligenceActionNotificationKey,
            let lastDate = lastIntelligenceActionNotificationDate,
            now.timeIntervalSince(lastDate) < 24 * 60 * 60 {
             return
         }

         lastIntelligenceActionNotificationKey = actionKey
         lastIntelligenceActionNotificationDate = now
         defaults.set(actionKey, forKey: "cellium.intelligence.lastActionNotificationKey")
         defaults.set(now, forKey: "cellium.intelligence.lastActionNotificationDate")

         var measurements = ["learningDays": Double(learningDaysObserved)]
         if let averagePower = learningAveragePowerWatts {
             measurements["averagePowerWatts"] = averagePower
         }
         let alert = ProactiveAlert(
             identifier: "intelligence-learning-action",
             title: copy(.alertLearningActionTitle),
             body: action,
             severity: .warning,
             measurements: measurements
         )
         proactiveAlert = alert
         lastProactiveAlertKey = alert.identifier
         lastProactiveAlertDate = now
         persistAlertEvent(alert, occurredAt: now)
         onProactiveAlert?(alert)
     }

     private func intelligenceErrorMessage(_ error: Error) -> String {

        if let urlError = error as? URLError, urlError.code == .timedOut {
            return language == .spanish
                ? "El proveedor no respondió a tiempo. El análisis se detuvo y quedó registrado."
                : "The provider did not respond in time. The analysis stopped and was logged."
        }
        guard language == .spanish else { return error.localizedDescription }
        guard let intelligenceError = error as? IntelligenceError else {
            return error.localizedDescription
        }
        switch intelligenceError {
        case .missingAPIKey:
            return "No hay una API key de OpenRouter configurada."
        case .invalidEndpoint:
            return "La dirección de Ollama no es válida."
        case .emptyPrompt:
            return "El mensaje no puede estar vacío."
        case .emptyResponse:
            return "El proveedor devolvió una respuesta vacía."
        case .invalidResponse:
            return "El proveedor devolvió una respuesta no válida."
        case let .httpStatus(status):
            return "El proveedor de IA respondió con el estado HTTP \(status)."
        case .secretPassphraseRequired:
            return "No se pudo crear la clave local segura para la API key."
        case .secretPassphraseInvalid:
            return "La API key cifrada no se puede desbloquear en esta instalación."
        case .secretStore:
            return "No se pudo abrir el archivo cifrado de credenciales."
        case .timedOut:
            return "El proveedor no respondió a tiempo. El análisis se detuvo y quedó registrado."
        }
    }

    private func refreshIntelligenceAPIKeyState() {
        let provider = intelligenceConfiguration.provider
        Task { @MainActor [weak self] in
            guard let self else { return }
            intelligenceAPIKeyConfigured = await intelligenceService.hasAPIKey(for: provider)
        }
    }

    private func refreshLocalIntelligenceInsight() {
        let insight = BatteryInsightEngine.makeInsight(
            from: makeIntelligenceEvidence(),
            languageCode: language.rawValue
        )
        localIntelligenceInsight = insight
        let deterministicCycleSignal = cycleUsageSummary?.status == .elevated
            || cycleUsageSummary?.status == .high
        if deterministicCycleSignal
            || !intelligenceConfiguration.enabled
            || intelligenceInsight?.provider == nil {
            intelligenceInsight = insight
        }
    }

    private func restoreLatestIntelligenceInsight(from logs: [StoredIntelligenceAnalysis]) {
        if cycleUsageSummary?.status == .elevated || cycleUsageSummary?.status == .high {
            refreshLocalIntelligenceInsight()
            return
        }
        guard let latest = logs.first(where: {
            $0.kind == .analysis &&
                $0.status == .succeeded &&
                $0.languageCode.lowercased().hasPrefix(language.rawValue)
        }),
        let title = latest.title,
        let severity = latest.severity.flatMap(BatteryInsightSeverity.init(rawValue:)),
        let confidence = latest.confidence.flatMap(Confidence.init(rawValue:)),
        let provider = IntelligenceProvider(rawValue: latest.provider),
        let response = latest.response else {
            return
        }

        intelligenceInsight = BatteryInsight(
            generatedAt: latest.completedAt ?? latest.requestedAt,
            title: title,
            summary: response,
            severity: severity,
            confidence: confidence,
            evidence: latest.evidence,
            recommendations: latest.recommendations,
            provider: provider
        )
    }

    private func startIntelligenceMonitoring() {
        intelligenceTask?.cancel()
        refreshIntelligenceAPIKeyState()
        intelligenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                wifiAvailable = wifiMonitor.isWiFiAvailable
                let lastAnalysisAt = lastAutomaticIntelligenceAnalysis
                    ?? intelligenceAnalysisLogs.first(where: { $0.kind == .analysis })?.requestedAt
                if isIntelligenceReady,
                    intelligenceConfiguration.automaticAnalysisEnabled,
                    wifiAvailable,
                    !isGeneratingIntelligence,
                    (lastAnalysisAt == nil || Date().timeIntervalSince(lastAnalysisAt ?? .distantPast) >= 3_600) {
                    requestIntelligenceAnalysis()
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func makeIntelligenceEvidence() -> BatteryEvidenceSnapshot {
        let capturedAt = Date()
        let recentHistory = recentSamples.prefix(60).map { sample in
            BatteryEvidencePoint(
                timestamp: sample.battery.timestamp,
                chargePercent: sample.battery.chargePercent,
                powerWatts: powerWatts(for: sample.battery),
                temperatureCelsius: sample.battery.temperatureCelsius
            )
        }
        let processEvidence = processImpacts.prefix(6).enumerated().map { index, impact in
            ProcessEvidence(
                name: "\(impact.kind.rawValue)-\(index + 1)",
                kind: impact.kind.rawValue,
                cpuPercent: impact.averageCPUPercent,
                memoryPercent: impact.memoryPercent,
                estimatedBatteryPercentPerMinute: impact.estimatedBatteryPercentPerMinute
            )
        }
        return BatteryEvidenceSnapshot(
             capturedAt: capturedAt,
            chargePercent: battery.chargePercent,
            isCharging: battery.isCharging,
            externalPowerConnected: battery.externalPowerConnected,
            powerWatts: batteryPowerWatts,
            dischargePercentPerMinute: effectiveBatteryPercentPerMinute,
            temperatureCelsius: battery.temperatureCelsius,
            healthPercent: healthPercent,
            cycleCount: battery.cycleCount,
            designCycleCount: battery.designCycleCount,
            thermalState: system.thermalState,
            lowPowerModeEnabled: system.lowPowerModeEnabled,
            cpuUsagePercent: system.cpuUsagePercent,
             memoryUsedPercent: system.memoryUsedPercent,
             diskUsedPercent: system.diskUsedPercent,
             learningDaysObserved: learningDaysObserved,
             recentHistory: recentHistory,
             processImpacts: processEvidence,
             context: makeIntelligenceContext(at: capturedAt),
             cycleUsage: cycleUsageSummary,
             chargeLimitPercent: chargeLimitPercent,
             isChargeLimitActive: isChargeLimitActive,
             batteryUsePausedByExternalPower: isBatteryUseCurrentlyPausedByExternalPower
           )
      }

      private func makeIntelligenceContext(at capturedAt: Date) -> IntelligenceContext {
          let (timeZone, timeZoneSource) = intelligenceTimeZone()
          let device = IntelligenceDeviceContext(
              modelIdentifier: macModelIdentifier(),
              operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
              architecture: machineArchitecture(),
              appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          )
          let weather = weatherSnapshot.map {
              IntelligenceWeatherContext(
                  locationLabel: $0.locationLabel,
                  timezoneIdentifier: $0.timezoneIdentifier,
                  condition: $0.conditionLabel(for: language),
                 temperatureCelsius: $0.temperatureCelsius,
                 apparentTemperatureCelsius: $0.apparentTemperatureCelsius,
                 relativeHumidityPercent: $0.relativeHumidity,
                 windSpeedKmh: $0.windSpeedKmh
             )
         }
         let weeklyAggregates = Array(learningAggregates.suffix(7))
         let weeklyDays = weeklyAggregates.map {
             IntelligenceLearningDay(
                 date: $0.bucketStart,
                 sampleCount: $0.sampleCount,
                 averageChargePercent: $0.averageChargePercent,
                 averageBatteryPowerWatts: $0.averageBatteryPowerWatts,
                 averageTemperatureCelsius: $0.averageTemperatureCelsius,
                 averageCPUUsagePercent: $0.averageCPUUsagePercent,
                 averageMemoryUsedPercent: $0.averageMemoryUsedPercent
             )
         }
         let weeklyLearning = IntelligenceLearningContext(
             windowDays: 7,
             observedDays: min(7, learningDaysObserved),
             sampleCount: weeklyAggregates.reduce(0) { $0 + $1.sampleCount },
             firstSampleDate: weeklyAggregates.first?.bucketStart ?? learningFirstDate,
             lastSampleDate: weeklyAggregates.last?.bucketStart ?? learningLastDate,
             averageBatteryPowerWatts: average(weeklyAggregates.compactMap(\.averageBatteryPowerWatts)),
             averageChargePercent: average(weeklyAggregates.compactMap(\.averageChargePercent)),
             averageTemperatureCelsius: average(weeklyAggregates.compactMap(\.averageTemperatureCelsius)),
             averageCPUUsagePercent: average(weeklyAggregates.compactMap(\.averageCPUUsagePercent)),
             averageMemoryUsedPercent: average(weeklyAggregates.compactMap(\.averageMemoryUsedPercent)),
              days: weeklyDays
          )
          return IntelligenceContext(
              device: device,
              weather: weather,
              weeklyLearning: weeklyLearning,
              time: makeIntelligenceTimeContext(
                  at: capturedAt,
                  timeZone: timeZone,
                  source: timeZoneSource
              ),
              usage: makeIntelligenceUsageContext(timeZone: timeZone)
          )
      }

      private func intelligenceTimeZone() -> (timeZone: TimeZone, source: String) {
          if let identifier = weatherSnapshot?.timezoneIdentifier,
             let timeZone = TimeZone(identifier: identifier) {
              return (timeZone, "weather-location")
          }
          return (.autoupdatingCurrent, "macOS")
      }

      private func makeIntelligenceTimeContext(
          at date: Date,
          timeZone: TimeZone,
          source: String
      ) -> IntelligenceTimeContext {
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = timeZone
          let formatter = DateFormatter()
          formatter.calendar = calendar
          formatter.locale = Locale(identifier: "en_US_POSIX")
          formatter.timeZone = timeZone
          formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
          return IntelligenceTimeContext(
              localDateTime: formatter.string(from: date),
              timeZoneIdentifier: timeZone.identifier,
              utcOffsetMinutes: timeZone.secondsFromGMT(for: date) / 60,
              localHour: calendar.component(.hour, from: date),
              dayOfWeek: calendar.component(.weekday, from: date),
              isDaylightSavingTime: timeZone.isDaylightSavingTime(for: date),
              source: source
          )
      }

      private func makeIntelligenceUsageContext(timeZone: TimeZone) -> IntelligenceUsageContext? {
          guard !learningHourlyAggregates.isEmpty else { return nil }
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = timeZone
          let grouped = Dictionary(grouping: learningHourlyAggregates) { aggregate in
              IntelligenceUsageBucketKey(
                  day: calendar.startOfDay(for: aggregate.bucketStart),
                  hour: calendar.component(.hour, from: aggregate.bucketStart)
              )
          }
          let summaries = grouped.values.compactMap { aggregates -> IntelligenceUsageBucketSummary? in
              guard let first = aggregates.first else { return nil }
              let cpu = average(aggregates.compactMap(\.averageCPUUsagePercent))
              let memory = average(aggregates.compactMap(\.averageMemoryUsedPercent))
              guard cpu != nil || memory != nil else { return nil }
              return IntelligenceUsageBucketSummary(
                  key: IntelligenceUsageBucketKey(
                      day: calendar.startOfDay(for: first.bucketStart),
                      hour: calendar.component(.hour, from: first.bucketStart)
                  ),
                  activityScore: usageActivityScore(cpuPercent: cpu, memoryPercent: memory),
                  cpuPercent: cpu,
                  memoryPercent: memory
              )
          }
          guard !summaries.isEmpty else { return nil }

          let dayGroups = Dictionary(grouping: summaries, by: \.key.day)
          let activeHoursPerDay = dayGroups.values.map { day in
              Double(day.filter { ($0.activityScore ?? 0) >= 0.15 }.count)
          }
          let hourlyGroups = Dictionary(grouping: summaries, by: \.key.hour)
          let hourlyProfile = hourlyGroups.keys.sorted().compactMap { hour -> IntelligenceUsageHour? in
              guard let values = hourlyGroups[hour], !values.isEmpty else { return nil }
              let averageScore = average(values.compactMap(\.activityScore))
              return IntelligenceUsageHour(
                  localHour: hour,
                  observedDays: Set(values.map(\.key.day)).count,
                  activeDays: values.filter { ($0.activityScore ?? 0) >= 0.15 }.count,
                  averageActivityScore: averageScore,
                  averageCPUPercent: average(values.compactMap(\.cpuPercent)),
                  averageMemoryUsedPercent: average(values.compactMap(\.memoryPercent))
              )
          }
          let activeProfile = hourlyProfile.filter { ($0.averageActivityScore ?? 0) >= 0.15 }
          let peakHour = hourlyProfile.max {
              ($0.averageActivityScore ?? 0) < ($1.averageActivityScore ?? 0)
          }?.localHour
          return IntelligenceUsageContext(
              windowDays: 7,
              observedDays: min(7, max(learningDaysObserved, dayGroups.count)),
              sampleCount: learningHourlyAggregates.reduce(0) { $0 + $1.sampleCount },
              averageActiveHoursPerDay: average(activeHoursPerDay),
              typicalStartLocalHour: activeProfile.map(\.localHour).min(),
              typicalEndLocalHour: activeProfile.map(\.localHour).max(),
              peakLocalHour: peakHour,
              hourlyProfile: hourlyProfile
          )
      }

      private func usageActivityScore(cpuPercent: Double?, memoryPercent: Double?) -> Double? {
          let cpu = cpuPercent.map { min(1, max(0, $0 / 100)) }
          let memory = memoryPercent.map { min(1, max(0, $0 / 100)) }
          switch (cpu, memory) {
          case let (.some(cpu), .some(memory)):
              return cpu * 0.6 + memory * 0.4
          case let (.some(cpu), nil):
              return cpu
          case let (nil, .some(memory)):
              return memory
          case (nil, nil):
              return nil
          }
      }

     private func average(_ values: [Double]) -> Double? {
         let finiteValues = values.filter { $0.isFinite }
         guard !finiteValues.isEmpty else { return nil }
         return finiteValues.reduce(0, +) / Double(finiteValues.count)
     }

     private func macModelIdentifier() -> String? {
         var size = 0
         guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
             return nil
         }
         var buffer = [CChar](repeating: 0, count: size)
         let result = buffer.withUnsafeMutableBytes { bytes in
             sysctlbyname("hw.model", bytes.baseAddress, &size, nil, 0)
         }
         guard result == 0 else { return nil }
         let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
         return String(decoding: bytes, as: UTF8.self)
     }

     private func machineArchitecture() -> String {
         #if arch(arm64)
         return "arm64"
         #elseif arch(x86_64)
         return "x86_64"
         #else
         return "unknown"
         #endif
     }

     private func powerWatts(for snapshot: BatterySnapshot) -> Double? {

        guard let watts = BatteryMath.batteryPowerWatts(
            voltageMillivolts: snapshot.voltageMillivolts,
            signedAmperageMilliamps: snapshot.amperageMilliamps
        ), abs(watts) >= 0.05 else {
            return nil
        }
        return watts
    }

    func setUpdateCheckEnabled(_ enabled: Bool) {
        updateCheckEnabled = enabled
        defaults.set(enabled, forKey: "cellium.updateCheckEnabled")
        if enabled {
            checkForUpdatesIfNeeded(force: true)
        } else {
            updateTask?.cancel()
            updateTask = nil
            availableUpdateAsset = nil
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
        availableUpdateAsset = nil
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
                    availableUpdateAsset = nil
                    updateState = .current(version: version)
                case let .available(release):
                    availableUpdateAsset = release.assets.first { asset in
                        let fileName = URL(fileURLWithPath: asset.name).lastPathComponent
                        return fileName == asset.name
                            && fileName.lowercased().hasSuffix(".zip")
                            && asset.digest != nil
                    }
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
                availableUpdateAsset = nil
                updateState = .failed
            }
        }
    }

    func installUpdate() {
        guard case let .available(version, _, _) = updateState,
              let asset = availableUpdateAsset else {
            openUpdatePage()
            return
        }

        updateTask?.cancel()
        updateState = .updating(version: version)
        let targetAppURL = Bundle.main.bundleURL
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.obed0101.cellium"
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let sourceAppURL = try await updateInstaller.prepare(
                    asset: asset,
                    expectedBundleIdentifier: bundleIdentifier
                )
                try updateInstaller.launchReplacement(
                    sourceAppURL: sourceAppURL,
                    targetAppURL: targetAppURL
                )
                updateTask = nil
                NSApplication.shared.terminate(nil)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                updateTask = nil
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
        weatherCoordinator.setLanguage(language)
        syncWeatherState()
        refreshLocalIntelligenceInsight()
        if let latest = latestIntelligenceAnalysis,
           latest.languageCode.lowercased().hasPrefix(language.rawValue) {
            restoreLatestIntelligenceInsight(from: intelligenceAnalysisLogs)
        } else {
            intelligenceInsight = localIntelligenceInsight
        }
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

    func setCyclePlanEnabled(_ enabled: Bool) {
        cyclePlanConfiguration.enabled = enabled
        cyclePlanDidChange()
    }

    func setCyclePlanMode(_ mode: CyclePlanMode) {
        cyclePlanConfiguration.mode = mode
        if mode == .targetDate {
            if cyclePlanConfiguration.targetDate == nil {
                cyclePlanConfiguration.targetDate = Calendar.autoupdatingCurrent.date(
                    byAdding: .year,
                    value: 1,
                    to: Date()
                )
            }
            if cyclePlanConfiguration.targetCycleCount == nil {
                cyclePlanConfiguration.targetCycleCount = (battery.cycleCount ?? 0) + 100
            }
        }
        cyclePlanDidChange()
    }

    func setCycleWeeklyBudget(_ value: Double) {
        cyclePlanConfiguration.weeklyEquivalentCycleBudget = min(100, max(0.1, value))
        cyclePlanDidChange()
    }

    func setCycleTargetDate(_ date: Date) {
        let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        cyclePlanConfiguration.targetDate = max(date, tomorrow)
        cyclePlanDidChange()
    }

    func setCycleTargetCount(_ value: Int) {
        cyclePlanConfiguration.targetCycleCount = max(battery.cycleCount ?? 0, value)
        cyclePlanDidChange()
    }

    func setCycleAlertsEnabled(_ enabled: Bool) {
        cyclePlanConfiguration.alertsEnabled = enabled
        cyclePlanDidChange()
    }

    private func cyclePlanDidChange() {
        persistCyclePlanConfiguration()
        guard let store else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await refreshCycleBudget(from: store, now: Date())
            evaluateProactiveSignals()
            refreshLocalIntelligenceInsight()
        }
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
        startIntelligenceMonitoring()
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
        intelligenceTask?.cancel()
        intelligenceTask = nil
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
        refreshHealthEstimate()
        lastUpdated = date
        if includeProcessImpacts {
            refreshProcessImpactsIfNeeded(
                at: date,
                allowBackground: includeBackgroundProcesses
            )
        }
        evaluateProactiveSignals()
        refreshLocalIntelligenceInsight()
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
            limit: 48,
            batteryPercentPerMinute: effectiveBatteryPercentPerMinute,
            memoryTotalBytes: system.memoryTotalBytes
        )
        if let store, !nextImpacts.isEmpty {
            let samples = nextImpacts.map {
                StoredProcessSample(
                    processID: $0.id,
                    name: $0.name,
                    kind: $0.kind,
                    timestamp: date,
                    cpuPercent: $0.averageCPUPercent,
                    residentMemoryBytes: $0.residentMemoryBytes,
                    memoryPercent: $0.memoryPercent,
                    estimatedBatteryPercentPerMinute: $0.estimatedBatteryPercentPerMinute
                )
            }
            Task {
                try? await store.appendProcessSamples(samples)
            }
        }
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
            try await refreshCycleBudget(from: store, now: now)
            evaluateProactiveSignals()
            refreshLocalIntelligenceInsight()
            refreshProcessImpactsIfNeeded(
                at: now,
                allowBackground: !panelVisible
            )
            if panelVisible,
               lastHistoryRefresh == nil || now.timeIntervalSince(lastHistoryRefresh ?? .distantPast) >= 60 {
                refreshHistory(includeSupportingData: false)
            }
        } catch {
            // The live snapshot remains available even when the local store is unavailable.
        }
    }

    private func refreshBackgroundSamples() async {
        await refreshPersistedDataIfNeeded(force: true)
    }

    private func evaluateProactiveSignals() {
        var candidates: [(score: Int, alert: ProactiveAlert)] = []
        if !isBatteryUseCurrentlyPausedByExternalPower,
           cyclePlanConfiguration.enabled,
           cyclePlanConfiguration.alertsEnabled,
           let summary = cycleUsageSummary,
           summary.status == .elevated || summary.status == .high {
            var measurements: [String: Double] = [
                "todayEFC": summary.todayEquivalentCycles,
                "rolling24HourEFC": summary.rolling24HourEquivalentCycles,
                "todayUsagePercent": summary.todayUsagePercent,
                "hardwareCycleDelta24h": Double(summary.rolling24HourHardwareCycleDelta),
                "weeklyEFC": summary.weekEquivalentCycles
            ]
            if let projected = summary.projectedWeekEquivalentCycles {
                measurements["projectedWeekEFC"] = projected
            }
            if let budget = summary.weeklyBudget {
                measurements["weeklyBudgetEFC"] = budget
            }
            let critical = summary.status == .high
            let alert = ProactiveAlert(
                identifier: critical ? "cycle-pace-high" : "cycle-pace-elevated",
                title: language == .spanish
                    ? (critical ? "Ritmo de ciclos alto" : "Uso de batería elevado")
                    : (critical ? "High cycle pace" : "Elevated battery use"),
                body: language == .spanish
                    ? String(
                        format: "%.2f ciclos equivalentes y +%d ciclos medidos en 24 h. Es uso acumulado alto, no daño confirmado.",
                        summary.rolling24HourEquivalentCycles,
                        summary.rolling24HourHardwareCycleDelta
                    )
                    : String(
                        format: "%.2f equivalent cycles and +%d measured cycles in 24h. This is high accumulated use, not confirmed damage.",
                        summary.rolling24HourEquivalentCycles,
                        summary.rolling24HourHardwareCycleDelta
                    ),
                severity: critical ? .critical : .warning,
                measurements: measurements
            )
            candidates.append((critical ? 300 : 180, alert))
        }

        if let app = processImpacts.first(where: { isHighMemoryImpact($0) }) {
            let memory = memoryDescription(for: app)
            candidates.append((140, ProactiveAlert(
                identifier: "memory:\(app.id)",
                title: copy(.alertMemoryTitle),
                body: String(format: copy(.appMemoryAlert), app.name, memory),
                subject: app.name,
                measurements: processMeasurements(for: app)
            )))
        }
        if let dischargeRate = effectiveBatteryPercentPerMinute, dischargeRate >= 0.35 {
            candidates.append((160, ProactiveAlert(
                identifier: "discharge",
                title: copy(.alertDischargeTitle),
                body: String(format: copy(.rapidDischargeAlert), dischargeRate),
                measurements: ["percentPerMinute": dischargeRate]
            )))
        }
        if let app = processImpacts.first(where: { ($0.estimatedBatteryPercentPerMinute ?? 0) >= 0.05 }),
           let rate = app.estimatedBatteryPercentPerMinute {
            candidates.append((130, ProactiveAlert(
                identifier: "energy:\(app.id)",
                title: copy(.alertEnergyTitle),
                body: String(format: copy(.appEnergyAlert), app.name, rate),
                subject: app.name,
                measurements: processMeasurements(for: app, energyRate: rate)
            )))
        }
        if let app = processImpacts.first(where: { isHighCPUImpact($0) }) {
            candidates.append((120, ProactiveAlert(
                identifier: "cpu:\(app.id)",
                title: copy(.alertCPUProcessTitle),
                body: String(format: copy(.appCPUAlert), app.name, app.averageCPUPercent),
                subject: app.name,
                measurements: processMeasurements(for: app)
            )))
        }
        if let memory = system.memoryUsedPercent, memory >= 90 {
            candidates.append((110, ProactiveAlert(
                identifier: "system-memory",
                title: copy(.alertMemoryTitle),
                body: String(format: copy(.memoryAlert), memory),
                measurements: ["memoryPercent": memory]
            )))
        }

        let candidate = candidates.max { $0.score < $1.score }?.alert
        proactiveAlert = candidate
        guard let candidate else { return }
        let now = Date()
        let cooldown: TimeInterval = candidate.identifier.hasPrefix("cycle-pace")
            ? 6 * 60 * 60
            : 20 * 60
        let alertDateKey = "cellium.alert.lastDate.\(candidate.identifier)"
        if let lastDate = defaults.object(forKey: alertDateKey) as? Date,
           now.timeIntervalSince(lastDate) < cooldown {
            return
        }
        lastProactiveAlertKey = candidate.identifier
        lastProactiveAlertDate = now
        defaults.set(now, forKey: alertDateKey)
        persistAlertEvent(candidate, occurredAt: now)
        onProactiveAlert?(candidate)
    }

    private func persistAlertEvent(_ alert: ProactiveAlert, occurredAt: Date) {
        guard let store else { return }
        let event = StoredAlertEvent(
            identifier: alert.identifier,
            occurredAt: occurredAt,
            severity: alert.severity,
            subject: alert.subject,
            measurements: alert.measurements
        )
        Task {
            try? await store.appendAlertEvent(event)
        }
    }

    private func isHighMemoryImpact(_ impact: ProcessEnergyImpact) -> Bool {
        if let memoryPercent = impact.memoryPercent, memoryPercent >= 20 {
            return true
        }
        return (impact.residentMemoryBytes ?? 0) >= 4 * 1_024 * 1_024 * 1_024
    }

    private func isHighCPUImpact(_ impact: ProcessEnergyImpact) -> Bool {
        impact.averageCPUPercent >= 20
    }

    private func memoryDescription(for impact: ProcessEnergyImpact) -> String {
        if let bytes = impact.residentMemoryBytes {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
        }
        return language == .spanish ? "mucha" : "high"
    }

    private func processMeasurements(
        for impact: ProcessEnergyImpact,
        energyRate: Double? = nil
    ) -> [String: Double] {
        var measurements = ["cpuPercent": impact.averageCPUPercent]
        if let memoryPercent = impact.memoryPercent {
            measurements["memoryPercent"] = memoryPercent
        }
        if let residentMemoryBytes = impact.residentMemoryBytes {
            measurements["residentMemoryBytes"] = Double(residentMemoryBytes)
        }
        if let energyRate {
            measurements["percentPerMinute"] = energyRate
        } else if let estimatedRate = impact.estimatedBatteryPercentPerMinute {
            measurements["percentPerMinute"] = estimatedRate
        }
        return measurements
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
    let kind: StoredProcessKind
    let icon: NSImage?
    let applicationID: Int32?
    let averageCPUPercent: Double
    let residentMemoryBytes: Int64?
    let memoryPercent: Double?
    let estimatedBatteryPercentPerMinute: Double?

    static func == (lhs: ProcessEnergyImpact, rhs: ProcessEnergyImpact) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.kind == rhs.kind
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
    private struct ApplicationIdentity {
        let processID: Int32
        let name: String
        let icon: NSImage?
    }

    private struct ProcessUsage {
        let processID: Int32
        let name: String
        let kind: StoredProcessKind
        let icon: NSImage?
        let applicationID: Int32?
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
        let runningApplications = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != currentProcessID && !$0.isTerminated
        }
        let applicationsByID = Dictionary(
            uniqueKeysWithValues: runningApplications.map { ($0.processIdentifier, $0) }
        )
        let applicationsByBundlePath = runningApplications.reduce(
            into: [String: ApplicationIdentity]()
        ) { result, application in
            guard let bundleURL = application.bundleURL else { return }
            let bundlePath = bundleURL.standardizedFileURL.path
            if let existing = result[bundlePath],
               existing.processID != application.processIdentifier,
               application.activationPolicy != .regular {
                return
            }
            result[bundlePath] = applicationIdentity(from: application, bundleURL: bundleURL)
        }
        let processIDs = allProcessIDs().filter { $0 != currentProcessID && $0 > 0 }
        let activeIDs = Set(processIDs)
        previousCPUSeconds = previousCPUSeconds.filter { activeIDs.contains($0.key) }
        observations = observations.filter { activeIDs.contains($0.key) }
        lastRankOrder = lastRankOrder.filter { activeIDs.contains($0.key) }

        let usages = processIDs.compactMap { processID in
            let application = applicationsByID[processID]
            let identity = applicationIdentity(
                for: processID,
                application: application,
                applicationsByBundlePath: applicationsByBundlePath
            )
            return processUsage(
                for: processID,
                application: application,
                applicationIdentity: identity,
                at: now
            )
        }
        let totalCPU = max(1, usages.reduce(0) { $0 + $1.cpuPercent })
        let cutoff = now.addingTimeInterval(-observationWindow)

        for usage in usages {
            let processID = usage.processID
            let cpuShare = max(0, min(1, usage.cpuPercent / totalCPU))
            let estimatedBatteryPercentPerMinute: Double?
            if usage.cpuPercent > 0 {
                estimatedBatteryPercentPerMinute = batteryPercentPerMinute.map {
                    max(0, $0) * cpuShare
                }
            } else {
                estimatedBatteryPercentPerMinute = nil
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

        let processImpacts = usages.compactMap { usage -> ProcessEnergyImpact? in
            let processID = usage.processID
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
                name: usage.name,
                kind: usage.kind,
                icon: usage.icon,
                applicationID: usage.applicationID,
                averageCPUPercent: averageCPU,
                residentMemoryBytes: averageMemoryBytes,
                memoryPercent: memoryPercent,
                estimatedBatteryPercentPerMinute: averageBatteryRate
            )
        }

        let groupedApplications = Dictionary(grouping: processImpacts.compactMap { impact in
            impact.applicationID == nil ? nil : impact
        }) { impact in
            impact.applicationID!
        }
        var impacts = processImpacts.filter { $0.applicationID == nil }
        for (applicationID, applicationImpacts) in groupedApplications {
            impacts.append(aggregateApplicationImpacts(applicationID, from: applicationImpacts))
        }

        let sorted = impacts.sorted { left, right in
            let leftEnergy = left.estimatedBatteryPercentPerMinute ?? 0
            let rightEnergy = right.estimatedBatteryPercentPerMinute ?? 0
            if Swift.abs(leftEnergy - rightEnergy) > 0.005 {
                return leftEnergy > rightEnergy
            }
            if abs(left.averageCPUPercent - right.averageCPUPercent) > 0.25 {
                return left.averageCPUPercent > right.averageCPUPercent
            }
            let leftMemory = left.memoryPercent ?? Double(left.residentMemoryBytes ?? 0)
            let rightMemory = right.memoryPercent ?? Double(right.residentMemoryBytes ?? 0)
            if abs(leftMemory - rightMemory) > 0.25 {
                return leftMemory > rightMemory
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
        return result
    }

    private func allProcessIDs() -> [Int32] {
        let requestedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard requestedBytes > 0 else { return [] }
        let count = Int(requestedBytes) / MemoryLayout<pid_t>.stride + 1
        var processIDs = [pid_t](repeating: 0, count: count)
        let returnedBytes = processIDs.withUnsafeMutableBytes { buffer in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard returnedBytes > 0 else { return [] }
        let returnedCount = min(processIDs.count, Int(returnedBytes) / MemoryLayout<pid_t>.stride)
        return Array(processIDs.prefix(returnedCount))
    }

    private func processPath(for processID: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = buffer.withUnsafeMutableBytes { rawBuffer in
            proc_pidpath(processID, rawBuffer.baseAddress, UInt32(rawBuffer.count))
        }
        guard length > 0 else { return nil }
        let bytes = buffer.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
    }

    private func applicationBundleURL(for processID: Int32) -> URL? {
        guard let path = processPath(for: processID) else { return nil }
        let components = URL(fileURLWithPath: path).pathComponents
        guard let contentsIndex = components.firstIndex(where: {
            $0.caseInsensitiveCompare("Contents") == .orderedSame
        }),
        contentsIndex > 1,
        components[contentsIndex - 1].lowercased().hasSuffix(".app") else {
            return nil
        }
        let bundlePath = "/" + components.dropFirst().prefix(contentsIndex - 1).joined(separator: "/")
        return URL(fileURLWithPath: bundlePath).standardizedFileURL
    }

    private func applicationIdentity(
        from application: NSRunningApplication,
        bundleURL: URL? = nil
    ) -> ApplicationIdentity {
        let resolvedBundleURL = bundleURL ?? application.bundleURL
        let fallbackName = resolvedBundleURL?.deletingPathExtension().lastPathComponent
            ?? "PID \(application.processIdentifier)"
        let name: String
        if let localizedName = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localizedName.isEmpty {
            name = localizedName
        } else {
            name = fallbackName
        }
        return ApplicationIdentity(
            processID: application.processIdentifier,
            name: name,
            icon: application.icon
        )
    }

    private func applicationIdentity(
        for processID: Int32,
        application: NSRunningApplication?,
        applicationsByBundlePath: [String: ApplicationIdentity]
    ) -> ApplicationIdentity? {
        if let application {
            return applicationIdentity(from: application)
        }
        guard let bundleURL = applicationBundleURL(for: processID) else { return nil }
        if let application = applicationsByBundlePath[bundleURL.path] {
            return application
        }
        return ApplicationIdentity(
            processID: processID,
            name: bundleURL.deletingPathExtension().lastPathComponent,
            icon: NSWorkspace.shared.icon(forFile: bundleURL.path)
        )
    }

    private func processName(for processID: Int32, application: NSRunningApplication?) -> String {
        if let localizedName = application?.localizedName,
           !localizedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localizedName
        }
        if let path = processPath(for: processID) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "PID \(processID)"
    }

    private func processKind(
        for processID: Int32,
        application: NSRunningApplication?,
        applicationIdentity: ApplicationIdentity?
    ) -> StoredProcessKind {
        let path = processPath(for: processID)?.lowercased() ?? ""
        let name = processName(for: processID, application: application).lowercased()
        if applicationIdentity != nil
            || application?.activationPolicy == .regular
            || path.contains(".app/contents/") {
            return .application
        }
        let scriptExtensions = [".sh", ".bash", ".zsh", ".fish", ".py", ".rb", ".pl", ".js", ".command"]
        let scriptRunners = ["sh", "bash", "zsh", "fish", "python", "python3", "ruby", "perl", "node", "osascript"]
        if scriptExtensions.contains(where: path.hasSuffix)
            || scriptRunners.contains(where: { name == $0 || name.hasPrefix("\($0).") }) {
            return .script
        }
        if path.hasPrefix("/usr/libexec/")
            || path.hasPrefix("/system/library/")
            || path.hasPrefix("/library/launchdaemons/")
            || path.hasPrefix("/sbin/")
            || path.hasPrefix("/usr/sbin/") {
            return .daemon
        }
        return .process
    }

    private func processUsage(
        for processID: Int32,
        application: NSRunningApplication?,
        applicationIdentity: ApplicationIdentity?,
        at date: Date
    ) -> ProcessUsage? {
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
            return ProcessUsage(
                processID: processID,
                name: applicationIdentity?.name ?? processName(for: processID, application: application),
                kind: processKind(
                    for: processID,
                    application: application,
                    applicationIdentity: applicationIdentity
                ),
                icon: applicationIdentity?.icon ?? application?.icon,
                applicationID: applicationIdentity?.processID,
                cpuPercent: 0,
                residentMemoryBytes: residentMemoryBytes(for: processID)
            )
        }
        let elapsed = max(1, date.timeIntervalSince(previous.date))
        let delta = max(0, cpuSeconds - previous.seconds)
        let cpuPercent = min(400, max(0, delta / elapsed * 100))
        previousCPUSeconds[processID] = (cpuSeconds, date)

        return ProcessUsage(
            processID: processID,
            name: applicationIdentity?.name ?? processName(for: processID, application: application),
            kind: processKind(
                for: processID,
                application: application,
                applicationIdentity: applicationIdentity
            ),
            icon: applicationIdentity?.icon ?? application?.icon,
            applicationID: applicationIdentity?.processID,
            cpuPercent: cpuPercent,
            residentMemoryBytes: residentMemoryBytes(for: processID)
        )
    }

    private func aggregateApplicationImpacts(
        _ applicationID: Int32,
        from impacts: [ProcessEnergyImpact]
    ) -> ProcessEnergyImpact {
        let memorySamples = impacts.compactMap(\.residentMemoryBytes)
        let averageMemoryBytes = memorySamples.isEmpty ? nil : memorySamples.reduce(0, +)
        let batterySamples = impacts.compactMap(\.estimatedBatteryPercentPerMinute)
        let estimatedBattery = batterySamples.isEmpty
            ? nil
            : batterySamples.reduce(0, +)
        let memoryPercent = impacts.compactMap(\.memoryPercent).reduce(0, +)
        let representative = impacts.max { left, right in
            left.averageCPUPercent < right.averageCPUPercent
        } ?? impacts[0]
        return ProcessEnergyImpact(
            id: applicationID,
            name: representative.name,
            kind: .application,
            icon: impacts.compactMap(\.icon).first,
            applicationID: nil,
            averageCPUPercent: impacts.reduce(0) { $0 + $1.averageCPUPercent },
            residentMemoryBytes: averageMemoryBytes,
            memoryPercent: memoryPercent > 0 ? memoryPercent : nil,
            estimatedBatteryPercentPerMinute: estimatedBattery
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
            Text(model.copy(.appName))
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
            MetricView(title: model.copy(.health), value: healthText, quality: model.copy(.calculated))
            MetricView(title: model.copy(.temperature), value: temperatureText, quality: model.copy(.measured))
            MetricView(title: model.copy(.cycles), value: cycleText, quality: model.copy(.measured))
        }
    }

    private var drivers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.language == .spanish ? "Estado del sistema" : "System state")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            HStack(spacing: 8) {
                StatePill(title: model.system.thermalState.rawValue.capitalized, color: CelliumBrand.accent)
                StatePill(
                    title: model.system.lowPowerModeEnabled
                        ? (model.language == .spanish ? "Bajo consumo" : "Low Power")
                        : (model.language == .spanish ? "Automático" : "Automatic"),
                    color: CelliumBrand.info
                )
                if let watts = model.batteryPowerWatts {
                    StatePill(title: String(format: "%.1f W", watts), color: watts > 0 ? CelliumBrand.warning : CelliumBrand.accent)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Text(model.language == .spanish ? "Monitoreo de solo lectura" : "Read-only monitoring")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            Spacer()
            Text(model.language == .spanish ? "Diagnóstico →" : "Diagnostics →")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CelliumBrand.accentStrong)
        }
    }

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.language == .spanish ? "Historial y diagnóstico" : "History & diagnostics")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                Spacer()
                Picker(
                    model.language == .spanish ? "Rango del historial" : "History range",
                    selection: Binding(
                    get: { model.historyRange },
                    set: { model.setHistoryRange($0) }
                    )
                ) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.label(for: model.language)).tag(range)
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
                .accessibilityLabel(
                    model.language == .spanish
                        ? "Actualizar historial y diagnóstico"
                        : "Refresh history and diagnostics"
                )
            }

            if let storeError = model.storeError {
                Label(storeError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CelliumBrand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if model.historyAggregates.isEmpty {
                        Text(model.copy(.noData))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                } else {
                        HistoryChart(aggregates: model.historyAggregates, language: model.language)
                        .frame(height: 96)
                        .accessibilityLabel(
                            model.language == .spanish
                                ? "Historial del nivel de batería para \(model.historyRange.label(for: model.language))"
                                : "Battery charge history for \(model.historyRange.label(for: model.language))"
                        )
                }

                if model.recentSamples.isEmpty {
                    Text(model.copy(.noRecentSamples))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                } else {
                    ForEach(Array(model.recentSamples.prefix(3).enumerated()), id: \.offset) { _, sample in
                        HistorySampleRow(sample: sample, language: model.language)
                    }
                }
                if !model.recentSessions.isEmpty {
                    ForEach(Array(model.recentSessions.prefix(2).enumerated()), id: \.offset) { _, session in
                        SessionHistoryRow(session: session, language: model.language)
                    }
                }

                HStack(spacing: 8) {
                    Text(model.language == .spanish ? "Calidad" : "Quality")
                    Text(model.battery.sourceQuality.rawValue)
                    Spacer()
                    Text(model.copy(.sampling))
                    Text(model.samplingMode.rawValue)
                }
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)

                if let diagnostics = model.storeDiagnostics {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            model.language == .spanish
                                ? "SQLite v\(diagnostics.schemaVersion) · \(ByteCountFormatter.string(fromByteCount: diagnostics.databaseSizeBytes, countStyle: .file)) · WAL \(ByteCountFormatter.string(fromByteCount: diagnostics.walSizeBytes, countStyle: .file))"
                                : "SQLite v\(diagnostics.schemaVersion) · \(ByteCountFormatter.string(fromByteCount: diagnostics.databaseSizeBytes, countStyle: .file)) · WAL \(ByteCountFormatter.string(fromByteCount: diagnostics.walSizeBytes, countStyle: .file))"
                        )
                        Text(
                            model.language == .spanish
                                ? "Escrituras pendientes: \(model.pendingSampleCount) muestras · \(model.pendingSessionCount) sesiones"
                                : "Pending writes: \(model.pendingSampleCount) samples · \(model.pendingSessionCount) sessions"
                        )
                        Text(
                            model.language == .spanish
                                ? "Diagnóstico: \(model.battery.diagnostics.isEmpty ? "ninguno" : model.battery.diagnostics.joined(separator: ", "))"
                                : "Diagnostics: \(model.battery.diagnostics.isEmpty ? "none" : model.battery.diagnostics.joined(separator: ", "))"
                        )
                    }
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            model.language == .spanish
                                ? "Esquema SQLite \(diagnostics.schemaVersion), base de datos de \(diagnostics.databaseSizeBytes) bytes, WAL de \(diagnostics.walSizeBytes) bytes"
                                : "SQLite schema \(diagnostics.schemaVersion), database size \(diagnostics.databaseSizeBytes) bytes, WAL size \(diagnostics.walSizeBytes) bytes"
                        )
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
        model.statusTitle
    }

    private var statusExplanation: String {
        model.statusExplanation
    }

    private var statusColor: Color {
        switch model.statusKind {
        case .protected: return CelliumBrand.accent
        case .charging: return CelliumBrand.accentStrong
        case .connectedNotCharging: return CelliumBrand.accentStrong
        case .elevated: return CelliumBrand.warning
        case .attention: return CelliumBrand.critical
        }
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
    let language: CelliumLanguage

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
        .accessibilityLabel(
            language == .spanish
                ? "Muestra de batería, \(sample.battery.chargePercent.map { "\($0) por ciento" } ?? "nivel no disponible")"
                : "Battery sample, \(sample.battery.chargePercent.map { "\($0) percent" } ?? "charge unavailable")"
        )
    }
}

private struct SessionHistoryRow: View {
    let session: BatterySession
    let language: CelliumLanguage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.kind == .charging ? "bolt.fill" : "battery.100")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(session.kind == .charging ? CelliumBrand.warning : CelliumBrand.accent)
            Text(sessionTitle)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Spacer()
            Text(language == .spanish ? "\(session.sampleCount) muestras" : "\(session.sampleCount) samples")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            language == .spanish
                ? "Sesión \(sessionTitle), \(session.sampleCount) muestras"
                : "\(sessionTitle) session, \(session.sampleCount) samples"
        )
    }

    private var sessionTitle: String {
        switch (session.kind, language) {
        case (.charging, .spanish): return "Cargando"
        case (.discharging, .spanish): return "Descargando"
        case (.connectedDeficit, .spanish): return "Conectado sin cargar"
        case (.sleepGap, .spanish): return "Pausa de reposo"
        case (.charging, .english): return "Charging"
        case (.discharging, .english): return "Discharging"
        case (.connectedDeficit, .english): return "Connected, not charging"
        case (.sleepGap, .english): return "Sleep gap"
        }
    }
}

private struct HistoryChart: View {
    let aggregates: [BatteryAggregate]
    let language: CelliumLanguage

    var body: some View {
        Chart {
            ForEach(Array(aggregates.enumerated()), id: \.offset) { _, aggregate in
                if let charge = aggregate.averageChargePercent {
                    LineMark(
                        x: .value(language == .spanish ? "Hora" : "Time", aggregate.bucketStart),
                        y: .value(language == .spanish ? "Nivel" : "Charge", charge)
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
