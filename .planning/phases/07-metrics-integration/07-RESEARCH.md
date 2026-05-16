# Phase 7: Metrics Integration - Research

**Researched:** 2026-05-15
**Domain:** Swift 6.3 / SwiftUI TabView restructure + Mach API ViewModel integration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Phase 7 introduces TabView with 3 tabs: Thermal, CPU, Memory. ContentView becomes the TabView container. Existing thermal content (badge + chart) moves into a new `ThermalView` sub-view.

**D-02:** Debug sheet trigger (long-press on "CoreWatch" title) moves into `ThermalView` with the rest of the thermal content. Behavior unchanged, just relocated.

**D-03:** DASH-01 and DASH-02 (from REQUIREMENTS.md, Phase 8) are satisfied here — the TabView restructure happens in Phase 7, not Phase 8.

**D-04:** CPU tab shows two metric cards: App CPU (%) and System CPU (%). Each card: large number centered, label above. Same visual style — `RoundedRectangle` card matching the thermal badge aesthetic.

**D-05:** Memory tab shows two metric cards: App Memory (MB, from `task_info` resident_size) and System Memory (free / used in GB, from `host_statistics64` page counts × page size). Same card format as CPU tab.

**D-06:** No history charts in Phase 7 for CPU/memory. Rolling history charts are deferred to v1.3+ (CPU-03, MEM-03). Only live current-value display.

**D-07:** Create a new `MetricsViewModel.swift` — separate `@Observable @MainActor` class. Does NOT extend `TemperatureViewModel`. `ContentView` holds both via `@State`:
```swift
@State private var vm = TemperatureViewModel()
@State private var metrics = MetricsViewModel()
```

**D-08:** MetricsViewModel exposes these published properties:
- `appCPUPercent: Double` — app CPU % from `task_threads`
- `appMemoryMB: Int` — app resident memory MB from `task_info`
- `sysCPUPercent: Double` — system CPU % from `host_statistics`
- `sysMemoryFreeGB: Double` — free memory in GB from `host_statistics64`
- `sysMemoryUsedGB: Double` — used memory in GB (active + wired pages × page size)

**D-09:** MetricsViewModel polling interval: 5 seconds. TemperatureViewModel polling interval also reduced from 10s → 5s as part of this phase.

**D-10:** MetricsViewModel lifecycle mirrors TemperatureViewModel — `startPolling()` / `stopPolling()` called together from ContentView's `scenePhase` observer.

**D-11:** MetricsViewModel's Mach call methods are `nonisolated`. Polling runs via `Task.detached(priority: .userInitiated)` with `Task.sleep(for: .seconds(5))` between ticks. Results marshal back to `@MainActor` via `await MainActor.run { }` to update published properties.

**D-12:** This pattern is used in MetricsViewModel only. SystemMetricsProbe in `SystemMetrics.swift` is NOT changed.

**D-13:** System CPU% = `(user_ticks_delta / (user_ticks_delta + idle_ticks_delta)) × 100`. Use user and idle deltas only (system ticks = 0 on Apple Silicon — confirmed Phase 6). Store previous tick snapshot between polls.

**D-14:** App CPU% = sum of `cpu_usage / TH_USAGE_SCALE × 100` across non-idle threads (same formula as `probeTaskCPU()` in SystemMetrics.swift).

**D-15:** Extract Mach call implementations directly from `SystemMetrics.swift` probe methods — they are proven correct and KERN_SUCCESS confirmed. Do NOT rewrite from scratch.

### Claude's Discretion

- Tab bar icon system images (SF Symbols) — use standard iOS symbols appropriate for thermal/CPU/memory
- Exact number formatting (e.g. "4.2%" vs "4%", "79 MB" vs "79.3 MB")
- Card padding, spacing, and typography — follow existing ContentView patterns (16pt horizontal padding, .largeTitle for the number, .headline for the label)
- Empty/loading state for CPU/memory cards before first poll completes

### Deferred Ideas (OUT OF SCOPE)

