import Foundation
import Darwin
import IOKit
import IOKit.storage
import CelliumCore

public final class SystemStateReader: @unchecked Sendable {
    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64

        var total: UInt64 {
            user &+ system &+ idle &+ nice
        }
    }

    private struct DiskIOCounters {
        let readBytes: UInt64
        let writeBytes: UInt64
    }

    private let lock = NSLock()
    private var previousCPUTicks: CPUTicks?
    private var previousDiskIO: (counters: DiskIOCounters, date: Date)?

    public init() {}

    public func readSnapshot(at date: Date = Date()) -> SystemSnapshot {
        let processInfo = ProcessInfo.processInfo
        let memory = readMemoryMetrics()
        let disk = readDiskMetrics()
        let diskIO = readDiskIO(at: date)
        return SystemSnapshot(
            timestamp: date,
            thermalState: thermalState(processInfo.thermalState),
            lowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
            cpuUsagePercent: readCPUUsagePercent(),
            memoryUsedPercent: memory?.usedPercent,
            memoryUsedBytes: memory?.usedBytes,
            memoryTotalBytes: memory?.totalBytes,
            diskUsedPercent: disk?.usedPercent,
            diskUsedBytes: disk?.usedBytes,
            diskTotalBytes: disk?.totalBytes,
            diskFreeBytes: disk?.freeBytes,
            diskReadBytesPerSecond: diskIO?.readBytesPerSecond,
            diskWriteBytesPerSecond: diskIO?.writeBytesPerSecond
        )
    }

    private func readCPUUsagePercent() -> Double? {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let current = CPUTicks(
            user: UInt64(load.cpu_ticks.0),
            system: UInt64(load.cpu_ticks.1),
            idle: UInt64(load.cpu_ticks.2),
            nice: UInt64(load.cpu_ticks.3)
        )

        lock.lock()
        defer { lock.unlock() }
        let previous = previousCPUTicks
        previousCPUTicks = current
        guard let previous else { return nil }

        let totalDelta = current.total &- previous.total
        let idleDelta = current.idle &- previous.idle
        guard totalDelta > 0 else { return 0 }

        let usage = (1 - Double(idleDelta) / Double(totalDelta)) * 100
        return min(100, max(0, usage))
    }

    private func readMemoryMetrics() -> (usedPercent: Double, usedBytes: Int64, totalBytes: Int64)? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let totalBytes = Int64(clamping: ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return nil }
        // Inactive pages are mostly reclaimable file cache on macOS. Exclude
        // them from the user-facing usage number so RAM reflects pressure,
        // not memory that the system can reclaim when an app needs it.
        let usedPages = UInt64(statistics.active_count)
            &+ UInt64(statistics.wire_count)
            &+ UInt64(statistics.compressor_page_count)
        let usedBytes = Int64(clamping: usedPages &* UInt64(getpagesize()))
        let usedPercent = min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
        return (usedPercent, usedBytes, totalBytes)
    }

    private func readDiskMetrics() -> (
        usedPercent: Double,
        usedBytes: Int64,
        totalBytes: Int64,
        freeBytes: Int64
    )? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = (attributes[.systemSize] as? NSNumber)?.int64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value,
              total > 0,
              free >= 0 else {
            return nil
        }

        let freeBytes = min(total, free)
        let usedBytes = max(0, total - freeBytes)
        let usedPercent = min(100, max(0, Double(usedBytes) / Double(total) * 100))
        return (usedPercent, usedBytes, total, freeBytes)
    }

    private func readDiskIO(at date: Date) -> (readBytesPerSecond: Double, writeBytesPerSecond: Double)? {
        guard let current = readDiskIOCounters() else { return nil }

        lock.lock()
        defer { lock.unlock() }
        let previous = previousDiskIO
        previousDiskIO = (current, date)
        guard let previous else { return nil }

        let elapsed = date.timeIntervalSince(previous.date)
        guard elapsed > 0.1 else { return nil }
        let readDelta = current.readBytes >= previous.counters.readBytes
            ? current.readBytes - previous.counters.readBytes
            : 0
        let writeDelta = current.writeBytes >= previous.counters.writeBytes
            ? current.writeBytes - previous.counters.writeBytes
            : 0
        return (
            Double(readDelta) / elapsed,
            Double(writeDelta) / elapsed
        )
    }

    private func readDiskIOCounters() -> DiskIOCounters? {
        let matching = IOServiceMatching(kIOBlockStorageDriverClass)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0
        var foundStatistics = false

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            var unmanagedProperties: Unmanaged<CFMutableDictionary>?
            let result = IORegistryEntryCreateCFProperties(
                service,
                &unmanagedProperties,
                kCFAllocatorDefault,
                0
            )
            guard result == KERN_SUCCESS,
                  let unmanagedProperties,
                  let properties = unmanagedProperties.takeRetainedValue() as? [String: Any],
                  let statistics = properties["Statistics"] as? [String: Any] else {
                continue
            }

            if let value = statistics["Bytes (Read)"] as? NSNumber {
                readBytes &+= value.uint64Value
                foundStatistics = true
            }
            if let value = statistics["Bytes (Write)"] as? NSNumber {
                writeBytes &+= value.uint64Value
                foundStatistics = true
            }
        }

        guard foundStatistics else { return nil }
        return DiskIOCounters(readBytes: readBytes, writeBytes: writeBytes)
    }

    private func thermalState(_ state: ProcessInfo.ThermalState) -> ThermalState {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unavailable
        }
    }
}
