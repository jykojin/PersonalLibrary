import Foundation
import UIKit

/// 系统指标采集 — 仅采集 iOS 公开 API 可读的数据
/// CPU 实际温度 (°C) iOS 不允许读取（私有 API），用 ProcessInfo.thermalState 作为代理
enum SystemMetrics {

    /// 当前 thermal state 的可读字符串
    static var thermalStateString: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// 本进程 CPU 占用百分比（所有线程合计；> 100% 说明跨核）
    /// 失败返回 nil
    static func processCPUPercent() -> Double? {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threadList = threadList else {
            return nil
        }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: threadList)),
                          vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }

        var totalUsage: Double = 0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO),
                                $0, &threadInfoCount)
                }
            }
            if result == KERN_SUCCESS,
               (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return totalUsage
    }

    /// 本进程内存占用（resident set size，字节）
    /// 失败返回 nil
    static func processMemoryBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// 系统空闲内存（字节）
    static func systemFreeMemoryBytes() -> UInt64? {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(stats.free_count) * UInt64(pageSize)
    }

    /// 一次性 snapshot 文本（用于日志）
    /// 格式: "thermal=nominal cpu=145% mem=180MB free=2.1GB battery=82% charging=yes"
    @MainActor
    static func snapshot() -> String {
        let thermal = thermalStateString
        let cpu = processCPUPercent().map { String(format: "%.0f%%", $0) } ?? "?"
        let mem = processMemoryBytes().map { String(format: "%.0fMB", Double($0) / 1024.0 / 1024.0) } ?? "?"
        let free = systemFreeMemoryBytes().map { String(format: "%.1fGB", Double($0) / 1024.0 / 1024.0 / 1024.0) } ?? "?"

        // 电池信息需要先开启监听
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = UIDevice.current.batteryLevel
        let batteryStr = battery >= 0 ? String(format: "%.0f%%", battery * 100) : "?"
        let charging: String = {
            switch UIDevice.current.batteryState {
            case .charging, .full: return "yes"
            case .unplugged: return "no"
            default: return "?"
            }
        }()

        return "thermal=\(thermal) cpu=\(cpu) mem=\(mem) free=\(free) battery=\(batteryStr) charging=\(charging)"
    }
}