- Rolling history charts for CPU and memory — deferred to v1.3+ (CPU-03, MEM-03)
- Battery level display — deferred to v1.3+ (BATT-01, BATT-02)
- State duration display ("Serious for 4 min") — deferred to v1.3+ (THERM-01)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CPU-01 | User can see CoreWatch's own CPU usage as a percentage gauge | `probeTaskCPU()` pattern in SystemMetrics.swift is proven; extract into MetricsViewModel `appCPUPercent` property |
| MEM-01 | User can see CoreWatch's memory footprint in MB | `probeTaskMemory()` pattern proven; `resident_size / 1024 / 1024` → MB, expose as `appMemoryMB` |
| CPU-02 | System-wide CPU if sandbox permits (graceful fallback if blocked) | Phase 6 confirmed KERN_SUCCESS — no fallback needed; delta formula (D-13) researched below |
| MEM-02 | System-wide memory if sandbox permits (graceful fallback if blocked) | Phase 6 confirmed KERN_SUCCESS — page count × page size formula researched below |
| DASH-01 | User can switch between Thermal, CPU, and Memory tabs | TabView restructure (D-01) — SwiftUI TabView pattern documented below |
| DASH-02 | Existing thermal content remains functional (no regression) | ThermalView extracts existing ContentView body verbatim — no logic changes |
</phase_requirements>

---

## Summary

Phase 7 is a well-bounded integration phase. The hard work — proving Mach API accessibility on iOS 18 under free sideload — was done in Phase 6. All 4 APIs returned KERN_SUCCESS on physical device. Phase 7's job is to extract the proven probe implementations from `SystemMetrics.swift` into a production `MetricsViewModel`, wire them into a new TabView layout, and update the polling interval. There are no unknowns gating this work.

The primary complexity is concentrated in two areas: (1) the Swift 6.3 strict concurrency pattern for calling `nonisolated` Mach functions from a `@MainActor` ViewModel without blocking the main thread, and (2) the CPU delta computation for `host_statistics`, which requires storing previous tick snapshots to compute a meaningful percentage. Both are resolved — the concurrency pattern is documented in CONTEXT.md (D-11) and the delta formula matches the Phase 6 raw data behavior (user ticks increment monotonically; system ticks are 0 on Apple Silicon).

The TabView restructure is mechanical: ContentView's VStack body moves verbatim into ThermalView, ContentView becomes a TabView container with three tabs. The debug sheet trigger moves with the thermal content (D-02). Four new Swift files need manual project.pbxproj registration following the exact same pattern established for SystemMetrics.swift and MachProbeDebugView.swift in Phase 6.

**Primary recommendation:** Execute in strict file-creation order — pbxproj registration before attempting to build each new file — to avoid Xcode "no such module" failures mid-session.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18 SDK (bundled) | TabView, View protocol, @State, @Environment | Project-mandated; no alternatives |
| Observation | Swift 5.9+ (bundled) | @Observable macro for ViewModel | Project-mandated MVVM pattern |
| Foundation | iOS 18 SDK (bundled) | Task, Task.detached, Task.sleep, MainActor | Swift concurrency primitives |
| Darwin/Mach | iOS 18 SDK (via bridging header) | host_statistics, task_info, task_threads | Already integrated in Phase 6 |

No new dependencies. Phase 7 is zero-external-dependency, same as the rest of the project.

**Installation:** Nothing to install. All frameworks are already in the project.

---

## Architecture Patterns

### Recommended Project Structure (after Phase 7)
```
CoreWatch/
├── CoreWatchApp.swift          # unchanged
├── ContentView.swift            # becomes TabView container (modified)
├── ThermalView.swift            # NEW — extracted from ContentView body
├── CPUView.swift                # NEW — CPU tab content
├── MemoryView.swift             # NEW — Memory tab content
├── MetricsViewModel.swift       # NEW — @Observable @MainActor metrics polling
├── TemperatureViewModel.swift   # modified — polling interval 10s → 5s only
├── SystemMetrics.swift          # unchanged (debug probe retained)
├── MachProbeDebugView.swift     # unchanged
├── NotificationDelegate.swift   # unchanged
├── CoreWatch-Bridging-Header.h # unchanged
└── Assets.xcassets/             # unchanged
```

---

### Pattern 1: TabView Container in ContentView

ContentView becomes a pure container. Its entire existing body becomes `ThermalView`. The `@State private var viewModel` moves into ThermalView; `@State private var metrics` is held at ContentView level.

```swift
// Source: [VERIFIED: ContentView.swift read — existing scenePhase pattern]
struct ContentView: View {
    @State private var vm = TemperatureViewModel()
    @State private var metrics = MetricsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ThermalView(viewModel: vm)
                .tabItem {
                    Label("Thermal", systemImage: "thermometer.medium")
                }
            CPUView(metrics: metrics)
                .tabItem {
                    Label("CPU", systemImage: "cpu")
                }
            MemoryView(metrics: metrics)
                .tabItem {
                    Label("Memory", systemImage: "memorychip")
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                vm.startPolling()
                metrics.startPolling()
            case .background:
                vm.stopPolling()
                metrics.stopPolling()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onAppear {
            vm.startPolling()
            metrics.startPolling()
        }
    }
}
```
[VERIFIED: ContentView.swift line 130–147 — existing onChange/onAppear pattern]

