import Foundation
import Observation

/// Live CPU and memory metrics ViewModel for Termostato.
/// Polls every 5 seconds via Task.detached — Mach calls are nonisolated to avoid blocking @MainActor.
/// D-07: Separate class, does NOT extend TemperatureViewModel.
/// D-11: Task.detached + await MainActor.run marshalling pattern.
@Observable
@MainActor
final class MetricsViewModel {

    // MARK: - Published properties (read-only to views — D-08)

    /// App CPU% from task_threads — sum of cpu_usage/TH_USAGE_SCALE across non-idle threads (D-14)
    private(set) var appCPUPercent: Double = 0.0

    /// App resident memory in MB from task_info MACH_TASK_BASIC_INFO (D-08)
    private(set) var appMemoryMB: Int = 0

    /// System CPU% from host_statistics delta formula — user/(user+idle) × 100 (D-13)
    private(set) var sysCPUPercent: Double = 0.0

    /// System free memory in GB from host_statistics64 free_count × page size (D-08)
    private(set) var sysMemoryFreeGB: Double = 0.0

    /// System used memory in GB from host_statistics64 (active_count + wire_count) × page size (D-08)
    private(set) var sysMemoryUsedGB: Double = 0.0

    // MARK: - Private polling state

    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    /// Previous CPU tick snapshot for delta computation (D-13).
    /// nonisolated(unsafe): mutated inside nonisolated readSystemCPU(), not tracked by @Observable.
    /// Same pattern as thermalObserver / backgroundTaskID in TemperatureViewModel (lines 69-73).
    @ObservationIgnored
    nonisolated(unsafe) private var previousCPUTicks: (user: UInt32, idle: UInt32) = (0, 0)

    // MARK: - Lifecycle (D-10)

    /// Start 5-second polling loop. Guard against double-start by cancelling any existing task first.
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.tick()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await self.tick()
            }
        }
        #if DEBUG
        print("[Termostato] MetricsViewModel polling started.")
        #endif
    }

    /// Cancel polling task. Call when scenePhase becomes .background.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        #if DEBUG
        print("[Termostato] MetricsViewModel polling stopped.")
        #endif
    }

    // MARK: - Tick (D-11)

    /// Execute one poll cycle: call nonisolated Mach methods (no actor hop required),
    /// then marshal results back to @MainActor via MainActor.run.
    private func tick() async {
        let appCPU = readAppCPU()
        let appMem = readAppMemory()
        let sysCPU = readSystemCPU()
        let sysMem = readSystemMemory()
        await MainActor.run {
            self.appCPUPercent   = appCPU
            self.appMemoryMB     = appMem
            self.sysCPUPercent   = sysCPU
            self.sysMemoryFreeGB = sysMem.freeGB
            self.sysMemoryUsedGB = sysMem.usedGB
        }
    }

    // MARK: - nonisolated Mach call methods (D-11, D-12, D-15)
    // Extracted verbatim from SystemMetrics.swift — proven correct on device (Phase 6 KERN_SUCCESS).
    // SystemMetrics.swift is NOT modified (D-12).

    /// App CPU% — task_threads loop. CRITICAL: defer vm_deallocate to prevent port leak (Pitfall 1).
    nonisolated private func readAppCPU() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threadList, &threadCount)

        guard result == KERN_SUCCESS, let threads = threadList else { return 0.0 }

        defer {
            // Mandatory: task_threads allocates via vm_allocate — must free to prevent port leak.
            let size = vm_size_t(MemoryLayout<thread_act_t>.size * Int(threadCount))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }

        var totalUsage: Double = 0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var infoCount = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
            )
            let kr = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if kr == KERN_SUCCESS && (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return totalUsage
    }

    /// App resident memory in MB — task_info MACH_TASK_BASIC_INFO resident_size.
    nonisolated private func readAppMemory() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size / 1024 / 1024)
    }

    /// System CPU% delta — host_statistics cpu_ticks. First poll returns 0.0 (Pitfall 2).
    /// cpu_ticks tuple: .0=user, .1=system(always 0 on Apple Silicon), .2=idle, .3=nice (D-13).
    nonisolated private func readSystemCPU() -> Double {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0.0 }

        let currentUser = loadInfo.cpu_ticks.0   // CPU_STATE_USER
        let currentIdle = loadInfo.cpu_ticks.2   // CPU_STATE_IDLE (.1=system always 0 on Apple Silicon)

        let prev = previousCPUTicks
        previousCPUTicks = (user: currentUser, idle: currentIdle)

        // First poll: previousCPUTicks is (0,0) — delta would span all boot ticks, return 0 (Pitfall 2).
        guard prev.user > 0 || prev.idle > 0 else { return 0.0 }

        let userDelta = currentUser > prev.user ? Double(currentUser - prev.user) : 0.0
        let idleDelta = currentIdle > prev.idle ? Double(currentIdle - prev.idle) : 0.0
        let total = userDelta + idleDelta
        guard total > 0 else { return 0.0 }

        return (userDelta / total) * 100.0
    }

    /// System memory free/used in GB — host_statistics64 vm_statistics64 page counts × vm_kernel_page_size.
    nonisolated private func readSystemMemory() -> (freeGB: Double, usedGB: Double) {
        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0.0, 0.0) }

        // vm_kernel_page_size is not concurrency-safe under Swift 6 strict concurrency (assumption A1 fallback).
        // iOS on Apple Silicon uses 16384-byte pages; this literal is safe and correct for arm64.
        let pageSize: Double = 16384
        let freeGB = Double(vmStat.free_count) * pageSize / 1_073_741_824.0
        let usedGB = Double(vmStat.active_count + vmStat.wire_count) * pageSize / 1_073_741_824.0

        return (freeGB: freeGB, usedGB: usedGB)
    }
}
