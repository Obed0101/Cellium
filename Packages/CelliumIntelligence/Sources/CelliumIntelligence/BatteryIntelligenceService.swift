import Foundation

public actor BatteryIntelligenceService {
    private struct ProviderMessage: Codable, Sendable {
        let role: String
        let content: String
    }

    private struct OpenRouterRequest: Encodable {
        let model: String
        let messages: [ProviderMessage]
        let stream: Bool
    }

    private struct OpenRouterResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct OllamaRequest: Encodable {
        let model: String
        let messages: [ProviderMessage]
        let stream: Bool
    }

    private struct OllamaResponse: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    private struct ActionDecision: Sendable {
        let required: Bool
        let message: String?
        let displayResponse: String
    }

    private let encryptedSecrets: EncryptedSecretStore
    private let installationPassphraseStore: LocalInstallationSecretStore
    private let session: URLSession
    private var secretPassphrase: String?

    public init(
        encryptedSecrets: EncryptedSecretStore = EncryptedSecretStore(),
        installationPassphraseStore: LocalInstallationSecretStore = LocalInstallationSecretStore(),
        session: URLSession = .shared
    ) {
        self.encryptedSecrets = encryptedSecrets
        self.installationPassphraseStore = installationPassphraseStore
        self.session = session
        self.secretPassphrase = nil
    }

    public func unlockAPIKey(for provider: IntelligenceProvider) throws -> Bool {
        return try secret(for: provider) != nil
    }

    public func hasAPIKey(for provider: IntelligenceProvider) -> Bool {
        guard let secret = try? secret(for: provider) else { return false }
        return !secret.isEmpty
    }

    public func saveAPIKey(_ value: String, for provider: IntelligenceProvider) throws {
        let secretPassphrase = try ensureSecretPassphrase()
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            try encryptedSecrets.deleteSecret(for: provider, passphrase: secretPassphrase)
        } else {
            try encryptedSecrets.setSecret(key, for: provider, passphrase: secretPassphrase)
        }
    }

    public func deleteAPIKey(for provider: IntelligenceProvider) throws {
        let secretPassphrase = try ensureSecretPassphrase()
        try encryptedSecrets.deleteSecret(for: provider, passphrase: secretPassphrase)
    }

    private func secret(for provider: IntelligenceProvider) throws -> String? {
        let secretPassphrase = try ensureSecretPassphrase()
        if let secret = try encryptedSecrets.secret(for: provider, passphrase: secretPassphrase),
           !secret.isEmpty {
            return secret
        }

        return nil
    }

    private func ensureSecretPassphrase() throws -> String {
        if let secretPassphrase, !secretPassphrase.isEmpty {
            return secretPassphrase
        }
        let generated = try installationPassphraseStore.secret()
        secretPassphrase = generated
        return generated
    }

    public func validateProvider(_ configuration: IntelligenceConfiguration) async throws {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw IntelligenceError.emptyPrompt }

        switch configuration.provider {
        case .openRouter:
            guard let key = try secret(for: .openRouter), !key.isEmpty else {
                throw IntelligenceError.missingAPIKey
            }
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            try validate(response)

        case .ollama:
            guard let baseURL = configuration.ollamaURL,
                  var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
                  components.scheme != nil,
                  components.host != nil else {
                throw IntelligenceError.invalidEndpoint
            }
            let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = basePath.isEmpty
                ? "/api/tags"
                : (basePath.hasSuffix("api/tags") ? "/\(basePath)" : "/\(basePath)/api/tags")
            guard let endpoint = components.url else { throw IntelligenceError.invalidEndpoint }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            let (_, response) = try await session.data(for: request)
            try validate(response)
        }
    }

    public func localInsight(
        for evidence: BatteryEvidenceSnapshot,
        languageCode: String
    ) -> BatteryInsight {
        BatteryInsightEngine.makeInsight(from: evidence, languageCode: languageCode)
    }

    public func generateInsight(
        from evidence: BatteryEvidenceSnapshot,
        configuration: IntelligenceConfiguration,
        languageCode: String
    ) async throws -> BatteryInsight {
        let result = try await generateAnalysis(
            from: evidence,
            configuration: configuration,
            languageCode: languageCode
        )
        return result.insight
    }

    public func generateAnalysis(
        from evidence: BatteryEvidenceSnapshot,
        configuration: IntelligenceConfiguration,
        languageCode: String
    ) async throws -> IntelligenceAnalysisResult {
        let local = BatteryInsightEngine.makeInsight(from: evidence, languageCode: languageCode)
        guard configuration.enabled else {
            return IntelligenceAnalysisResult(
                insight: local,
                prompt: "",
                response: local.summary
            )
        }

        let messages = [
            ProviderMessage(role: "system", content: systemPrompt(languageCode: languageCode)),
            ProviderMessage(role: "user", content: summaryPrompt(for: evidence, localInsight: local, languageCode: languageCode))
        ]
        let response = AssistantResponseFormatter.format(
            try await completeWithTimeout(configuration: configuration, messages: messages)
        )
        let actionDecision = parseActionDecision(response, evidence: evidence)
        var recommendations = local.recommendations
        if actionDecision.required, let actionMessage = actionDecision.message {
            recommendations.append(actionMessage)
        }
        let insight = BatteryInsight(
            generatedAt: Date(),
            title: local.title,
            summary: actionDecision.displayResponse,
            severity: local.severity,
            confidence: local.confidence,
            evidence: local.evidence,
            recommendations: recommendations,
            provider: configuration.provider
        )
        return IntelligenceAnalysisResult(
            insight: insight,
            prompt: transcript(for: messages),
            response: actionDecision.displayResponse,
            actionRequired: actionDecision.required,
            actionMessage: actionDecision.message
        )
    }

    public func chat(
        message: String,
        history: [AgentChatMessage],
        evidence: BatteryEvidenceSnapshot,
        configuration: IntelligenceConfiguration,
        languageCode: String
    ) async throws -> String {
        try await chatAnalysis(
            message: message,
            history: history,
            evidence: evidence,
            configuration: configuration,
            languageCode: languageCode
        ).response
    }

    public func chatAnalysis(
        message: String,
        history: [AgentChatMessage],
        evidence: BatteryEvidenceSnapshot,
        configuration: IntelligenceConfiguration,
        languageCode: String
    ) async throws -> IntelligenceChatResult {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw IntelligenceError.emptyPrompt }

        let responseLanguageCode = languageCode.lowercased().hasPrefix("es") ? "es" : "en"
        let localInsight = BatteryInsightEngine.makeInsight(from: evidence, languageCode: responseLanguageCode)
        var messages = [
            ProviderMessage(role: "system", content: systemPrompt(languageCode: responseLanguageCode)),
            ProviderMessage(role: "system", content: evidencePrompt(for: evidence, localInsight: localInsight))
        ]
         messages.append(contentsOf: history.suffix(10).map {

            ProviderMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
        })
        messages.append(ProviderMessage(role: "user", content: trimmedMessage))
        let response = AssistantResponseFormatter.format(
            try await completeWithTimeout(configuration: configuration, messages: messages)
        )
        return IntelligenceChatResult(
            languageCode: responseLanguageCode,
            prompt: transcript(for: messages),
            response: response
        )
    }

    private func complete(
        configuration: IntelligenceConfiguration,
        messages: [ProviderMessage]
    ) async throws -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw IntelligenceError.emptyPrompt }

        switch configuration.provider {
        case .openRouter:
            guard let key = try secret(for: .openRouter), !key.isEmpty else {
                throw IntelligenceError.missingAPIKey
            }
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("Cellium", forHTTPHeaderField: "X-Title")
            request.httpBody = try JSONEncoder().encode(
                OpenRouterRequest(model: model, messages: messages, stream: false)
            )
            let (data, response) = try await session.data(for: request)
            try validate(response)
            let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw IntelligenceError.emptyResponse
            }
            return content

        case .ollama:
            guard let baseURL = configuration.ollamaURL,
                  var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw IntelligenceError.invalidEndpoint
            }
            let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = basePath.isEmpty
                ? "/api/chat"
                : (basePath.hasSuffix("api/chat") ? "/\(basePath)" : "/\(basePath)/api/chat")
            guard let endpoint = components.url else { throw IntelligenceError.invalidEndpoint }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                OllamaRequest(model: model, messages: messages, stream: false)
            )
            let (data, response) = try await session.data(for: request)
            try validate(response)
            let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
            guard let content = decoded.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw IntelligenceError.emptyResponse
            }
            return content
        }
    }

    private func completeWithTimeout(
        configuration: IntelligenceConfiguration,
        messages: [ProviderMessage]
    ) async throws -> String {
        let timeoutNanoseconds: UInt64 = configuration.provider == .ollama
            ? 130_000_000_000
            : 75_000_000_000

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.complete(configuration: configuration, messages: messages)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw IntelligenceError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw IntelligenceError.timedOut
            }
            return result
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IntelligenceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw IntelligenceError.httpStatus(httpResponse.statusCode)
        }
    }

    private func systemPrompt(languageCode: String) -> String {
        let language = languageCode.lowercased().hasPrefix("es") ? "Spanish" : "English"
        return """
        You are Cellium's battery evidence assistant. Answer in \(language). Use only the measured context supplied by Cellium, which may include the Mac model and macOS version, the app version, the current local date/time and timezone, current outdoor weather, current battery/system readings, an estimated weekly computer-activity profile, local learning, and deterministic cycle-usage analysis. Distinguish measured facts, estimates, and explanations. Hardware cycle count, estimated equivalent full cycles (EFC), and battery health are separate signals. Battery use can exceed 100% when more than one full-capacity equivalent is discharged; never clamp or reinterpret that value as charge level. Do not infer battery damage, wear, or a required replacement unless the evidence supports that exact claim. Treat Cellium's cycleUsage status and comparison as authoritative, and never claim use is usual when comparison is insufficientData. If batteryUsePausedByExternalPower is true, describe the EFC value as accumulated historical use and do not call it an active discharge. Treat the usage profile as an estimate from CPU and memory activity, not proof that a person was actively using the computer. Treat weather as environmental context, not proof of battery causation. Process names may be anonymized labels such as `application-1`; never guess their real identity. If evidence is missing, say so. Never request secrets or passwords.

        Format every response for a chat bubble with real Markdown. Use blank lines between paragraphs, put each bullet on its own line, and always include a space after sentence-ending punctuation before the next word. Never join separate sentences or sections, for example never write `stable.Right`; write `stable.` followed by a new paragraph. Keep the response concise and practical.
        """
    }

    private func summaryPrompt(
        for evidence: BatteryEvidenceSnapshot,
        localInsight: BatteryInsight,
        languageCode: String
    ) -> String {
        let language = languageCode.lowercased().hasPrefix("es") ? "Spanish" : "English"
        return """
        In \(language), summarize the current battery state in 2-4 short paragraphs. Mention the local time only when it helps explain the usage window, and use usage.averageActiveHoursPerDay and usage.hourlyProfile to describe the user's estimated normal computer-activity hours when available. Mention the most relevant measured facts, whether today's consumption is lower, usual, or higher only when cycleUsage.comparison supports that exact comparison, and one practical next step. Keep the distinction between battery health, measured hardware cycles, estimated equivalent cycles, and recent discharge explicit. Use the Mac, weather, timezone, weekly learning, and usage context when available. If weeklyLearning.observedDays is below 7, do not infer a general routine; clearly label the usage profile as provisional too. A deterministic cycleUsage.status of high can still require action without seven learning days; describe it as high throughput, never as confirmed damage.

        At the very end, on two separate lines, emit this machine-readable decision and keep it out of the prose:
        CELLIUM_ACTION_NEEDED: yes or no
        CELLIUM_ACTION: one short imperative action for the user, or none
        Set yes only when at least 7 observed learning days show a concrete pattern that requires human action, or when deterministic cycleUsage.status is high. Otherwise set no and none.

        Structured evidence:
        \(encoded(evidence))

        Deterministic local interpretation:
        title=\(localInsight.title)
        severity=\(localInsight.severity.rawValue)
        confidence=\(localInsight.confidence.rawValue)
        evidence=\(localInsight.evidence.joined(separator: " | "))
        """
    }

    private func evidencePrompt(
        for evidence: BatteryEvidenceSnapshot,
        localInsight: BatteryInsight
    ) -> String {
        """
        Current Cellium evidence follows. Treat it as the source of truth and do not invent values. The context can include the Mac model, macOS, app version, local time and timezone, current weather, estimated computer-activity hours, local learning, and deterministic cycle usage. Use learning and usage context to explain general patterns only when enough days are present. You may report an absolute high cycle pace without that baseline when cycleUsage.status is high. Never equate high throughput with confirmed battery damage, and never infer a person's exact activity from CPU or memory alone.
        \(encoded(evidence))
        Local interpretation: \(localInsight.summary)
        """
    }

    private func parseActionDecision(
        _ response: String,
        evidence: BatteryEvidenceSnapshot
    ) -> ActionDecision {
        let markerPrefix = "cellium_action_needed:"
        let actionPrefix = "cellium_action:"
        var requested = false
        var actionMessage: String?
        var foundMarker = false
        var displayLines: [String] = []

        for rawLine in response.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = line
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "*", with: "")
                .lowercased()
            if normalized.hasPrefix(markerPrefix) {
                foundMarker = true
                let value = normalized.dropFirst(markerPrefix.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                requested = value.hasPrefix("yes") || value.hasPrefix("true") || value.hasPrefix("sí")
                continue
            }
            if normalized.hasPrefix(actionPrefix) {
                foundMarker = true
                let valueStart = line.index(line.startIndex, offsetBy: min(actionPrefix.count, line.count))
                let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedValue = value.lowercased()
                if !value.isEmpty,
                   normalizedValue != "none",
                   normalizedValue != "ninguna",
                   normalizedValue != "ninguno" {
                    actionMessage = String(value)
                }
                continue
            }
            displayLines.append(rawLine)
        }

        let eligible = evidence.learningDaysObserved >= 7
            || evidence.cycleUsage?.isActionableHighPace == true
        let required = eligible && requested && actionMessage != nil
        let cleanedResponse = foundMarker
            ? displayLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            : response
        return ActionDecision(
            required: required,
            message: required ? actionMessage : nil,
            displayResponse: cleanedResponse.isEmpty ? response : cleanedResponse
        )
    }

    private func transcript(for messages: [ProviderMessage]) -> String {
        messages.map { "[\($0.role)]\n\($0.content)" }.joined(separator: "\n\n")
    }

    private func encoded(_ evidence: BatteryEvidenceSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(evidence),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return value
    }
}