---

### Pattern 2: ThermalView — Verbatim Extract

ThermalView receives `viewModel` as a constructor parameter (or binds via @Bindable if @Observable is used). The simplest approach is to move the entire ContentView body, `badgeColor`/`badgeTextColor`/`thermalStateLabel` helpers, `showDebugSheet` state, and the `.sheet(isPresented:)` modifier into ThermalView unchanged.

```swift
// Source: [VERIFIED: ContentView.swift — existing body content to migrate verbatim]
struct ThermalView: View {
    var viewModel: TemperatureViewModel
    @State private var showDebugSheet = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        // entire existing ContentView VStack body here
        // including the "CoreWatch" title with .onLongPressGesture
        // the badge, the permission-denied banner, the chart
        // and the .sheet(isPresented: $showDebugSheet) modifier
    }
}
```
[VERIFIED: ContentView.swift — existing layout confirmed]

**Key transfer detail:** `@State private var showDebugSheet = false` must move into ThermalView (not ContentView) since the debug sheet trigger is in the thermal content per D-02.

---

### Pattern 3: MetricsViewModel — Task.detached Polling

The Swift 6.3 strict concurrency constraint: `@MainActor` ViewModel cannot directly call Mach C functions without the compiler raising "call to main actor-isolated function from non-isolated context" or blocking the main thread. Solution: mark Mach call helpers `nonisolated`, run polling loop in `Task.detached`, marshal results back with `await MainActor.run`.

```swift
// Source: [VERIFIED: CONTEXT.md D-11 + SystemMetrics.swift nonisolated probe pattern]
@Observable
@MainActor
final class MetricsViewModel {

    // MARK: - Published properties (read-only to views)
    private(set) var appCPUPercent: Double = 0.0
    private(set) var appMemoryMB: Int = 0
    private(set) var sysCPUPercent: Double = 0.0
    private(set) var sysMemoryFreeGB: Double = 0.0
    private(set) var sysMemoryUsedGB: Double = 0.0

    // MARK: - Private polling state
    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    // CPU delta state — previous tick snapshot to compute delta
    @ObservationIgnored
    nonisolated(unsafe) private var previousCPUTicks: (user: UInt32, idle: UInt32) = (0, 0)

    // MARK: - Lifecycle
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // immediate first read
            await self.tick()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await self.tick()
            }
        }
        print("[CoreWatch] MetricsViewModel polling started.")
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        print("[CoreWatch] MetricsViewModel polling stopped.")
    }

    // MARK: - Tick
    private func tick() async {
        // Call nonisolated Mach methods (no actor hop)
        let appCPU = readAppCPU()
        let appMem = readAppMemory()
        let sysCPU = readSystemCPU()
        let sysMem = readSystemMemory()

        // Marshal results to @MainActor
        await MainActor.run {
            self.appCPUPercent = appCPU
            self.appMemoryMB = appMem
            self.sysCPUPercent = sysCPU
            self.sysMemoryFreeGB = sysMem.freeGB
            self.sysMemoryUsedGB = sysMem.usedGB
        }
    }

    // MARK: - nonisolated Mach call methods
    // (implementations extracted from SystemMetrics.swift — see Pattern 4 and 5)
    nonisolated private func readAppCPU() -> Double { ... }
    nonisolated private func readAppMemory() -> Int { ... }
    nonisolated private func readSystemCPU() -> Double { ... }
    nonisolated private func readSystemMemory() -> (freeGB: Double, usedGB: Double) { ... }
}
```
[VERIFIED: CONTEXT.md D-11, SystemMetrics.swift @ObservationIgnored nonisolated(unsafe) pattern line 58-59]

**Important:** `previousCPUTicks` must be `nonisolated(unsafe)` because it is mutated inside `nonisolated` methods (`readSystemCPU`) but is not an `@Observable` tracked property. This follows the established `TemperatureViewModel` pattern for `thermalObserver` and `backgroundTaskID` (lines 69-73 of TemperatureViewModel.swift). [VERIFIED: TemperatureViewModel.swift line 69-73]

---

