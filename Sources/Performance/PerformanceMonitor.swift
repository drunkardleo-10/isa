import Foundation
import Darwin
import MachO
import IOKit

struct rusage_info_v4 {
    var ri_uuid: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    var ri_user_time: UInt64 = 0
    var ri_system_time: UInt64 = 0
    var ri_pkg_idle_wkups: UInt64 = 0
    var ri_interrupt_wkups: UInt64 = 0
    var ri_pageins: UInt64 = 0
    var ri_wired_size: UInt64 = 0
    var ri_resident_size: UInt64 = 0
    var ri_phys_footprint: UInt64 = 0
    var ri_proc_start_abstime: UInt64 = 0
    var ri_proc_exit_abstime: UInt64 = 0
    var ri_child_user_time: UInt64 = 0
    var ri_child_system_time: UInt64 = 0
    var ri_child_pkg_idle_wkups: UInt64 = 0
    var ri_child_interrupt_wkups: UInt64 = 0
    var ri_child_pageins: UInt64 = 0
    var ri_child_elapsed_abstime: UInt64 = 0
    var ri_diskio_bytesread: UInt64 = 0
    var ri_diskio_byteswritten: UInt64 = 0
    var ri_cpu_time_qos_default: UInt64 = 0
    var ri_cpu_time_qos_maintenance: UInt64 = 0
    var ri_cpu_time_qos_background: UInt64 = 0
    var ri_cpu_time_qos_utility: UInt64 = 0
    var ri_cpu_time_qos_legacy: UInt64 = 0
    var ri_cpu_time_qos_user_initiated: UInt64 = 0
    var ri_cpu_time_qos_user_interactive: UInt64 = 0
    var ri_billed_system_time: UInt64 = 0
    var ri_serviced_system_time: UInt64 = 0
    var ri_logical_writes: UInt64 = 0
    var ri_lifetime_max_phys_footprint: UInt64 = 0
    var ri_instructions: UInt64 = 0
    var ri_cycles: UInt64 = 0
    var ri_billed_energy: UInt64 = 0
    var ri_serviced_energy: UInt64 = 0
    var ri_unused: (UInt64, UInt64) = (0, 0)
}

@_silgen_name("proc_pid_rusage")
func proc_pid_rusage(_ pid: pid_t, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer) -> Int32

@_silgen_name("responsibility_get_pid_responsible_for_pid")
func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

