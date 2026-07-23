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
}
