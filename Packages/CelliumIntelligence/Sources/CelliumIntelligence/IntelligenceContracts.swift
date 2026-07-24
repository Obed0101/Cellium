import Foundation
import CelliumCore

public enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low
    case unavailable
}

public enum IntelligenceProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openRouter
    case ollama

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openRouter:
            return "OpenRouter"
        case .ollama:
            return "Ollama"
        }
    }

    public var requiresAPIKey: Bool {
        self == .openRouter
    }
}

public enum IntelligenceModelCategory: String, CaseIterable, Sendable {
    case recommended
    case budget
    case fast
    case balanced
    case free
}

public struct IntelligenceModelRecommendation: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let category: IntelligenceModelCategory
    public let promptCostPerMillion: Double?
    public let completionCostPerMillion: Double?
    public let contextLength: Int?

    public init(
        id: String,
        name: String,
        category: IntelligenceModelCategory,
        promptCostPerMillion: Double? = nil,
        completionCostPerMillion: Double? = nil,
        contextLength: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.promptCostPerMillion = promptCostPerMillion
        self.completionCostPerMillion = completionCostPerMillion
        self.contextLength = contextLength
    }
}

public enum IntelligenceModelCatalog {
    public static let openRouter: [IntelligenceModelRecommendation] = [
        IntelligenceModelRecommendation(
            id: "openrouter/auto",
            name: "Auto · OpenRouter",
            category: .recommended
        ),
        IntelligenceModelRecommendation(
            id: "deepseek/deepseek-v4-flash",
            name: "DeepSeek V4 Flash",
            category: .recommended,
            promptCostPerMillion: 0.098,
            completionCostPerMillion: 0.196,
            contextLength: 1_048_576
        ),
        IntelligenceModelRecommendation(
            id: "xiaomi/mimo-v2.5",
            name: "Xiaomi MiMo-V2.5",
            category: .recommended,
            promptCostPerMillion: 0.14,
            completionCostPerMillion: 0.28,
            contextLength: 1_050_000
        ),
        IntelligenceModelRecommendation(
            id: "minimax/minimax-m3",
            name: "MiniMax M3",
            category: .recommended,
            promptCostPerMillion: 0.30,
            completionCostPerMillion: 1.20,
            contextLength: 1_048_576
        ),
        IntelligenceModelRecommendation(
            id: "qwen/qwen3.5-flash-02-23",
            name: "Qwen3.5 Flash",
            category: .budget,
            promptCostPerMillion: 0.065,
            completionCostPerMillion: 0.26,
            contextLength: 1_000_000
        ),
        IntelligenceModelRecommendation(
            id: "mistralai/mistral-nemo",
            name: "Mistral Nemo",
            category: .budget,
            promptCostPerMillion: 0.019,
            completionCostPerMillion: 0.03,
            contextLength: 131_072
        ),
        IntelligenceModelRecommendation(
            id: "nvidia/nemotron-3-nano-30b-a3b",
            name: "Nemotron 3 Nano",
            category: .budget,
            promptCostPerMillion: 0.05,
            completionCostPerMillion: 0.20,
            contextLength: 262_144
        ),
        IntelligenceModelRecommendation(
            id: "google/gemini-2.5-flash-lite",
            name: "Gemini 2.5 Flash Lite",
            category: .fast,
            promptCostPerMillion: 0.10,
            completionCostPerMillion: 0.40,
            contextLength: 1_048_576
        ),
        IntelligenceModelRecommendation(
            id: "qwen/qwen3-coder-flash",
            name: "Qwen3 Coder Flash",
            category: .fast,
            promptCostPerMillion: 0.195,
            completionCostPerMillion: 0.975,
            contextLength: 1_000_000
        ),
        IntelligenceModelRecommendation(
            id: "mistralai/ministral-8b-2512",
            name: "Ministral 3 8B",
            category: .fast,
            promptCostPerMillion: 0.15,
            completionCostPerMillion: 0.15,
            contextLength: 262_144
        ),
        IntelligenceModelRecommendation(
            id: "qwen/qwen3-30b-a3b-instruct-2507",
            name: "Qwen3 30B A3B Instruct",
            category: .balanced,
            promptCostPerMillion: 0.10,
            completionCostPerMillion: 0.30,
            contextLength: 262_144
        ),
        IntelligenceModelRecommendation(
            id: "openai/gpt-4o-mini",
            name: "GPT-4o mini",
            category: .balanced,
            promptCostPerMillion: 0.15,
            completionCostPerMillion: 0.60,
            contextLength: 128_000
        ),
        IntelligenceModelRecommendation(
            id: "google/gemma-4-26b-a4b-it:free",
            name: "Gemma 4 26B · Free",
            category: .free,
            contextLength: 262_144
        ),
        IntelligenceModelRecommendation(
            id: "nvidia/nemotron-3-nano-30b-a3b:free",
            name: "Nemotron 3 Nano · Free",
            category: .free,
            contextLength: 262_144
        )
    ]