@_silgen_name("proc_listpids")
func proc_listpids(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidpath")
func proc_pidpath(_ pid: pid_t, _ buffer: UnsafeMutableRawPointer, _ buffersize: UInt32) -> Int32

struct MemoryTelemetry: Codable {
    struct ChildProcess: Codable {
        let pid: Int32
        let role: String
        let physicalFootprintMB: Double
        let legacyRssMB: Double
    }

    let hostFootprintMB: Double
    let hostRusageFootprintMB: Double
    let hostRssMB: Double
    let children: [ChildProcess]
    let webKitFootprintMB: Double
    let webKitLegacyRssMB: Double
    let totalPhysicalFootprintMB: Double
    let legacyRssSumMB: Double
    let rssInflationRatio: Double
}

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

    private var cachedTelemetry: MemoryTelemetry?
    private var lastTelemetryQueryTime: CFAbsoluteTime = 0

    func currentTelemetry(requireNonZeroChildrenIfWebviewLoaded: Bool = false) -> MemoryTelemetry {
        let now = CFAbsoluteTimeGetCurrent()
        if let cached = cachedTelemetry, (now - lastTelemetryQueryTime) < 1.0 {
            return cached
        }

        let hostMachFootprint = physicalFootprintMB
        var hostRusage = rusage_info_v4()
        let rusageRet = proc_pid_rusage(getpid(), 4, &hostRusage)
        let hostRusageFootprint = rusageRet == 0 ? Double(hostRusage.ri_phys_footprint) / (1024.0 * 1024.0) : hostMachFootprint

        if hostMachFootprint > 0 && hostRusageFootprint > 0 {
            let delta = abs(hostMachFootprint - hostRusageFootprint) / hostMachFootprint
            if delta > 0.02 {
                print("[isa] [WARNING] Host footprint mismatch: mach=\(hostMachFootprint)MB vs rusage=\(hostRusageFootprint)MB (diff: \(String(format: "%.1f", delta * 100))%)")
            }
        }

        let hostRss = ramUsageMB
        let childPids = findWebKitChildPids()

        var children: [MemoryTelemetry.ChildProcess] = []
        var totalWkFootprint: Double = 0.0
        var totalWkLegacyRss: Double = 0.0

        for (pid, role) in childPids {
            var info = rusage_info_v4()
            if proc_pid_rusage(pid, 4, &info) == 0 {
                let footMB = Double(info.ri_phys_footprint) / (1024.0 * 1024.0)
                let rssMB = Double(info.ri_resident_size) / (1024.0 * 1024.0)
                children.append(MemoryTelemetry.ChildProcess(pid: pid, role: role, physicalFootprintMB: footMB, legacyRssMB: rssMB))
                totalWkFootprint += footMB
                totalWkLegacyRss += rssMB
            }
        }

        if requireNonZeroChildrenIfWebviewLoaded && children.isEmpty {
            print("[isa] [ERROR] Zero WebKit child processes discovered while WKWebView is active!")
        }

        let totalFootprint = hostMachFootprint + totalWkFootprint
        let legacyRssSum = hostRss + totalWkLegacyRss
        let ratio = totalFootprint > 0 ? (legacyRssSum / totalFootprint) : 1.0

        let telemetry = MemoryTelemetry(
            hostFootprintMB: hostMachFootprint,
            hostRusageFootprintMB: hostRusageFootprint,
            hostRssMB: hostRss,
            children: children,
            webKitFootprintMB: totalWkFootprint,
            webKitLegacyRssMB: totalWkLegacyRss,
            totalPhysicalFootprintMB: totalFootprint,
            legacyRssSumMB: legacyRssSum,
            rssInflationRatio: ratio
        )

        self.cachedTelemetry = telemetry
        self.lastTelemetryQueryTime = now
        return telemetry
    }

    func findWebKitChildPids() -> [(pid: pid_t, role: String)] {
        let myPid = getpid()
        let myResp = responsibility_get_pid_responsible_for_pid(myPid)
        let myBundleId = Bundle.main.bundleIdentifier ?? "com.isa.browser"

        let numPids = proc_listpids(1, 0, nil, 0)
        guard numPids > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(numPids) / MemoryLayout<pid_t>.stride)
        let actualBytes = proc_listpids(1, 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard actualBytes > 0 else { return [] }
        let count = Int(actualBytes) / MemoryLayout<pid_t>.stride

        var results: [(pid: pid_t, role: String)] = []
        for p in pids[0..<count] {
            if p <= 0 || p == myPid { continue }
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            let len = proc_pidpath(p, &pathBuffer, 4096)
            guard len > 0 else { continue }
            let path = String(cString: pathBuffer)
            guard path.contains("com.apple.WebKit.") else { continue }

            let role: String
            if path.contains("WebContent") {
                role = "WebContent"
            } else if path.contains("GPU") {
                role = "GPU"
            } else if path.contains("Networking") {
                role = "Networking"
            } else {
                continue
            }

            let resp = responsibility_get_pid_responsible_for_pid(p)
            var isAttributed = (resp == myPid)
            if !isAttributed && myResp != 0 && resp == myResp {
                isAttributed = true
            }

            if !isAttributed {
                var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, p]
                var size: Int = 0
                if sysctl(&mib, 3, nil, &size, nil, 0) == 0 && size > 0 {
                    var buffer = [CChar](repeating: 0, count: size)
                    if sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 {
                        let data = Data(bytes: buffer, count: size)
                        let str = String(decoding: data, as: UTF8.self)
                        if str.contains(myBundleId) {
                            isAttributed = true
                        }
                    }
                }
            }

            if isAttributed {
                results.append((pid: p, role: role))
            }
        }

        print("[isa] [Discovery] Found \(results.count) WebKit child processes: " + results.map { "\($0.role)(\($0.pid))" }.joined(separator: ", "))
        return results
    }

    func debugVmmapSummary(for pid: pid_t) -> String? {
        guard ProcessInfo.processInfo.arguments.contains("--vmmap-debug") else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/vmmap")
        proc.arguments = ["--summary", "\(pid)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func log(event: String, details: String? = nil) {
        guard isEnabled else { return }
        let t = currentTelemetry()
        let footStr = String(format: "%.1f MB (Host: %.1f MB, WebKit: %.1f MB [%d procs])",
                             t.totalPhysicalFootprintMB, t.hostFootprintMB, t.webKitFootprintMB, t.children.count)
        let legacyRssStr = String(format: "%.1f MB", t.legacyRssSumMB)
        let gpuStr = gpuUtilization.map { "\(Int($0))%" } ?? "N/A"

        if let details = details {
            print("[isa] [\(event)] \(details) | Physical Footprint: \(footStr) | RSS (double-counted): \(legacyRssStr) | GPU: \(gpuStr)")
        } else {
            print("[isa] [\(event)] Physical Footprint: \(footStr) | RSS (double-counted): \(legacyRssStr) | GPU: \(gpuStr)")
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
