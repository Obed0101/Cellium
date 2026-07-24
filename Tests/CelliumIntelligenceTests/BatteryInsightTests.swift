import XCTest
@testable import CelliumIntelligence
import CelliumCore

final class BatteryInsightTests: XCTestCase {
    func testLocalInsightSeparatesHealthFromCycleUse() {
        let snapshot = BatteryEvidenceSnapshot(
            chargePercent: 54,
            isCharging: false,
            externalPowerConnected: false,
            powerWatts: 12.4,
            dischargePercentPerMinute: 0.1,
            temperatureCelsius: 34,
            healthPercent: 92,
            cycleCount: 840,
            designCycleCount: 1_000,
            thermalState: .nominal,
            lowPowerModeEnabled: false,
            cpuUsagePercent: 22,
            memoryUsedPercent: 48,
            diskUsedPercent: 61,
            learningDaysObserved: 7
        )

        let insight = BatteryInsightEngine.makeInsight(from: snapshot)

        XCTAssertEqual(insight.severity, .warning)
        XCTAssertTrue(insight.evidence.contains { $0.contains("Measured cycles") })
        XCTAssertTrue(insight.recommendations.contains { $0.contains("separate signals") })
    }

    func testAssistantResponseFormatterSeparatesJoinedSentences() {
        let formatted = AssistantResponseFormatter.format(
            "Battery looks stable.Right now the Mac is discharging. Check the recent history."
        )

        XCTAssertTrue(formatted.contains("stable.\n\nRight now"))
        XCTAssertTrue(formatted.contains("discharging.\n\nCheck"))
    }

    func testAssistantResponseFormatterDecodesEscapedLineBreaks() {
        let formatted = AssistantResponseFormatter.format("First paragraph.\\nSecond paragraph.")

        XCTAssertEqual(formatted, "First paragraph.\nSecond paragraph.")
    }

    func testAssistantMarkdownParserKeepsParagraphsSeparate() {
        let formatted = AssistantResponseFormatter.format(
            "Battery looks stable.Right now the Mac is discharging."
        )

        let blocks = AssistantMarkdownParser.parse(formatted)

        XCTAssertEqual(
            blocks,
            [
                AssistantMarkdownBlock(kind: .paragraph, content: "Battery looks stable."),
                AssistantMarkdownBlock(kind: .paragraph, content: "Right now the Mac is discharging.")
            ]
        )
    }

    func testAssistantMarkdownParserRecognizesCommonBlocks() {
        let markdown = """
        # Summary

        **Measured:** [159%](https://example.com/efc)

        - First item
        2. Second item

        > Estimated, not battery damage.

        ```swift
        let cycles = 153
        ```
        """

        let blocks = AssistantMarkdownParser.parse(markdown)

        XCTAssertEqual(blocks.map(\.kind), [
            .heading(level: 1),
            .paragraph,
            .unorderedListItem,
            .orderedListItem(marker: "2."),
            .quote,
            .code(language: "swift")
        ])
        XCTAssertEqual(blocks[1].content, "**Measured:** [159%](https://example.com/efc)")
        XCTAssertEqual(blocks.last?.content, "let cycles = 153")
    }

    func testLocalInsightMarksCriticalCharge() {
        let snapshot = BatteryEvidenceSnapshot(
            chargePercent: 8,
            isCharging: false,
            externalPowerConnected: false,
            powerWatts: nil,
            dischargePercentPerMinute: nil,
            temperatureCelsius: nil,
            healthPercent: nil,
            cycleCount: nil,
            designCycleCount: nil,
            thermalState: .nominal,
            lowPowerModeEnabled: false,
            cpuUsagePercent: nil,
            memoryUsedPercent: nil,
            diskUsedPercent: nil,
            learningDaysObserved: 0
        )

        let insight = BatteryInsightEngine.makeInsight(from: snapshot)

        XCTAssertEqual(insight.severity, .critical)
        XCTAssertTrue(insight.recommendations.contains("Connect power soon."))
    }

    func testLocalInsightDoesNotCallHighCyclePaceStableOrDamaged() {
        let snapshot = evidence(
            cycleUsage: cycleSummary(
                status: .high,
                comparison: .insufficientData,
                todayEFC: 1.59,
                rollingEFC: 2.1,
                hardwareDelta: 2
            )
        )

        let insight = BatteryInsightEngine.makeInsight(from: snapshot, languageCode: "en")

        XCTAssertEqual(insight.severity, .critical)
        XCTAssertEqual(insight.title, "High cycle pace")
        XCTAssertFalse(insight.summary.localizedCaseInsensitiveContains("stable"))
        XCTAssertTrue(insight.summary.localizedCaseInsensitiveContains("not prove damage"))
        XCTAssertTrue(insight.evidence.contains { $0.contains("159%") })
        XCTAssertTrue(insight.evidence.contains { $0.contains("not enough comparable days") })
    }

