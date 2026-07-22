import Foundation
import CelliumCore

public enum AutomationAction: Codable, Equatable, Sendable {
    case noAction
    case openBatterySettings
    case runAllowlistedShortcut(name: String, limit: Int)
}

public struct AutomationPolicy: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let allowedLimits: Set<Int>

    public init(enabled: Bool = false, allowedLimits: Set<Int> = [80, 85, 90, 95, 100]) {
        self.enabled = enabled
        self.allowedLimits = allowedLimits.intersection([80, 85, 90, 95, 100])
    }
}

public enum CelliumAutomationModule {
    public static let name = "CelliumAutomation"
}
