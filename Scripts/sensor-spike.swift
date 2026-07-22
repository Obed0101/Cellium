import Foundation
import IOKit.ps

private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private func safeValue(_ value: Any?) -> Any? {
    guard let value else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number }
    return nil
}

private func safeFields(from description: [String: Any]) -> [String: Any] {
    let allowedKeys = [
        "Type",
        "Name",
        "Power Source State",
        "Current Capacity",
        "Max Capacity",
        "Design Capacity",
        "Nominal Charge Capacity",
        "Voltage",
        "Amperage",
        "InstantAmperage",
        "Is Charging",
        "Fully Charged",
        "External Connected",
        "Time to Empty",
        "Time to Full",
        "Battery Provides Time Remaining"
    ]

    var result: [String: Any] = [:]
    for key in allowedKeys {
        if let value = safeValue(description[key]) {
            result[key] = value
        }
    }
    return result
}

#if arch(arm64)
let architecture = "arm64"
#elseif arch(x86_64)
let architecture = "x86_64"
#else
let architecture = "unknown"
#endif

let processInfo = ProcessInfo.processInfo
var output: [String: Any] = [
    "timestamp": isoFormatter.string(from: Date()),
    "architecture": architecture,
    "thermalState": String(describing: processInfo.thermalState),
    "lowPowerModeEnabled": processInfo.isLowPowerModeEnabled,
    "readOnly": true
]

let powerSourceInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo).takeRetainedValue() as [CFTypeRef]
var sources: [[String: Any]] = []

for source in powerSources {
    guard let unmanagedDescription = IOPSGetPowerSourceDescription(powerSourceInfo, source),
          let description = unmanagedDescription.takeUnretainedValue() as? [String: Any] else {
        continue
    }
    sources.append(safeFields(from: description))
}

output["powerSources"] = sources

let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write(Data("\n".utf8))