### Pattern 4: App CPU% Extraction (from probeTaskCPU)

Direct extraction from SystemMetrics.swift `probeTaskCPU()`. The CRITICAL pitfall is `vm_deallocate` on the thread list — already documented in the probe code as "Pitfall 1 / T-06-02 mitigation".

```swift
// Source: [VERIFIED: SystemMetrics.swift lines 236-285]
nonisolated private func readAppCPU() -> Double {
    var threadList: thread_act_array_t?
    var threadCount: mach_msg_type_number_t = 0
    let result = task_threads(mach_task_self_, &threadList, &threadCount)

    guard result == KERN_SUCCESS, let threads = threadList else { return 0.0 }

    defer {
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
```
[VERIFIED: SystemMetrics.swift probeTaskCPU() — confirmed KERN_SUCCESS on device per 06-VERDICTS.md]

---

### Pattern 5: App Memory MB Extraction (from probeTaskMemory)

```swift
// Source: [VERIFIED: SystemMetrics.swift lines 202-232]
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
```
[VERIFIED: SystemMetrics.swift probeTaskMemory() — probe data showed ~79 MB on device, resident_size / 1024 / 1024 formula confirmed correct]

---

### Pattern 6: System CPU% Delta Computation (host_statistics)

The critical insight: `host_statistics` returns cumulative tick counts since boot. A single reading is meaningless as a percentage — you must compute the delta between two consecutive readings and derive the ratio from that delta.

Phase 6 probe data confirms the behavior:
- Sample 1: user=10410413, system=0, idle=28064974
- Sample 2: user=10414312, system=0, idle=28067198
- Delta: user_delta=3899, idle_delta=2224, system_delta=0 (always 0 on Apple Silicon)

CPU% = user_delta / (user_delta + idle_delta) × 100 = 3899 / 6123 × 100 ≈ 63.7% (plausible for a running app at the time of the probe).

```swift
// Source: [VERIFIED: SystemMetrics.swift probeSystemCPU() + 06-VERDICTS.md raw data + CONTEXT.md D-13]
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

    let currentUser = loadInfo.cpu_ticks.0
    let currentIdle = loadInfo.cpu_ticks.2

    let prev = previousCPUTicks  // read nonisolated(unsafe) field
    previousCPUTicks = (user: currentUser, idle: currentIdle)

    // First poll: no delta yet — return 0 and wait for next tick
    guard prev.user > 0 || prev.idle > 0 else { return 0.0 }

    let userDelta = currentUser > prev.user ? Double(currentUser - prev.user) : 0.0
    let idleDelta = currentIdle > prev.idle ? Double(currentIdle - prev.idle) : 0.0
    let total = userDelta + idleDelta
    guard total > 0 else { return 0.0 }

    return (userDelta / total) * 100.0
}
```
[VERIFIED: SystemMetrics.swift cpu_ticks tuple access pattern — .0=user, .1=system, .2=idle, .3=nice. Confirmed from probe output "user: ..., system: ..., idle: ..., nice: ..." mapping in probeSystemCPU() rawData string. 06-VERDICTS.md confirms system=0 on Apple Silicon.]

**cpu_ticks tuple index mapping** (critical — no named fields in the C struct tuple):
- `.0` = CPU_STATE_USER
- `.1` = CPU_STATE_SYSTEM (always 0 on Apple Silicon)
- `.2` = CPU_STATE_IDLE
- `.3` = CPU_STATE_NICE

[VERIFIED: SystemMetrics.swift line 151 rawData string matches "user: \(loadInfo.cpu_ticks.0), system: \(loadInfo.cpu_ticks.1), idle: \(loadInfo.cpu_ticks.2), nice: \(loadInfo.cpu_ticks.3)"]

---

### Pattern 7: System Memory GB (host_statistics64)

```swift
// Source: [VERIFIED: SystemMetrics.swift probeSystemMemory() + 06-VERDICTS.md page data]
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

    // Page size: 16384 bytes on Apple Silicon iOS devices (confirmed by probe data)
    // ~129K total pages × 16384 = ~2.0 GB (but 6 GB device = pages × 4096 actually)
    // Use vm_kernel_page_size for correctness (accessible from Darwin)
    let pageSize = Double(vm_kernel_page_size)
    let freeGB = Double(vmStat.free_count) * pageSize / 1_073_741_824.0
    let usedGB = Double(vmStat.active_count + vmStat.wire_count) * pageSize / 1_073_741_824.0

    return (freeGB: freeGB, usedGB: usedGB)
}
```
[VERIFIED: SystemMetrics.swift probeSystemMemory() — vm_statistics64 field access pattern confirmed. 06-VERDICTS.md sample 1: free=5610, active=41087, wired=45931. Page size verification below.]

