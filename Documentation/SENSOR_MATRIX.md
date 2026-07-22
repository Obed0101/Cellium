# Cellium Sensor Matrix

**Discovery date:** 2026-07-21
**Host:** Apple Silicon (`arm64`)
**Important:** This document records one read-only local spike. It is not a compatibility promise for every Mac.

## Environment

| Signal | Observed value | Source |
|---|---|---|
| Architecture | `arm64` | `uname -m`, Swift target info |
| macOS | `26.5.2` (`25F84`) | `sw_vers` |
| Xcode | `26.3` (`17C529`) | `xcodebuild -version` |
| Swift | Apple Swift `6.2.4` | `swift --version` |
| Swift target | `arm64-apple-macosx26.0` | `swiftc -print-target-info` |
| macOS SDK | `26.2` | `xcrun --sdk macosx --show-sdk-version` |
| Simulator runtimes | none listed | `xcrun simctl list runtimes` |

## Read-only spike

Script: `Scripts/sensor-spike.swift`

Compilation and execution:

```bash
swiftc Scripts/sensor-spike.swift \
  -o /tmp/cellium-sensor-spike \
  -framework IOKit \
  -framework Foundation
/tmp/cellium-sensor-spike
```

The script uses `IOKit.ps` and `ProcessInfo`. It only reads public power-source descriptions and emits a filtered JSON snapshot. It intentionally excludes serials and arbitrary I/O Registry properties.

### Power source result

```json
{
  "architecture": "arm64",
  "lowPowerModeEnabled": true,
  "powerSources": [
    {
      "Battery Provides Time Remaining": true,
      "Current Capacity": 82,
      "Is Charging": false,
      "Max Capacity": 100,
      "Name": "InternalBattery-0",
      "Power Source State": "Battery Power",
      "Time to Empty": 291,
      "Type": "InternalBattery"
    }
  ],
  "readOnly": true,
  "thermalState": "NSProcessInfoThermalState(rawValue: 0)"
}
```

Interpretation:

- Battery is at **82%** according to the power-source API.
- The Mac is on battery and not charging.
- Low Power Mode is active.
- Thermal state is raw value `0`, which corresponds to nominal in the current SDK.
- Estimated time to empty is **291 minutes** from this source.
- No AC adapter is currently reported.

### Follow-up comparison with macOS UI

A later read-only sample returned `Current Capacity: 78`, and `pmset -g batt` also returned `78%`. The screenshot supplied by the user shows `79%`, which is consistent with the value having changed between the screenshot and the sample; the Mac was discharging. The earlier spike samples were `82%` and `81%`, so the percentage is moving normally over time.

These are three different concepts that Cellium must keep separate:

1. **Current charge / SOC:** `CurrentCapacity / MaxCapacity` — the percentage shown by the macOS menu, currently 78–79% around the observed samples.
2. **Battery health:** `NominalChargeCapacity / DesignCapacity` — a calculated capacity-retention estimate, approximately 96.4% in the follow-up sample.
3. **Raw gauge capacities:** `AppleRawCurrentCapacity` and `AppleRawMaxCapacity` — diagnostic fields whose ratio must not be presented as either SOC or health without device-specific validation.

The macOS label `Using Significant Energy: Ghostty` is a qualitative system indication, not an exact per-process watt measurement. Cellium must not turn it into a precise Ghostty power claim.

## Filtered AppleSmartBattery fields

A separate `ioreg -r -c AppleSmartBattery -w 0` read was filtered before output. No serial or raw registry dump was emitted.

| Field | Observed value | Interpretation / status |
|---|---:|---|
| `BatteryInstalled` | Yes | Available |
| `DeviceName` | `bq40z651` | Hardware gauge identifier; do not show by default |
| `DesignCapacity` | 6249 | Raw capacity field; unit/device interpretation must remain documented |
| `NominalChargeCapacity` | 6039 | Raw capacity field |
| `AppleRawMaxCapacity` | 5887 | Raw capacity field |
| `AppleRawCurrentCapacity` | 4558 | Raw capacity field |
| `CurrentCapacity` | 82 | Percentage-style value in this registry |
| `MaxCapacity` | 100 | Percentage-style maximum in this registry |
| `CycleCount` | 149 | Available |
| `DesignCycleCount9C` | 1000 | Available |
| `Voltage` | 12343 | Approximately 12.343 V if interpreted as mV |
| `Amperage` | 18446744073709551027 | Unsigned representation of signed `-589` mA; normalize defensively |
| `InstantAmperage` | 18446744073709551027 | Same signed conversion issue |
| `Temperature` | 3069 | Approximately 30.69 °C if centi-Celsius; validate per device |
| `VirtualTemperature` | 3369 | Approximately 33.69 °C if centi-Celsius; validate per device |
| `IsCharging` | No | Available |
| `FullyCharged` | No | Available |
| `ExternalConnected` | No | Available |
| `AtCriticalLevel` | No | Available |
| `AvgTimeToEmpty` | 329 | Minutes-style estimate |
| `AvgTimeToFull` | 65535 | Sentinel; must be rejected as unavailable |

A preliminary health calculation from `NominalChargeCapacity / DesignCapacity` is approximately **96.6%**, but it is a calculated value and must not be treated as a production health reading until repeated snapshots and device-specific units are validated.

The raw amperage sign cannot be copied directly into UI. This device reports a negative signed current while discharging. Cellium must normalize one internal convention and label its source/quality.

## Notification API smoke check

The following notification names compile on the current SDK without triggering sleep or changing power state:

- `NSWorkspaceWillSleepNotification`
- `NSWorkspaceDidWakeNotification`
- `NSProcessInfoPowerStateDidChange`

Actual sleep/wake observation is deferred to integration tests because the spike must not force a user-visible sleep or wake action. The production coordinator will subscribe to these events and record a gap rather than reconstruct missing samples.

## Capability matrix

| Capability | Current result | MVP status | Fallback |
|---|---|---|---|
| IOPowerSources snapshot | Available | Include | `unavailable` if list missing |
| AppleSmartBattery fields | Available through filtered registry read | Include defensively | Per-field unavailable |
| Battery health | Calculable from raw fields | Include with provenance | No health value if invalid |
| Cycle count | Available | Include | `unavailable` |
| Battery temperature | Available, unit needs validation | Include after range checks | `unavailable` |
| Voltage/current | Available, signed conversion required | Include after normalization | Magnitude unavailable |
| Thermal state | Available, nominal now | Include | No heuristic alarm |
| Low Power Mode | Available and active now | Include | Default cadence |
| Sleep/wake notifications | API names compile; not forced | Integrate later | Record gap on observed events |
| SMC PPBR/PDTR/VD0R | Not validated in this spike | Optional | Never block MVP |
| Exact watts per process | No public universal source | Never claim | Estimated ranges or unavailable |
| WeatherKit | Not enabled | Optional later | Zero network by default |
| Charge-limit Shortcut | Not executed | Optional later | Open Battery Settings/guidance |

## Safety result

- No root was requested.
- No SMC write was performed.
- No power setting was changed.
- No sleep/wake action was forced.
- The spike process exited after printing the snapshot.
- Raw serial data was intentionally excluded from output.

## Next discovery gate

Before T07/T08 implementation, repeat the snapshot on the target Mac after reconnecting AC and after a controlled power transition. Validate signed-current conversion, health units, temperature units and the availability of any SMC power keys without adding writes or privileged helpers.