    public static func recommendation(for modelID: String) -> IntelligenceModelRecommendation? {
        openRouter.first { $0.id == modelID }
    }
}

public struct IntelligenceConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var provider: IntelligenceProvider
    public var model: String
    public var automaticAnalysisEnabled: Bool
    public var ollamaEndpoint: String

    public init(
        enabled: Bool = false,
        provider: IntelligenceProvider = .openRouter,
        model: String = "openrouter/auto",
        automaticAnalysisEnabled: Bool = false,
        ollamaEndpoint: String = "http://127.0.0.1:11434"
    ) {
        self.enabled = enabled
        self.provider = provider
        self.model = model
        self.automaticAnalysisEnabled = automaticAnalysisEnabled
        self.ollamaEndpoint = ollamaEndpoint
    }

    public var ollamaURL: URL? {
        URL(string: ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public struct BatteryEvidencePoint: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let chargePercent: Int?
    public let powerWatts: Double?
    public let temperatureCelsius: Double?

    public init(
        timestamp: Date,
        chargePercent: Int?,
        powerWatts: Double?,
        temperatureCelsius: Double?
    ) {
        self.timestamp = timestamp
        self.chargePercent = chargePercent
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
    }
}

public struct ProcessEvidence: Codable, Equatable, Sendable {
    public let name: String
    public let kind: String
    public let cpuPercent: Double
    public let memoryPercent: Double?
    public let estimatedBatteryPercentPerMinute: Double?

    public init(
        name: String,
        kind: String = "process",
        cpuPercent: Double,
        memoryPercent: Double?,
        estimatedBatteryPercentPerMinute: Double?
    ) {
        self.name = name
        self.kind = kind
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.estimatedBatteryPercentPerMinute = estimatedBatteryPercentPerMinute
    }
}

public struct IntelligenceDeviceContext: Codable, Equatable, Sendable {
    public let modelIdentifier: String?
    public let operatingSystem: String
    public let architecture: String

    public init(
        modelIdentifier: String? = nil,
        operatingSystem: String,
        architecture: String
    ) {
        self.modelIdentifier = modelIdentifier
        self.operatingSystem = operatingSystem
        self.architecture = architecture
    }
}

public struct IntelligenceWeatherContext: Codable, Equatable, Sendable {
    public let locationLabel: String?
    public let condition: String
    public let temperatureCelsius: Double
    public let apparentTemperatureCelsius: Double
    public let relativeHumidityPercent: Double
    public let windSpeedKmh: Double

    public init(
        locationLabel: String? = nil,
        condition: String,
        temperatureCelsius: Double,
        apparentTemperatureCelsius: Double,
        relativeHumidityPercent: Double,
        windSpeedKmh: Double
    ) {
        self.locationLabel = locationLabel
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.apparentTemperatureCelsius = apparentTemperatureCelsius
        self.relativeHumidityPercent = relativeHumidityPercent
        self.windSpeedKmh = windSpeedKmh
    }
}

public struct IntelligenceLearningDay: Codable, Equatable, Sendable {
    public let date: Date
    public let sampleCount: Int
    public let averageChargePercent: Double?
    public let averageBatteryPowerWatts: Double?
    public let averageTemperatureCelsius: Double?
    public let averageCPUUsagePercent: Double?
    public let averageMemoryUsedPercent: Double?

    public init(
        date: Date,
        sampleCount: Int,
        averageChargePercent: Double? = nil,
        averageBatteryPowerWatts: Double? = nil,
        averageTemperatureCelsius: Double? = nil,
        averageCPUUsagePercent: Double? = nil,
        averageMemoryUsedPercent: Double? = nil
    ) {
        self.date = date
        self.sampleCount = sampleCount
        self.averageChargePercent = averageChargePercent
        self.averageBatteryPowerWatts = averageBatteryPowerWatts
        self.averageTemperatureCelsius = averageTemperatureCelsius
        self.averageCPUUsagePercent = averageCPUUsagePercent
        self.averageMemoryUsedPercent = averageMemoryUsedPercent
    }
}

public struct IntelligenceLearningContext: Codable, Equatable, Sendable {
    public let windowDays: Int
    public let observedDays: Int
    public let sampleCount: Int
    public let firstSampleDate: Date?
    public let lastSampleDate: Date?
    public let averageBatteryPowerWatts: Double?
    public let averageChargePercent: Double?
    public let averageTemperatureCelsius: Double?
    public let averageCPUUsagePercent: Double?
    public let averageMemoryUsedPercent: Double?
    public let days: [IntelligenceLearningDay]

    public init(
        windowDays: Int = 7,
        observedDays: Int,
        sampleCount: Int,
        firstSampleDate: Date? = nil,
        lastSampleDate: Date? = nil,
        averageBatteryPowerWatts: Double? = nil,
        averageChargePercent: Double? = nil,
        averageTemperatureCelsius: Double? = nil,
        averageCPUUsagePercent: Double? = nil,
        averageMemoryUsedPercent: Double? = nil,
        days: [IntelligenceLearningDay] = []
    ) {
        self.windowDays = max(1, windowDays)
        self.observedDays = max(0, observedDays)
        self.sampleCount = max(0, sampleCount)
        self.firstSampleDate = firstSampleDate
        self.lastSampleDate = lastSampleDate
        self.averageBatteryPowerWatts = averageBatteryPowerWatts
        self.averageChargePercent = averageChargePercent
        self.averageTemperatureCelsius = averageTemperatureCelsius
        self.averageCPUUsagePercent = averageCPUUsagePercent
        self.averageMemoryUsedPercent = averageMemoryUsedPercent
        self.days = days
    }
}

public struct IntelligenceContext: Codable, Equatable, Sendable {
    public let device: IntelligenceDeviceContext
    public let weather: IntelligenceWeatherContext?
    public let weeklyLearning: IntelligenceLearningContext

    public init(
        device: IntelligenceDeviceContext,
        weather: IntelligenceWeatherContext? = nil,
        weeklyLearning: IntelligenceLearningContext
    ) {
        self.device = device
        self.weather = weather
        self.weeklyLearning = weeklyLearning
    }
}

public struct BatteryEvidenceSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let chargePercent: Int?
    public let isCharging: Bool
    public let externalPowerConnected: Bool
    public let powerWatts: Double?
    public let dischargePercentPerMinute: Double?
    public let temperatureCelsius: Double?
    public let healthPercent: Double?
    public let cycleCount: Int?
    public let designCycleCount: Int?
    public let thermalState: ThermalState
    public let lowPowerModeEnabled: Bool
    public let cpuUsagePercent: Double?
    public let memoryUsedPercent: Double?
    public let diskUsedPercent: Double?
    public let learningDaysObserved: Int
    public let recentHistory: [BatteryEvidencePoint]
    public let processImpacts: [ProcessEvidence]
    public let context: IntelligenceContext?
    public let cycleUsage: CycleUsageSummary?

    public init(
        capturedAt: Date = Date(),
        chargePercent: Int?,
        isCharging: Bool,
        externalPowerConnected: Bool,
        powerWatts: Double?,
        dischargePercentPerMinute: Double?,
        temperatureCelsius: Double?,
        healthPercent: Double?,
        cycleCount: Int?,
        designCycleCount: Int?,
        thermalState: ThermalState,
        lowPowerModeEnabled: Bool,
        cpuUsagePercent: Double?,
        memoryUsedPercent: Double?,
        diskUsedPercent: Double?,
        learningDaysObserved: Int,
        recentHistory: [BatteryEvidencePoint] = [],
        processImpacts: [ProcessEvidence] = [],
        context: IntelligenceContext? = nil,
        cycleUsage: CycleUsageSummary? = nil
    ) {
        self.capturedAt = capturedAt
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.externalPowerConnected = externalPowerConnected
        self.powerWatts = powerWatts
        self.dischargePercentPerMinute = dischargePercentPerMinute
        self.temperatureCelsius = temperatureCelsius
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.thermalState = thermalState
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsedPercent = memoryUsedPercent
        self.diskUsedPercent = diskUsedPercent
        self.learningDaysObserved = max(0, learningDaysObserved)
        self.recentHistory = recentHistory
        self.processImpacts = processImpacts
        self.context = context
        self.cycleUsage = cycleUsage
    }
}

