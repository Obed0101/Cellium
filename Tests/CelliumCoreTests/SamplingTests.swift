import XCTest
@testable import CelliumCore

final class SamplingTests: XCTestCase {
    func testModesExposeLowWakeCadences() {
        XCTAssertNil(SamplingMode.idle.interval)
        XCTAssertEqual(SamplingMode.backgroundOnAC.interval, 60)
        XCTAssertEqual(SamplingMode.backgroundOnBattery.interval, 30)
        XCTAssertEqual(SamplingMode.quickPanelVisible.interval, 15)
        XCTAssertEqual(SamplingMode.dashboardVisible.interval, 2)
        XCTAssertEqual(SamplingMode.transition.interval, 2)
        XCTAssertEqual(SamplingMode.diagnostics.interval, 1)
    }

    func testCoordinatorSamplesAndBoundsRingBuffer() async throws {
        let source = SnapshotSource(
            readBattery: { date in
                BatterySnapshot(
                    timestamp: date,
                    chargePercent: 75,
                    sourceQuality: .measured,
                    powerSourceState: .battery
                )
            },
            readSystem: { date in
                SystemSnapshot(
                    timestamp: date,
                    thermalState: .nominal,
                    lowPowerModeEnabled: true
                )
            }
        )
        let coordinator = SamplingCoordinator(source: source, ringBufferCapacity: 2)
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(1)
        let thirdDate = firstDate.addingTimeInterval(2)

        _ = await coordinator.sampleNow(at: firstDate)
        _ = await coordinator.sampleNow(at: secondDate)
        let latest = await coordinator.sampleNow(at: thirdDate)
        let buffered = await coordinator.bufferedSamples()

        let mode = await coordinator.currentMode()

        XCTAssertEqual(latest.battery.timestamp, thirdDate)
        XCTAssertEqual(buffered.count, 2)
        XCTAssertEqual(buffered.map(\.battery.timestamp), [secondDate, thirdDate])
        XCTAssertEqual(mode, .idle)
    }

    func testIntervalOverrideAppliesToForegroundModes() async {
        let source = SnapshotSource(
            readBattery: { date in BatterySnapshot(timestamp: date, chargePercent: 50) },
            readSystem: { date in
                SystemSnapshot(timestamp: date, thermalState: .nominal, lowPowerModeEnabled: false)
            }
        )
        let coordinator = SamplingCoordinator(source: source)

        await coordinator.setIntervalOverride(7)
        await coordinator.setMode(.quickPanelVisible)

        let interval = await coordinator.currentInterval()
        XCTAssertEqual(interval, 7)
        await coordinator.stop()
    }

    func testModeCanChangeWithoutSamplingInIdle() async {
        let source = SnapshotSource(
            readBattery: { date in BatterySnapshot(timestamp: date, chargePercent: 50) },
            readSystem: { date in
                SystemSnapshot(timestamp: date, thermalState: .nominal, lowPowerModeEnabled: false)
            }
        )
        let coordinator = SamplingCoordinator(source: source, ringBufferCapacity: 1)

        await coordinator.setMode(.backgroundOnBattery)
        let mode = await coordinator.currentMode()
        let buffered = await coordinator.bufferedSamples()

        XCTAssertEqual(mode, .backgroundOnBattery)
        XCTAssertEqual(buffered, [])

        await coordinator.stop()
    }
}
