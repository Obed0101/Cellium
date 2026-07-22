import XCTest
@testable import CelliumCore

final class BatteryMathTests: XCTestCase {
    func testHealthUsesNominalAndDesignCapacity() {
        guard let health = BatteryMath.healthPercent(nominalChargeCapacityMAh: 6_022, designCapacityMAh: 6_249) else {
            return XCTFail("Expected a valid health calculation")
        }
        XCTAssertEqual(health, 96.367418786, accuracy: 0.001)
    }

    func testHealthRejectsMissingOrZeroCapacity() {
        XCTAssertNil(BatteryMath.healthPercent(nominalChargeCapacityMAh: nil, designCapacityMAh: 6_249))
        XCTAssertNil(BatteryMath.healthPercent(nominalChargeCapacityMAh: 0, designCapacityMAh: 6_249))
        XCTAssertNil(BatteryMath.healthPercent(nominalChargeCapacityMAh: 6_249, designCapacityMAh: 0))
    }

    func testTemperatureConvertsCentiCelsius() {
        guard let temperature = BatteryMath.temperatureCelsius(fromCentiCelsius: 3_070) else {
            return XCTFail("Expected a valid temperature")
        }
        XCTAssertEqual(temperature, 30.70, accuracy: 0.001)
        XCTAssertNil(BatteryMath.temperatureCelsius(fromCentiCelsius: 20_000))
    }

    func testSignedCurrentPreservesTwoComplementValue() {
        let raw: UInt64 = 18_446_744_073_709_550_227
        XCTAssertEqual(BatteryMath.signedMilliamps(fromRawUnsigned: raw), -1_389)
    }

    func testBatteryPowerNormalizesDischargeSign() {
        let watts = BatteryMath.batteryPowerWatts(
            voltageMillivolts: 12_343,
            signedAmperageMilliamps: -589
        )
        guard let watts else {
            return XCTFail("Expected a valid power calculation")
        }
        XCTAssertEqual(watts, 7.270027, accuracy: 0.001)
    }

    func testTimeSentinelIsUnavailable() {
        XCTAssertNil(BatteryMath.rejectTimeSentinel(65_535))
        XCTAssertEqual(BatteryMath.rejectTimeSentinel(255), 255)
    }
}

final class SnapshotValidatorTests: XCTestCase {
    func testInvalidFieldsBecomeUnavailableAndProduceDiagnostics() {
        let snapshot = BatterySnapshot(
            chargePercent: 120,
            temperatureCelsius: 150,
            timeToFullMinutes: 65_535,
            sourceQuality: .measured
        )

        let sanitized = SnapshotValidator().sanitize(snapshot)

        XCTAssertNil(sanitized.chargePercent)
        XCTAssertNil(sanitized.temperatureCelsius)
        XCTAssertNil(sanitized.timeToFullMinutes)
        XCTAssertTrue(sanitized.diagnostics.contains("charge_percent_out_of_range"))
        XCTAssertTrue(sanitized.diagnostics.contains("temperature_out_of_range"))
        XCTAssertTrue(sanitized.diagnostics.contains("time_to_full_sentinel"))
    }
}