public enum BatteryInsightSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

public struct BatteryInsight: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let title: String
    public let summary: String
    public let severity: BatteryInsightSeverity
    public let confidence: Confidence
    public let evidence: [String]
    public let recommendations: [String]
    public let provider: IntelligenceProvider?

    public init(
        generatedAt: Date = Date(),
        title: String,
        summary: String,
        severity: BatteryInsightSeverity,
        confidence: Confidence,
        evidence: [String],
        recommendations: [String],
        provider: IntelligenceProvider? = nil
    ) {
        self.generatedAt = generatedAt
        self.title = title
        self.summary = summary
        self.severity = severity
        self.confidence = confidence
        self.evidence = evidence
        self.recommendations = recommendations
        self.provider = provider
    }
}

public struct IntelligenceAnalysisResult: Sendable {
    public let insight: BatteryInsight
    public let prompt: String
    public let response: String
    public let actionRequired: Bool
    public let actionMessage: String?

    public init(
        insight: BatteryInsight,
        prompt: String,
        response: String,
        actionRequired: Bool = false,
        actionMessage: String? = nil
    ) {
        self.insight = insight
        self.prompt = prompt
        self.response = response
        self.actionRequired = actionRequired
        self.actionMessage = actionMessage
    }
}

public struct IntelligenceChatResult: Sendable {
    public let languageCode: String
    public let prompt: String
    public let response: String

