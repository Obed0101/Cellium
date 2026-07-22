import XCTest
@testable import CelliumCore

final class SessionsTests: XCTestCase {
    func testChargingSessionCompletesWhenPowerSourceChanges() {
        var tracker = BatterySessionTracker(maximumContinuityGap: 300)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let started = tracker.ingest(sample(at: start, charge: 50, charging: true, externalPower: true))
        let continued = tracker.ingest(sample(at: start.addingTimeInterval(60), charge: 51, charging: true, externalPower: true))
        let switched = tracker.ingest(sample(at: start.addingTimeInterval(120), charge: 51, charging: false, externalPower: false))
        let finished = tracker.finish(at: start.addingTimeInterval(180))

        guard case let .started(session) = started.first else {
            return XCTFail("Expected a charging session to start")
        }
        XCTAssertEqual(session.kind, .charging)
        XCTAssertEqual(session.startChargePercent, 50)
        XCTAssertEqual(continued, [])
        XCTAssertEqual(switched.count, 2)
        guard case let .completed(completed) = switched[0] else {
            return XCTFail("Expected the charging session to complete")
        }
        XCTAssertEqual(completed.kind, .charging)
        XCTAssertEqual(completed.sampleCount, 2)
        XCTAssertEqual(completed.endChargePercent, 51)
        guard case let .started(discharging) = switched[1] else {
            return XCTFail("Expected a discharge session to start")
        }
        XCTAssertEqual(discharging.kind, .discharging)
        XCTAssertEqual(finished.count, 1)
    }

    func testConnectedPowerWithoutChargingIsDeficit() {
        var tracker = BatterySessionTracker()
        let events = tracker.ingest(
            sample(
                at: Date(timeIntervalSince1970: 1_700_000_000),
                charge: 80,
                charging: false,
                externalPower: true
            )
        )

        guard case let .started(session) = events.first else {
            return XCTFail("Expected a deficit session to start")
        }
        XCTAssertEqual(session.kind, .connectedDeficit)
    }

    func testClockRollbackDoesNotMutateActiveSession() {
        var tracker = BatterySessionTracker()
        let start = Date(timeIntervalSince1970: 1_700_000_100)

        _ = tracker.ingest(sample(at: start, charge: 70, charging: false, externalPower: false))
        let rollbackEvents = tracker.ingest(
            sample(
                at: start.addingTimeInterval(-60),
                charge: 69,
                charging: false,
                externalPower: false
            )
        )
        let finished = tracker.finish(at: start.addingTimeInterval(30))

        XCTAssertEqual(rollbackEvents, [])
        guard case let .completed(session) = finished.first else {
            return XCTFail("Expected the original session to finish")
        }
        XCTAssertEqual(session.sampleCount, 1)
        XCTAssertEqual(session.endChargePercent, 70)
        XCTAssertEqual(session.endedAt, start.addingTimeInterval(30))
    }

    func testLongGapProducesSleepGapWithoutReconstructingSamples() {
        var tracker = BatterySessionTracker(maximumContinuityGap: 300)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        _ = tracker.ingest(sample(at: start, charge: 60, charging: false, externalPower: false))

        let events = tracker.ingest(
            sample(
                at: start.addingTimeInterval(600),
                charge: 59,
                charging: false,
                externalPower: false
            )
        )

        XCTAssertEqual(events.count, 3)
        guard case let .completed(session) = events[0],
              case let .completed(gap) = events[1],
              case let .started(resumed) = events[2] else {
            return XCTFail("Expected completed session, sleep gap, and resumed session")
        }
        XCTAssertEqual(session.kind, .discharging)
        XCTAssertEqual(session.sampleCount, 1)
        XCTAssertEqual(gap.kind, .sleepGap)
        XCTAssertEqual(gap.startedAt, start)
        XCTAssertEqual(gap.endedAt, start.addingTimeInterval(600))
        XCTAssertEqual(gap.startChargePercent, 60)
        XCTAssertEqual(gap.endChargePercent, 59)
        XCTAssertEqual(gap.sampleCount, 0)
        XCTAssertEqual(resumed.kind, .discharging)
        XCTAssertEqual(resumed.startChargePercent, 59)
    }

    private func sample(
        at date: Date,
        charge: Int,
        charging: Bool,
        externalPower: Bool
    ) -> BatterySample {
        BatterySample(
            battery: BatterySnapshot(
                timestamp: date,
                chargePercent: charge,
                isCharging: charging,
                externalPowerConnected: externalPower,
                sourceQuality: .measured,
                powerSourceState: externalPower ? .adapter : .battery
            )
        )
    }
}
