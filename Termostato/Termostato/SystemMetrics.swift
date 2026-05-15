import Foundation
import Observation

// MARK: - APIVerdict (D-06)

/// Three-tier verdict classification for each Mach API probe.
/// - accessible: KERN_SUCCESS with non-zero plausible data
/// - degraded: KERN_SUCCESS but zeroed or stale data
/// - blocked: KERN_FAILURE or other error code
/// - pending: Not yet probed
enum APIVerdict: String {
    case accessible = "Accessible"
    case degraded   = "Degraded"
    case blocked    = "Blocked"
    case pending    = "Pending"
}

// MARK: - MachProbeResult (D-09)

/// A single probe sample result — kern_return_t code, verdict, raw data dump, and timestamp.
struct MachProbeResult: Identifiable {
    let id = UUID()
    let api: String
    let kernReturn: kern_return_t
    let verdict: APIVerdict
    let rawData: String
    let timestamp: Date
}

// MARK: - SystemMetricsProbe

/// Mach API probe engine. Isolated from TemperatureViewModel per D-01.
/// Calls host_statistics (CPU), host_statistics64 (Memory), task_info (Process Memory),
/// and task_threads (Process CPU) and classifies each as Accessible / Degraded / Blocked.
@Observable
@MainActor
final class SystemMetricsProbe {

    // MARK: - API Name Constants (match UI-SPEC copywriting contract exactly)

    static let cpuAPI           = "host_statistics (CPU)"
    static let memoryAPI        = "host_statistics64 (Memory)"
    static let processMemoryAPI = "task_info (Process Memory)"
    static let processCPUAPI    = "task_threads (Process CPU)"
    static let allAPIs          = [cpuAPI, memoryAPI, processMemoryAPI, processCPUAPI]

    // MARK: - Published State

    /// Keyed by API name, array of up to 3 samples per API.
    private(set) var results: [String: [MachProbeResult]] = [:]

    /// Majority verdict per API after 3 samples.
    private(set) var finalVerdicts: [String: APIVerdict] = [:]

    private(set) var isProbing: Bool = false
    private(set) var samplesCompleted: Int = 0

    @ObservationIgnored
    private var probeTask: Task<Void, Never>?

    // MARK: - Probe Sequence (D-07)

