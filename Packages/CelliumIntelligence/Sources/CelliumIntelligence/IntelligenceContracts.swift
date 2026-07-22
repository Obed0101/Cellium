import Foundation
import CelliumCore

public enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low
    case unavailable
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
