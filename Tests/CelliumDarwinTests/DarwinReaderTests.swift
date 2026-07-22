import XCTest
@testable import CelliumCore
@testable import CelliumDarwin

final class DarwinReaderTests: XCTestCase {
    func testBatteryReaderReturnsSafeSnapshotWithoutPrivilegedAccess() {
        let snapshot = IOKitBatteryReader().readSnapshot()

        if let charge = snapshot.chargePercent {
            XCTAssertTrue((0...100).contains(charge))
        }
        if let temperature = snapshot.temperatureCelsius {
            XCTAssertTrue((-20...100).contains(temperature))
        }
        XCTAssertFalse(snapshot.diagnostics.contains("root_required"))
    }

    func testSystemStateReaderReturnsSupportedState() {
        let reader = SystemStateReader()
        let snapshot = reader.readSnapshot()
        XCTAssertTrue(ThermalState.allCases.contains(snapshot.thermalState))
        if let readRate = snapshot.diskReadBytesPerSecond {
            XCTAssertTrue(readRate.isFinite && readRate >= 0)
        }
        if let writeRate = snapshot.diskWriteBytesPerSecond {
            XCTAssertTrue(writeRate.isFinite && writeRate >= 0)
        }
    }

    func testSMCFallbackNeverReportsPower() {
        XCTAssertNil(UnavailableSMCPowerReader().readBatteryPowerWatts())
        XCTAssertFalse(DarwinModule.smcWriteSupported)
    }
}
