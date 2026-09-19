import Foundation
import Darwin
import MachO
import IOKit

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    #if DEBUG
    var isEnabled: Bool = true
    #else
    var isEnabled: Bool = ProcessInfo.processInfo.environment["ISA_PERF_LOG"] == "1" ||
                          ProcessInfo.processInfo.arguments.contains("--perf-log")
    #endif

    private var timer: Timer?

    var ramUsageMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 0.0
    }

    var gpuUtilization: Double? {
        var iterator = io_iterator_t()
        let match = IOServiceMatching("IOAccelerator")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        var maxUtil: Double? = nil
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any],
               let util = stats["Device Utilization %"] as? NSNumber {
                let val = util.doubleValue
                if maxUtil == nil || val > (maxUtil ?? 0) {
                    maxUtil = val
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return maxUtil
    }

    var physicalFootprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.phys_footprint) / (1024.0 * 1024.0)
        }
        return 0.0
    }

    func log(event: String, details: String? = nil) {
        guard isEnabled else { return }
        let ramStr = String(format: "%.1f MB", ramUsageMB)
        let footStr = String(format: "%.1f MB", physicalFootprintMB)
        let gpuStr = gpuUtilization.map { "\(Int($0))%" } ?? "N/A"
        if let details = details {
            print("[isa] [\(event)] \(details) | RSS: \(ramStr) | Footprint: \(footStr) | GPU: \(gpuStr)")
        } else {
            print("[isa] [\(event)] RSS: \(ramStr) | Footprint: \(footStr) | GPU: \(gpuStr)")
        }
    }

    func startPeriodicLogging(tabCountProvider: @escaping () -> Int) {
        guard isEnabled else { return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let tabs = tabCountProvider()
            self.log(event: "Perf", details: "Active Tabs: \(tabs)")
        }
    }
}