    public init(languageCode: String, prompt: String, response: String) {
        self.languageCode = languageCode
        self.prompt = prompt
        self.response = response
    }
}

public enum AgentMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct AgentChatMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: AgentMessageRole
    public let content: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: AgentMessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public enum AssistantResponseFormatter {
    public static func format(_ response: String) -> String {
        let normalized = normalizeLineBreaks(response)
        let hadExplicitLineBreak = normalized.contains("\n")
        let repairedMissingSpaces = replacing(
            #"([.!?])(?=[A-ZÁÉÍÓÚÑÜ])"#,
            in: normalized,
            with: "$1\n\n"
        )

        guard !hadExplicitLineBreak else {
            return repairedMissingSpaces
        }

        return replacing(
            #"([.!?])[ \\t]+(?=[A-ZÁÉÍÓÚÑÜ])"#,
            in: repairedMissingSpaces,
            with: "$1\n\n"
        )
    }

    public static func normalizeLineBreaks(_ response: String) -> String {
        response
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func replacing(
        _ pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }
}

public enum IntelligenceError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidEndpoint
    case emptyPrompt
    case emptyResponse
    case invalidResponse
    case httpStatus(Int)
    case secretPassphraseRequired
    case secretPassphraseInvalid
    case secretStore
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "An OpenRouter API key is not configured."
        case .invalidEndpoint:
            return "The Ollama endpoint is invalid."
        case .emptyPrompt:
            return "The message cannot be empty."
        case .emptyResponse:
            return "The provider returned an empty response."
        case .invalidResponse:
            return "The provider returned an invalid response."
        case let .httpStatus(status):
            return "The AI provider returned HTTP status \(status)."
        case .secretPassphraseRequired:
            return "A secure local encryption key is required."
        case .secretPassphraseInvalid:
            return "The encrypted secret store could not be unlocked."
        case .secretStore:
            return "The encrypted secret store is unavailable."
        case .timedOut:
            return "The AI provider did not respond before the timeout."
        }
    }
}