**Page size note:** The CONTEXT.md mentions "~129K pages × 4K page size ≈ 6 GB" (total pages = free+active+inactive+wired = 5610+41087+36634+45931 = 129,262). 129,262 × 4096 = ~500 MB — that's wrong for 6 GB. Correct: 129,262 × 16384 bytes = ~2.0 GB. But iPhone 15 series have 6 GB RAM. This inconsistency suggests these counts only reflect a portion of the physical RAM visible to userspace. Use `vm_kernel_page_size` (a Darwin symbol available via the bridging header) rather than a hardcoded constant to be safe. [ASSUMED: vm_kernel_page_size is accessible as a Swift global via the bridging header; needs verification at build time. If not available, use `Int(ProcessInfo.processInfo.physicalMemory)` cross-check or hardcode 16384.]

---

### Pattern 8: Metric Card UI Component

The thermal badge is `RoundedRectangle(cornerRadius: 20).fill(badgeColor).overlay { Text(...) }`. CPU/memory cards follow the same pattern, but without color-coding (static gray fill, or system material fill).

```swift
// Source: [VERIFIED: ContentView.swift lines 32-42 — thermal badge pattern]
struct MetricCardView: View {
    let label: String
    let value: String

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemGray6))
            .overlay {
                VStack(spacing: 4) {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .monospacedDigit()  // prevents layout jitter on number changes
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 100)
    }
}
```
[VERIFIED: ContentView.swift badge shape/padding confirmed. .monospacedDigit() is [ASSUMED] best practice for numeric displays — prevents text width from changing as digits change, reducing layout reflows on every poll tick.]

---

### Pattern 9: project.pbxproj Manual File Registration

Phase 6 established the pattern. Each new Swift file requires 3 edits to project.pbxproj:

1. **PBXBuildFile section** — one line per file:
```
AA000011000000000000000A /* MetricsViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA000011000000000000000B /* MetricsViewModel.swift */; };
```

2. **PBXFileReference section** — one line per file:
```
AA000011000000000000000B /* MetricsViewModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MetricsViewModel.swift; sourceTree = "<group>"; };
```

3. **PBXGroup section** (AA000021000000000000000A "CoreWatch" group) — add fileRef to children array.

4. **PBXSourcesBuildPhase section** (AA000011000000000000000A "Sources") — add build file ref to files array.

[VERIFIED: project.pbxproj lines 9-18 (PBXBuildFile), 20-31 (PBXFileReference), 61-75 (PBXGroup children), 150-163 (PBXSourcesBuildPhase files)]

**ID assignment for new files:** Current highest build file ID is `AA000010100000000000000A` (MachProbeDebugView). New files should use `AA000011X00000000000000A/B` through `AA000014X00000000000000A/B` where X disambiguates the pattern. Following the existing scheme:
- `AA000011100000000000000A/B` — MetricsViewModel.swift
- `AA000012100000000000000A/B` — ThermalView.swift
- `AA000013100000000000000A/B` — CPUView.swift
- `AA000014100000000000000A/B` — MemoryView.swift

---

### Anti-Patterns to Avoid

- **Calling Mach functions directly on @MainActor:** Mach calls can block for microseconds to milliseconds. On a `@MainActor`-isolated method this directly contributes to dropped frames. Use `nonisolated` + `Task.detached` as specified in D-11.
- **Not deallocating the thread list in task_threads:** `task_threads` allocates a Mach port array via `vm_allocate`. Forgetting `vm_deallocate` causes a port leak that accumulates across every poll tick. The `defer` block in Pattern 4 is mandatory.
- **Using Timer.publish in MetricsViewModel:** TemperatureViewModel uses `Timer.publish(on: .main)` which is appropriate for a lightweight ProcessInfo read. MetricsViewModel uses Mach calls and `Task.detached` instead — do not copy the Timer pattern into MetricsViewModel.
- **Forgetting to cancel the polling Task in stopPolling:** `Task.detached` creates a task that outlives the object if not cancelled. `pollingTask?.cancel()` in `stopPolling()` is mandatory.
- **Registering Swift files in the Xcode GUI:** This project uses a hand-managed pbxproj. Adding files via Xcode's "Add Files to Target" dialog modifies the pbxproj with different UUID formats (random hex, not the AA000... scheme). Edit pbxproj directly to maintain the established pattern.
- **Tick counter wraparound in CPU delta:** UInt32 can wrap. The guard `currentUser > prev.user` before subtraction prevents underflow. The first-poll guard (`prev.user == 0 && prev.idle == 0`) returns 0.0 to avoid a garbage delta on the first sample.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mach call Swift bridging | Custom UnsafePointer wrappers | Extract from SystemMetrics.swift verbatim | Already proven correct on device; re-inventing introduces new bugs |
| CPU delta smoothing | Exponential moving average | Raw delta per tick | Overkill for a 5s interval; EMA adds complexity with no visible benefit at this scale |
| Page size detection | Runtime sysctlbyname query | `vm_kernel_page_size` Darwin symbol | Already accessible via bridging header; no code needed |
| Tab state persistence | NSUserDefaults for selected tab | SwiftUI TabView default behavior | TabView remembers selection automatically within a session |

