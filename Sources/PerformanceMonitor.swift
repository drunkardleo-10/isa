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

    private let monitorQueue = DispatchQueue(label: "org.isa.perf-monitor", qos: .utility)
    private var cachedWebKitRSSMB: Double = 0.0
    private var cachedWebKitProcessCount: Int = 0
    private var lastWebKitQueryTime: CFAbsoluteTime = 0

    var webKitHelperRSSMB: Double {
        refreshWebKitMemoryIfNeeded()
        return cachedWebKitRSSMB
    }

    var webKitProcessCount: Int {
        refreshWebKitMemoryIfNeeded()
        return cachedWebKitProcessCount
    }

    var totalCombinedRSSMB: Double {
        return ramUsageMB + webKitHelperRSSMB
    }

    private func refreshWebKitMemoryIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastWebKitQueryTime >= 2.0 else { return }
        lastWebKitQueryTime = now
        queryWebKitMemory()
    }

    func queryWebKitMemory() {
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p1.arguments = ["-c", "com.apple.WebKit"]
        let pipe1 = Pipe()
        p1.standardOutput = pipe1
        p1.standardError = Pipe()
        do {
            try p1.run()
        } catch {
            return
        }
        let data1 = pipe1.fileHandleForReading.readDataToEndOfFile()
        p1.waitUntilExit()
        guard let str1 = String(data: data1, encoding: .utf8) else { return }

        var pids = Set<String>()
        let matchPatterns = ["com.isa.browser", "+isa", "/isa/", "isa.app", "isa.adblock.rules"]
        for line in str1.components(separatedBy: .newlines) {
            var matched = false
            for pattern in matchPatterns {
                if line.contains(pattern) {
                    matched = true
                    break
                }
            }
            if matched {
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                if parts.count >= 2 {
                    pids.insert(String(parts[1]))
                }
            }
        }

        guard !pids.isEmpty else {
            self.cachedWebKitRSSMB = 0.0
            self.cachedWebKitProcessCount = 0
            return
        }

        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/bin/ps")
        p2.arguments = ["-o", "rss=", "-p", pids.joined(separator: ",")]
        let pipe2 = Pipe()
        p2.standardOutput = pipe2
        p2.standardError = Pipe()
        do {
            try p2.run()
        } catch {
            return
        }
        let data2 = pipe2.fileHandleForReading.readDataToEndOfFile()
        p2.waitUntilExit()
        guard let str2 = String(data: data2, encoding: .utf8) else { return }

        var totalKB = 0.0
        for line in str2.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let kb = Double(trimmed) {
                totalKB += kb
            }
        }
        self.cachedWebKitRSSMB = totalKB / 1024.0
        self.cachedWebKitProcessCount = pids.count
    }

    func log(event: String, details: String? = nil) {
        guard isEnabled else { return }
        refreshWebKitMemoryIfNeeded()
        let totalStr = String(format: "%.1f MB", totalCombinedRSSMB)
        let hostStr = String(format: "%.1f MB", ramUsageMB)
        let webKitStr = String(format: "%.1f MB (%d procs)", cachedWebKitRSSMB, cachedWebKitProcessCount)
        let footStr = String(format: "%.1f MB", physicalFootprintMB)
        let gpuStr = gpuUtilization.map { "\(Int($0))%" } ?? "N/A"
        if let details = details {
            print("[isa] [\(event)] \(details) | Total RSS: \(totalStr) (Host: \(hostStr), WebKit: \(webKitStr)) | Footprint: \(footStr) | GPU: \(gpuStr)")
        } else {
            print("[isa] [\(event)] Total RSS: \(totalStr) (Host: \(hostStr), WebKit: \(webKitStr)) | Footprint: \(footStr) | GPU: \(gpuStr)")
        }
    }


    func startPeriodicLogging(statsProvider: @escaping () -> String) {
        guard isEnabled else { return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let stats = statsProvider()
            self.log(event: "Perf", details: stats)
        }
    }
}