    func testLocalInsightReportsDeterministicTodayComparison() {
        let snapshot = evidence(
            cycleUsage: cycleSummary(
                status: .elevated,
                comparison: .higher,
                todayEFC: 0.8,
                rollingEFC: 1.1,
                hardwareDelta: 1
            )
        )

        let insight = BatteryInsightEngine.makeInsight(from: snapshot, languageCode: "en")

        XCTAssertEqual(insight.severity, .warning)
        XCTAssertEqual(insight.title, "Elevated battery use")
        XCTAssertTrue(insight.evidence.contains("Today's use is higher than usual at this time."))
        XCTAssertTrue(insight.recommendations.contains { $0.contains("separate signals") })
    }

    func testLocalInsightUsesOnTrackForLowAbsoluteUseAbovePersonalBaseline() {
        let snapshot = evidence(
            cycleUsage: cycleSummary(
                status: .onTrack,
                comparison: .higher,
                todayEFC: 0.17,
                rollingEFC: 0.17,
                hardwareDelta: 0
            )
        )

        let insight = BatteryInsightEngine.makeInsight(from: snapshot, languageCode: "en")

        XCTAssertEqual(insight.severity, .info)
        XCTAssertEqual(insight.title, "Battery use on track")
        XCTAssertFalse(insight.summary.localizedCaseInsensitiveContains("damage"))
        XCTAssertTrue(insight.evidence.contains { $0.contains("higher than usual") })
    }

    func testOpenRouterCatalogIncludesFastBudgetAndCustomReadyModels() {
        let models = IntelligenceModelCatalog.openRouter
        let ids = Set(models.map(\.id))

        XCTAssertTrue(ids.contains("deepseek/deepseek-v4-flash"))
        XCTAssertTrue(ids.contains("xiaomi/mimo-v2.5"))
        XCTAssertTrue(ids.contains("minimax/minimax-m3"))
        XCTAssertTrue(ids.contains("openrouter/auto"))
        XCTAssertTrue(models.contains { $0.category == .budget })
        XCTAssertTrue(models.contains { $0.category == .free })
        XCTAssertNotNil(IntelligenceModelCatalog.recommendation(for: "xiaomi/mimo-v2.5"))
        XCTAssertNil(IntelligenceModelCatalog.recommendation(for: "custom/provider-model"))
    }

    private func evidence(cycleUsage: CycleUsageSummary) -> BatteryEvidenceSnapshot {
        BatteryEvidenceSnapshot(
            chargePercent: 70,
            isCharging: false,
            externalPowerConnected: false,
            powerWatts: 12,
            dischargePercentPerMinute: 0.1,
            temperatureCelsius: 31,
            healthPercent: 95.5,
            cycleCount: 153,
            designCycleCount: 1_000,
            thermalState: .nominal,
            lowPowerModeEnabled: false,
            cpuUsagePercent: 20,
            memoryUsedPercent: 50,
            diskUsedPercent: 60,
            learningDaysObserved: 2,
            cycleUsage: cycleUsage
        )
    }

    private func cycleSummary(
        status: CyclePaceStatus,
        comparison: CyclePaceComparison,
        todayEFC: Double,
        rollingEFC: Double,
        hardwareDelta: Int
    ) -> CycleUsageSummary {
        CycleUsageSummary(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            currentCycleCount: 153,
            todayEquivalentCycles: todayEFC,
            rolling24HourEquivalentCycles: rollingEFC,
            weekEquivalentCycles: rollingEFC,
            todayHardwareCycleDelta: hardwareDelta,
            rolling24HourHardwareCycleDelta: hardwareDelta,
            weekHardwareCycleDelta: hardwareDelta,
            baselineEquivalentCyclesAtCurrentTime: comparison == .insufficientData ? nil : 0.5,
            baselineDayCount: comparison == .insufficientData ? 2 : 7,
            comparison: comparison,
            projectedTodayEquivalentCycles: nil,
            projectedWeekEquivalentCycles: nil,
            weeklyBudget: nil,
            status: status,
            confidence: .medium,
            forecast: nil,
            observedSecondsToday: 7_200,
            gapSecondsToday: 0
        )
    }
}