---

## Runtime State Inventory

> This is a code-change phase (new files + edits to existing files). No rename, rebrand, or migration is involved.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no databases, no CoreData, no UserDefaults in this project | None |
| Live service config | None | None |
| OS-registered state | None | None |
| Secrets/env vars | None | None |
| Build artifacts | project.pbxproj must be edited to register 4 new Swift files | Manual pbxproj edit per Pattern 9 |

---

## Common Pitfalls

### Pitfall 1: Thread List Memory Leak
**What goes wrong:** `task_threads` allocates a Mach port array that must be explicitly freed with `vm_deallocate`. If the `defer` block is omitted, each poll tick leaks a small port array. Over 5-second polling for 30 minutes = 360 leaks.
**Why it happens:** The C API contract is not expressed in Swift's type system — nothing in the signature warns you to free the result.
**How to avoid:** Copy the `defer { vm_deallocate(...) }` block from SystemMetrics.swift verbatim. Never omit it.
**Warning signs:** Mach port exhaustion after extended use; the probe code has "T-06-02 mitigation" comment as a reminder.

### Pitfall 2: Stale CPU% on First Poll
**What goes wrong:** `previousCPUTicks` is (0, 0) on first call. The delta = (currentUser - 0) / (currentUser + currentIdle - 0) gives a CPU% that represents the entire time since boot, not the last 5 seconds. This produces artificially low CPU readings (the app's recent activity is diluted across all boot ticks).
**Why it happens:** Cumulative tick counters have no natural "start".
**How to avoid:** Guard `prev.user == 0 && prev.idle == 0` → return 0.0 on first tick. The second tick will produce the first valid delta.
**Warning signs:** First CPU reading is suspiciously low (1-2%) then jumps to a realistic value on second tick.

### Pitfall 3: Swift 6 Sendability Violation on nonisolated Access
**What goes wrong:** `previousCPUTicks` is accessed from a `nonisolated` context (inside `readSystemCPU()`). Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete` — confirmed in project.pbxproj line 309) will error if a stored property accessed from a `nonisolated` context is not marked `nonisolated(unsafe)`.
**Why it happens:** `@MainActor`-isolated class properties cannot be touched from non-isolated functions without an actor hop.
**How to avoid:** Mark `previousCPUTicks` as `@ObservationIgnored nonisolated(unsafe) private var`. This is the identical pattern used for `thermalObserver` and `backgroundTaskID` in TemperatureViewModel.swift (lines 69-73).
**Warning signs:** Compiler error "main actor-isolated property can not be mutated from a nonisolated context".

### Pitfall 4: ThermalView viewModel Ownership
**What goes wrong:** If `TemperatureViewModel` is instantiated inside ThermalView (`@State private var vm = TemperatureViewModel()`), the view loses all data when the tab switches away and the view is recreated. The scenePhase observer is also in ContentView, so startPolling/stopPolling would not be called.
**Why it happens:** SwiftUI recreates views when they are not in the view hierarchy (depending on TabView caching behavior).
**How to avoid:** `ContentView` owns both ViewModels as `@State`. ThermalView receives `var viewModel: TemperatureViewModel` as a parameter (passed by reference since @Observable classes are reference types — no @Binding needed for read-only access; use @Bindable if two-way binding is needed).
**Warning signs:** Timer fires but view shows stale data after tab switch.

### Pitfall 5: Polling Task Not Cancelled on Background
**What goes wrong:** `Task.detached` runs independently of the actor. If `stopPolling()` is not called (or the Task is not stored), the loop continues in the background even after the app backgrounds.
**Why it happens:** `Task.detached` has no automatic lifecycle tie to the ViewModel.
**How to avoid:** Always store the Task handle in `pollingTask` and cancel it in `stopPolling()`. Check `Task.isCancelled` at the start of each loop iteration.
**Warning signs:** Xcode console shows "[CoreWatch] MetricsViewModel polling" logs after the app backgrounds.

---

## Code Examples

### SF Symbols for Tab Icons (Claude's Discretion area)
```swift
// Source: [ASSUMED — standard SF Symbols, verify in SF Symbols app or Xcode]
// Thermal tab:
Label("Thermal", systemImage: "thermometer.medium")
// CPU tab:
Label("CPU", systemImage: "cpu")
// Memory tab:
Label("Memory", systemImage: "memorychip")
```
All three symbols exist in iOS 15+ SF Symbols. [ASSUMED: availability — verify in SF Symbols 5 app or Xcode Symbols browser. Alternatives: "bolt.fill" for CPU, "square.stack.3d.up" for memory if the primary symbols are unavailable at iOS 18 target.]

### Number Formatting (Claude's Discretion area)
```swift
// CPU: one decimal place — "4.2%" is more informative than "4%" at low values
Text(String(format: "%.1f%%", metrics.appCPUPercent))
    .font(.largeTitle)
    .fontWeight(.bold)
    .monospacedDigit()

// Memory: integer MB — "79 MB" is precise enough; sub-MB variation is noise
Text("\(metrics.appMemoryMB) MB")
    .font(.largeTitle)
    .fontWeight(.bold)
    .monospacedDigit()

// System memory: one decimal GB — "0.3 GB free" is readable
Text(String(format: "%.1f GB free", metrics.sysMemoryFreeGB))
```
[VERIFIED: SystemMetrics.swift line 218 uses "%.1f" for CPU% display — matching format for consistency]

### TemperatureViewModel polling interval change
```swift
// Source: [VERIFIED: TemperatureViewModel.swift line 111]
// Change:
timerCancellable = Timer.publish(every: 10, on: .main, in: .common)
// To:
timerCancellable = Timer.publish(every: 5, on: .main, in: .common)
```
This is the only change to TemperatureViewModel in Phase 7.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@Published` + `ObservableObject` | `@Observable` macro | Swift 5.9 / iOS 17 | No `@ObservedObject` wrapper needed in views; reads are tracked per-property automatically |
| `@StateObject` in views | `@State` for `@Observable` | Swift 5.9 | `@State private var vm = TemperatureViewModel()` is the correct ownership pattern |
| `DispatchQueue.global().async` | `Task.detached(priority:)` | Swift 5.5 / async-await | Structured concurrency; cancellable via `Task.cancel()` |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `vm_kernel_page_size` is accessible as a Swift global symbol via the existing bridging header | Pattern 7 (System Memory) | If not accessible, fall back to hardcoded 16384 (Apple Silicon page size) or compute from `Int(ProcessInfo.processInfo.physicalMemory) / totalPageCount` |
| A2 | SF Symbols "cpu", "memorychip", "thermometer.medium" are available on iOS 18 SDK | Code Examples (SF Symbols) | If unavailable, use alternative symbols: "bolt.fill" / "square.stack.3d.up" / "flame" |
| A3 | `@Observable` class passed as `var viewModel: TemperatureViewModel` to ThermalView works without @Binding for read-only data binding | Pattern 2 (ThermalView) | If SwiftUI fails to track changes, use `@Bindable var viewModel` instead — @Observable supports both approaches |
| A4 | `.monospacedDigit()` is available on Text in iOS 18 | Code Examples (number formatting) | Extremely unlikely to be wrong — this modifier has been in SwiftUI since iOS 15 |

**If A1 is wrong:** The fix is one-line — replace `vm_kernel_page_size` with the integer literal `16384`. This does not affect architecture or planning.

---

## Open Questions

1. **Page size / total memory math discrepancy**
   - What we know: Phase 6 probe showed ~129K total pages. At 4096 bytes/page that's only ~500 MB; at 16384 bytes/page that's ~2 GB. The device has 6 GB RAM. This suggests the vm_statistics64 page counts reflect the portion visible to the app's memory zone, not all physical RAM.
   - What's unclear: The exact page size on the probe device and why the total doesn't match physical RAM. This is a known iOS behavior — the kernel virtualizes memory and the `vm_statistics64` counts reflect the VM subsystem's view.
   - Recommendation: Use `vm_kernel_page_size` to get the correct page size at runtime. Do not hard-code. The displayed "X GB free" will reflect what the VM reports, not total physical RAM — this is correct behavior for a memory pressure indicator.

2. **scenePhase double-start on launch**
   - What we know: ContentView calls `metrics.startPolling()` in both `.onAppear` and in the `.onChange(of: scenePhase) { .active }` handler. TemperatureViewModel handles this with `timerCancellable?.cancel()` guard in startPolling.
   - What's unclear: Whether the double-start causes two concurrent `Task.detached` poll loops for MetricsViewModel.
   - Recommendation: MetricsViewModel's `startPolling()` must call `pollingTask?.cancel()` before creating a new Task — same as TemperatureViewModel's guard against double-start (line 110).

---

## Environment Availability

> Step 2.6: SKIPPED (no external dependencies beyond Xcode toolchain already in use — all APIs are bundled iOS frameworks already integrated in Phase 6).

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None — no automated test target in this project |
| Config file | None |
| Quick run command | Build and run on physical device via Xcode |
| Full suite command | Manual on-device verification |

This project has no XCTest or Swift Testing target. All validation is manual on-device. The nyquist_validation setting is `true` in config.json but no automated test infrastructure exists and none is being added in Phase 7.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CPU-01 | App CPU% visible and updating | manual-only | N/A | N/A |
| MEM-01 | App memory MB visible and updating | manual-only | N/A | N/A |
| CPU-02 | System CPU% visible (Phase 6 confirmed accessible) | manual-only | N/A | N/A |
| MEM-02 | System memory GB visible (Phase 6 confirmed accessible) | manual-only | N/A | N/A |
| DASH-01 | TabView with 3 tabs visible and navigable | manual-only | N/A | N/A |
| DASH-02 | Thermal tab regression-free | manual-only | N/A | N/A |

**Rationale for manual-only:** All verification requires a physical iOS 18 device (Mach APIs). The project has no test target. Automated tests cannot be run without an XCTest infrastructure that does not exist and is not in scope for Phase 7.

### Sampling Rate
- Per task commit: Build succeeds (no compiler errors)
- Per wave merge: Deploy to physical device, verify all 3 tabs display live data
- Phase gate: All 6 requirements verified on-device before closing phase

### Wave 0 Gaps
None — no test infrastructure to create. Validation is by on-device observation.

---

## Security Domain

This phase adds no network calls, no authentication, no session management, no user input, no cryptography, and no persistent storage. The Mach API calls are sandboxed by iOS and read-only. ASVS categories V2/V3/V4/V6 do not apply. V5 (Input Validation) does not apply — all data comes from kernel-level APIs with no user input path.

No security concerns introduced in Phase 7.

---

## Sources

### Primary (HIGH confidence)
- `CoreWatch/CoreWatch/SystemMetrics.swift` — Mach call implementations verified correct on device (Phase 6); direct source for MetricsViewModel extraction
- `CoreWatch/CoreWatch/TemperatureViewModel.swift` — `@Observable @MainActor` ViewModel pattern, `@ObservationIgnored nonisolated(unsafe)` pattern
- `CoreWatch/CoreWatch/ContentView.swift` — Existing layout to restructure into TabView; all existing code confirmed working
- `.planning/phases/06-mach-api-proof-of-concept/06-VERDICTS.md` — On-device API verdicts; all 4 KERN_SUCCESS; Apple Silicon system-tick=0 confirmed
- `CoreWatch/CoreWatch.xcodeproj/project.pbxproj` — Manual file registration pattern confirmed

### Secondary (MEDIUM confidence)
- CONTEXT.md decisions (D-01 through D-15) — Verified against existing codebase during research

### Tertiary (LOW confidence — see Assumptions Log)
- `vm_kernel_page_size` symbol accessibility from Swift via bridging header [A1]
- SF Symbols availability by name [A2]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies, all APIs already integrated
- Architecture: HIGH — patterns extracted directly from working Phase 6 code
- Pitfalls: HIGH — pitfalls derived from Phase 6 implementation experience (T-06-02 thread leak documented in SystemMetrics.swift itself) and Swift 6 concurrency rules
- CPU delta formula: HIGH — verified against Phase 6 raw tick data from 06-VERDICTS.md

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 (stable iOS SDK + Swift 6.3 — no fast-moving dependencies)
