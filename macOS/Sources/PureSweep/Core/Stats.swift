import Darwin
import Foundation

/// Live disk, memory and CPU figures for the Home page and the menu bar.
@Observable
final class SystemStats {
    static let shared = SystemStats()

    private(set) var diskTotal: Int64 = 0
    private(set) var diskFree: Int64 = 0          // includes purgeable space, like Finder shows
    private(set) var purgeable: Int64 = 0
    private(set) var memTotal = Int64(ProcessInfo.processInfo.physicalMemory)
    private(set) var memUsed: Int64 = 0
    private(set) var cpu: Double = 0              // 0-100
    let cores = ProcessInfo.processInfo.activeProcessorCount

    var diskUsedPct: Double { diskTotal > 0 ? 100 * Double(diskTotal - diskFree) / Double(diskTotal) : 0 }
    var memUsedPct: Double { memTotal > 0 ? 100 * Double(memUsed) / Double(memTotal) : 0 }

    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var timer: Timer?
    private var users = 0

    /// Start/stop are reference counted so the Home page and the menu bar can share one timer.
    func start() {
        users += 1
        guard timer == nil else { return }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.update() }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { timer?.invalidate(); timer = nil }
    }

    func update() {
        updateDisk()
        updateMemory()
        updateCPU()
    }

    func updateDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        let plain = Int64(v.volumeAvailableCapacity ?? 0)
        diskFree = max(plain, v.volumeAvailableCapacityForImportantUsage ?? plain)
        purgeable = max(0, diskFree - plain)
    }

    private func updateMemory() {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Int64(vm_kernel_page_size)
        // Same as Activity Monitor's "Memory Used": app memory + wired + compressed.
        let app = Int64(info.internal_page_count) - Int64(info.purgeable_count)
        memUsed = (app + Int64(info.wire_count) + Int64(info.compressor_page_count)) * page
    }

    private func updateCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let t = info.cpu_ticks
        let user = UInt64(t.0), system = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
        let busy = user + system + nice, total = busy + idle
        if let last = lastTicks, total > last.total {
            cpu = 100 * Double(busy - last.busy) / Double(total - last.total)
        }
        lastTicks = (busy, total)
    }
}