public enum BatteryInsightEngine {
    public static func makeInsight(
        from snapshot: BatteryEvidenceSnapshot,
        languageCode: String = "en",
        now: Date = Date()
    ) -> BatteryInsight {
        let spanish = languageCode.lowercased().hasPrefix("es")
        var evidence: [String] = []
        var recommendations: [String] = []
        var severity: BatteryInsightSeverity = .info
        var confidence: Confidence = .medium
        var hasImmediateCriticalSignal = false
        var hasHighCyclePace = false
        var hasElevatedCyclePace = false

        if let charge = snapshot.chargePercent {
            evidence.append(spanish ? "Nivel medido: \(charge)%" : "Measured charge: \(charge)%")
            if charge <= 10 {
                severity = .critical
                hasImmediateCriticalSignal = true
                recommendations.append(spanish ? "Conecta energía pronto." : "Connect power soon.")
            } else if charge <= 20 {
                severity = maxSeverity(severity, .warning)
                recommendations.append(spanish ? "Considera conectar energía si seguirás usando el Mac." : "Consider connecting power if you will keep using the Mac.")
            }
        }

        if let health = snapshot.healthPercent {
            evidence.append(String(
                format: spanish ? "Salud calculada: %.1f%%" : "Calculated health: %.1f%%",
                health
            ))
            if health < 80 {
                severity = maxSeverity(severity, .warning)
                recommendations.append(spanish ? "La salud está por debajo del 80%; revisa la tendencia, no solo una lectura." : "Health is below 80%; review the trend rather than a single reading.")
            }
        }

        if let cycles = snapshot.cycleCount {
            if let designCycles = snapshot.designCycleCount, designCycles > 0 {
                let ratio = Double(cycles) / Double(designCycles)
                evidence.append(spanish ? "Ciclos medidos: \(cycles) de \(designCycles) de referencia" : "Measured cycles: \(cycles) of \(designCycles) design reference")
                if ratio >= 0.8 {
                    severity = maxSeverity(severity, .warning)
                    recommendations.append(spanish ? "Los ciclos acumulados son altos; ciclos y salud son señales distintas." : "Accumulated cycles are high; cycle count and health are separate signals.")
                }
            } else {
                evidence.append(spanish ? "Ciclos medidos: \(cycles)" : "Measured cycles: \(cycles)")
            }
        }

        if let usage = snapshot.cycleUsage {
            evidence.append(String(
                format: spanish
                    ? "Uso de batería estimado hoy: %.0f%% (%.2f ciclos equivalentes)"
                    : "Estimated battery use today: %.0f%% (%.2f equivalent cycles)",
                usage.todayUsagePercent,
                usage.todayEquivalentCycles
            ))
            evidence.append(spanish
                ? "Cambio medido del contador: +\(usage.todayHardwareCycleDelta) hoy, +\(usage.rolling24HourHardwareCycleDelta) en 24 h"
                : "Measured counter change: +\(usage.todayHardwareCycleDelta) today, +\(usage.rolling24HourHardwareCycleDelta) in 24h"
            )
            switch usage.comparison {
            case .lower:
                evidence.append(spanish ? "El consumo de hoy es menor que lo habitual a esta hora." : "Today's use is lower than usual at this time.")
            case .usual:
                evidence.append(spanish ? "El consumo de hoy está dentro de lo habitual a esta hora." : "Today's use is within the usual range at this time.")
            case .higher:
                evidence.append(spanish ? "El consumo de hoy es mayor que lo habitual a esta hora." : "Today's use is higher than usual at this time.")
            case .insufficientData:
                evidence.append(spanish
                    ? "Aún no hay suficientes días comparables para definir el ritmo habitual."
                    : "There are not enough comparable days yet to define the usual pace."
                )
            }

            switch usage.status {
            case .high:
                hasHighCyclePace = true
                severity = .critical
                recommendations.append(spanish
                    ? "Reduce descargas evitables si quieres bajar el ritmo; esta señal indica uso alto, no daño confirmado."
                    : "Reduce avoidable discharging if you want to lower the pace; this signal means high use, not confirmed damage."
                )
            case .elevated:
                hasElevatedCyclePace = true
                severity = maxSeverity(severity, .warning)
                recommendations.append(spanish
                    ? "Revisa el uso acumulado y la proyección semanal; salud y ritmo de ciclos siguen siendo señales distintas."
                    : "Review accumulated use and the weekly projection; health and cycle pace remain separate signals."
                )
            case .onTrack, .insufficientData:
                break
            }
        }

        if let temperature = snapshot.temperatureCelsius {
            evidence.append(String(
                format: spanish ? "Temperatura medida: %.1f °C" : "Measured temperature: %.1f °C",
                temperature
            ))
            if temperature >= 50 {
                severity = .critical
                hasImmediateCriticalSignal = true
                recommendations.append(spanish ? "Reduce la carga y deja enfriar el Mac." : "Reduce the load and let the Mac cool down.")
            } else if temperature >= 40 {
                severity = maxSeverity(severity, .warning)
                recommendations.append(spanish ? "Revisa las apps con mayor impacto mientras la temperatura siga alta." : "Review the highest-impact apps while temperature remains high.")
            }
        }

        if let dischargeRate = snapshot.dischargePercentPerMinute,
           dischargeRate >= 0.35,
           !snapshot.isCharging {
            severity = maxSeverity(severity, .warning)
            evidence.append(String(
                format: spanish ? "Descarga observada: %.2f%% por minuto" : "Observed discharge: %.2f%% per minute",
                dischargeRate
            ))
            recommendations.append(spanish ? "Revisa el historial y el impacto de las apps antes de atribuirlo a desgaste." : "Review history and app impact before attributing it to wear.")
        }

        switch snapshot.thermalState {
        case .serious:
            severity = maxSeverity(severity, .warning)
            evidence.append(spanish ? "Estado térmico: serio" : "Thermal state: serious")
        case .critical:
            severity = .critical
            hasImmediateCriticalSignal = true
            evidence.append(spanish ? "Estado térmico: crítico" : "Thermal state: critical")
        default:
            break
        }

        if let cpu = snapshot.cpuUsagePercent, cpu >= 90 {
            severity = maxSeverity(severity, .warning)
            evidence.append(String(format: spanish ? "CPU del sistema: %.0f%%" : "System CPU: %.0f%%", cpu))
        }
        if let memory = snapshot.memoryUsedPercent, memory >= 90 {
            severity = maxSeverity(severity, .warning)
            evidence.append(String(format: spanish ? "RAM del sistema: %.0f%%" : "System memory: %.0f%%", memory))
        }

        if !snapshot.processImpacts.isEmpty {
            let names = snapshot.processImpacts.prefix(3).map(\.name).joined(separator: ", ")
            evidence.append(spanish ? "Mayor impacto observado: \(names)" : "Highest observed impact: \(names)")
        }

        if evidence.isEmpty {
            confidence = .unavailable
        } else if snapshot.learningDaysObserved < 1 {
            confidence = .low
        } else if snapshot.learningDaysObserved >= 7 {
            confidence = .high
        }

        let title: String
        let summary: String
        switch severity {
        case .critical:
            if hasHighCyclePace && !hasImmediateCriticalSignal {
                title = spanish ? "Ritmo de ciclos alto" : "High cycle pace"
                summary = spanish
                    ? "Cellium midió un uso de batería alto en la ventana reciente. Esto no demuestra daño, pero sí merece ajustar el ritmo si quieres conservar ciclos."
                    : "Cellium measured high battery use in the recent window. This does not prove damage, but the pace is worth adjusting if you want to preserve cycles."
            } else {
                title = spanish ? "Atención inmediata" : "Immediate attention"
                summary = spanish ? "Hay una señal crítica medida por Cellium. Revisa los datos antes de continuar con una carga intensa." : "Cellium measured a critical signal. Review the data before continuing with a heavy workload."
            }
        case .warning:
            if hasElevatedCyclePace {
                title = spanish ? "Uso de batería elevado" : "Elevated battery use"
                summary = spanish
                    ? "El ritmo reciente está por encima del guardrail o de tu contexto habitual, sin indicar por sí solo daño de batería."
                    : "Recent use is above the guardrail or your usual context, without indicating battery damage by itself."
            } else {
                title = spanish ? "Revisión recomendada" : "Review recommended"
                summary = spanish ? "Hay señales que merecen revisión, pero no prueban por sí solas un daño de batería." : "Some signals deserve review, but they do not prove battery damage by themselves."
            }
        case .info:
            title = spanish ? "Batería estable" : "Battery looks stable"
            summary = spanish ? "Las mediciones actuales no muestran una señal importante fuera de tu contexto observado." : "Current measurements do not show an important signal outside the observed context."
        }

        return BatteryInsight(
            generatedAt: now,
            title: title,
            summary: summary,
            severity: severity,
            confidence: confidence,
            evidence: evidence,
            recommendations: recommendations,
            provider: nil
        )
    }

    private static func maxSeverity(
        _ left: BatteryInsightSeverity,
        _ right: BatteryInsightSeverity
    ) -> BatteryInsightSeverity {
        let rank: [BatteryInsightSeverity: Int] = [.info: 0, .warning: 1, .critical: 2]
        return (rank[right] ?? 0) > (rank[left] ?? 0) ? right : left
    }
}

public struct Recommendation: Codable, Equatable, Sendable {
    public let title: String
    public let explanation: String
    public let confidence: Confidence
    public let quality: SensorQuality

    public init(
        title: String,
        explanation: String,
        confidence: Confidence,
        quality: SensorQuality
    ) {
        self.title = title
        self.explanation = explanation
        self.confidence = confidence
        self.quality = quality
    }
}

public enum CelliumIntelligenceModule {
    public static let name = "CelliumIntelligence"
}