    /// Run 3 samples at 10-second intervals. Majority verdict determines final classification.
    func runProbeSequence() {
        guard !isProbing else { return }
        isProbing = true
        samplesCompleted = 0
        results = [:]
        finalVerdicts = [:]

        probeTask = Task { [weak self] in
            guard let self else { return }
            for i in 0..<3 {
                if Task.isCancelled { break }

                let cpuResult     = self.probeSystemCPU()
                let memResult     = self.probeSystemMemory()
                let procMemResult = self.probeTaskMemory()
                let procCPUResult = self.probeTaskCPU()

                self.results[SystemMetricsProbe.cpuAPI, default: []].append(cpuResult)
                self.results[SystemMetricsProbe.memoryAPI, default: []].append(memResult)
                self.results[SystemMetricsProbe.processMemoryAPI, default: []].append(procMemResult)
                self.results[SystemMetricsProbe.processCPUAPI, default: []].append(procCPUResult)

                self.samplesCompleted = i + 1
                print("[Termostato] Probe sample \(i + 1) of 3 complete")

                if i < 2 {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .seconds(10))
                }
            }

            // Compute majority verdicts
            for api in SystemMetricsProbe.allAPIs {
                let samples = self.results[api] ?? []
                self.finalVerdicts[api] = self.majorityVerdict(from: samples)
            }

            self.isProbing = false
            print("[Termostato] Probe sequence complete. Verdicts: \(self.finalVerdicts)")
        }
    }

    func cancelProbe() {
        probeTask?.cancel()
        probeTask = nil
        isProbing = false
    }

    // MARK: - Majority Verdict

    private func majorityVerdict(from samples: [MachProbeResult]) -> APIVerdict {
        guard !samples.isEmpty else { return .pending }
        var counts: [APIVerdict: Int] = [:]
        for sample in samples {
            counts[sample.verdict, default: 0] += 1
        }
        // Priority order if tie: accessible > degraded > blocked
        let verdictPriority: [APIVerdict] = [.accessible, .degraded, .blocked, .pending]
        let maxCount = counts.values.max() ?? 0
        for verdict in verdictPriority {
            if (counts[verdict] ?? 0) == maxCount {
                return verdict
            }
        }
        return .pending
    }

    // MARK: - Probe Methods

    /// Probe host_statistics with HOST_CPU_LOAD_INFO flavor (system-wide CPU ticks).
    private func probeSystemCPU() -> MachProbeResult {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        let verdict: APIVerdict
        let rawData: String
        if result == KERN_SUCCESS {
            let total = UInt64(loadInfo.cpu_ticks.0) + UInt64(loadInfo.cpu_ticks.1)
                      + UInt64(loadInfo.cpu_ticks.2) + UInt64(loadInfo.cpu_ticks.3)
            verdict = total > 0 ? .accessible : .degraded
            rawData = "user: \(loadInfo.cpu_ticks.0), system: \(loadInfo.cpu_ticks.1), idle: \(loadInfo.cpu_ticks.2), nice: \(loadInfo.cpu_ticks.3)"
        } else {
            verdict = .blocked
            rawData = "kern_return_t: \(result)"
        }

        print("[Termostato] host_statistics CPU: kern_return_t=\(result), data=\(rawData)")
        return MachProbeResult(
            api: SystemMetricsProbe.cpuAPI,
            kernReturn: result,
            verdict: verdict,
            rawData: rawData,
            timestamp: Date()
        )
    }

    /// Probe host_statistics64 with HOST_VM_INFO64 flavor (system-wide memory page counts).
    private func probeSystemMemory() -> MachProbeResult {
        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let verdict: APIVerdict
        let rawData: String
        if result == KERN_SUCCESS {
            let total = UInt64(vmStat.free_count) + UInt64(vmStat.active_count)
                      + UInt64(vmStat.inactive_count) + UInt64(vmStat.wire_count)
            verdict = total > 0 ? .accessible : .degraded
            rawData = "free: \(vmStat.free_count), active: \(vmStat.active_count), inactive: \(vmStat.inactive_count), wired: \(vmStat.wire_count)"
        } else {
            verdict = .blocked
            rawData = "kern_return_t: \(result)"
        }

        print("[Termostato] host_statistics64 Memory: kern_return_t=\(result), data=\(rawData)")
        return MachProbeResult(
            api: SystemMetricsProbe.memoryAPI,
            kernReturn: result,
            verdict: verdict,
            rawData: rawData,
            timestamp: Date()
        )
    }

    /// Probe task_info with MACH_TASK_BASIC_INFO flavor (per-process resident memory).
    private func probeTaskMemory() -> MachProbeResult {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MACH_TASK_BASIC_INFO_COUNT)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let verdict: APIVerdict
        let rawData: String
        if result == KERN_SUCCESS {
            verdict = info.resident_size > 0 ? .accessible : .degraded
            rawData = "resident_size: \(info.resident_size) bytes (\(info.resident_size / 1024 / 1024) MB), virtual_size: \(info.virtual_size) bytes"
        } else {
            verdict = .blocked
            rawData = "kern_return_t: \(result)"
        }

        print("[Termostato] task_info Memory: kern_return_t=\(result), data=\(rawData)")
        return MachProbeResult(
            api: SystemMetricsProbe.processMemoryAPI,
            kernReturn: result,
            verdict: verdict,
            rawData: rawData,
            timestamp: Date()
        )
    }

    /// Probe task_threads + THREAD_BASIC_INFO (per-process CPU usage across all threads).
    /// CRITICAL: Thread list is deallocated with vm_deallocate in a defer block (T-06-02 mitigation).
    private func probeTaskCPU() -> MachProbeResult {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threadList, &threadCount)

        guard result == KERN_SUCCESS, let threads = threadList else {
            let rawData = "kern_return_t: \(result)"
            print("[Termostato] task_threads CPU: kern_return_t=\(result), data=\(rawData)")
            return MachProbeResult(
                api: SystemMetricsProbe.processCPUAPI,
                kernReturn: result,
                verdict: .blocked,
                rawData: rawData,
                timestamp: Date()
            )
        }

        // Deallocate thread port array when done — prevents mach port leak (T-06-02, Pitfall 1)
        defer {
            let size = vm_size_t(MemoryLayout<thread_act_t>.size * Int(threadCount))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }

        var totalUsage: Double = 0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
            let kr = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if kr == KERN_SUCCESS && (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        let rawData = "threads: \(threadCount), total_cpu: \(String(format: "%.1f", totalUsage))%"
        print("[Termostato] task_threads CPU: kern_return_t=\(result), data=\(rawData)")
        return MachProbeResult(
            api: SystemMetricsProbe.processCPUAPI,
            kernReturn: result,
            verdict: .accessible,
            rawData: rawData,
            timestamp: Date()
        )
    }
}
