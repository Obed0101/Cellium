import Foundation
import CelliumCore
import CelliumStore

struct CycleBudgetSnapshot: Equatable, Sendable {
    let summary: CycleUsageSummary
    let quarterHourBuckets: [StoredCycleUsageBucket]
    let dailyBuckets: [StoredCycleUsageBucket]
}

actor CycleBudgetCoordinator {
    func load(
        from store: SQLiteStore,
        currentCycleCount: Int?,
        configuration: CyclePlanConfiguration,
        now: Date = Date()
    ) async throws -> CycleBudgetSnapshot {
        let quarterHourSince = now.addingTimeInterval(-31 * 86_400)
        async let quarterHourRequest = store.fetchCycleUsage(
            resolution: .quarterHour,
            since: quarterHourSince,
            limit: 3_500
        )
        async let dailyRequest = store.fetchCycleUsage(
            resolution: .day,
            limit: 10_000
        )
        let fetchedQuarterHours = try await quarterHourRequest
        let fetchedDays = try await dailyRequest
        let quarterHourBuckets = Array(fetchedQuarterHours.reversed())
        let dailyBuckets = Array(fetchedDays.reversed())
        let summary = CycleBudgetEngine.summarize(
            quarterHourBuckets: quarterHourBuckets,
            dailyBuckets: dailyBuckets,
            currentCycleCount: currentCycleCount,
            configuration: configuration,
            now: now
        )
        return CycleBudgetSnapshot(
            summary: summary,
            quarterHourBuckets: quarterHourBuckets,
            dailyBuckets: dailyBuckets
        )
    }
}
