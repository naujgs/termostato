# Architecture Research

**Domain:** iOS system metrics dashboard (sideloaded, single-screen SwiftUI MVVM)
**Researched:** 2026-05-14 (v1.2 — supersedes v1.1 document dated 2026-05-13)
**Confidence:** HIGH

---

## Standard Architecture

### System Overview

```
TermostatoApp (@main)
  └── ContentView
        └── TemperatureViewModel (@State, @Observable @MainActor)   ← one ViewModel, expanded
              ├── Thermal domain
              │     ├── thermalState: ProcessInfo.ThermalState
              │     └── history: [ThermalReading]                    ← ring buffer (360 entries)
              ├── CPU domain  [v1.2 new]
              │     ├── cpuUsage: Double                             ← 0.0–1.0
              │     └── cpuHistory: [SystemReading]
              ├── Memory domain  [v1.2 new]
              │     ├── memoryUsedBytes: UInt64
              │     └── memoryHistory: [SystemReading]
              ├── Battery domain  [v1.2 new]
              │     ├── batteryLevel: Float                          ← 0.0–1.0
              │     └── batteryState: UIDevice.BatteryState
              └── Notification / background state (unchanged)
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `TemperatureViewModel` | All data acquisition, state, history, alerting | `@Observable @MainActor final class` |
| `ThermalReading` (existing) | One thermal snapshot for the chart | `struct` with `id`, `timestamp`, `state` |
| `SystemReading` (new) | One numeric snapshot for CPU or memory charts | `struct` with `id`, `timestamp`, `value: Double` |
| `ContentView` | Dumb display — reads ViewModel, owns no data logic | SwiftUI `View` |
| Mach C API helpers | Pure nonisolated functions: read CPU ticks and memory | Free functions in a new `SystemMetrics.swift` file |

---

## Recommended Project Structure

```
Termostato/
├── TemperatureViewModel.swift   # expanded — CPU/memory/battery properties added
├── ContentView.swift            # expanded — new metric panels
├── ThermalReading.swift         # (extract if currently inline) unchanged
├── SystemReading.swift          # NEW — shared value type for CPU and memory history
├── SystemMetrics.swift          # NEW — nonisolated free functions wrapping Mach C APIs
└── Termostato-Bridging-Header.h # unchanged — Mach headers already available via SDK
```

### Structure Rationale

- **`SystemMetrics.swift`:** Isolates all Mach C API calls into `nonisolated` free functions. They have no actor context, return plain Swift value types, and are trivially testable. Keeps ViewModel clean of low-level pointer arithmetic.
- **`SystemReading.swift`:** A single `struct SystemReading: Identifiable` shared by CPU history and memory history arrays. Avoids duplicating an identical type twice.
- Everything else stays in the existing two files — no services layer, no coordinator, no DI container. The app is a single-screen tool; structural overhead would add zero value.

---

## Architectural Patterns

### Pattern 1: One Expanded ViewModel (Not Multiple ViewModels)

**What:** Keep a single `TemperatureViewModel` and add CPU, memory, and battery properties to it rather than splitting into `CPUViewModel`, `MemoryViewModel`, etc.

**When to use:** When all data sources share the same polling cadence, the same notification cooldown logic, and are displayed on the same screen with no navigation between them.

**Trade-offs:**
- Pro: Single source of truth. `ContentView` reads one `@State` object. `scenePhase` lifecycle hooks call one `startPolling()` / `stopPolling()`. Cooldown logic and background task management stay in one place.
- Pro: All `@Observable` mutation stays on `@MainActor`. No cross-actor coordination needed.
- Con: File grows to ~600–700 lines. Acceptable for a personal tool. Mitigate by extracting Mach helpers to `SystemMetrics.swift`.
- Reject split ViewModels because: SwiftUI `@State` ownership requires the ViewModel to live in `ContentView`. Multiple `@State` ViewModels on a single `ContentView` is awkward — you cannot inject one into another without a `@Bindable` or `@Environment` hop that adds complexity for no gain.

**Example (adding CPU to the existing ViewModel):**
```swift
@Observable
@MainActor
final class TemperatureViewModel {
    // --- existing ---
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    private(set) var history: [ThermalReading] = []

    // --- v1.2 additions ---
    private(set) var cpuUsage: Double = 0          // 0.0 – 1.0
    private(set) var cpuHistory: [SystemReading] = []
    private(set) var memoryUsedBytes: UInt64 = 0
    private(set) var memoryHistory: [SystemReading] = []
    private(set) var batteryLevel: Float = 0
    private(set) var batteryState: UIDevice.BatteryState = .unknown
}
```

### Pattern 2: Mach C API Calls via nonisolated Free Functions

**What:** Wrap `host_cpu_load_info` and `task_vm_info` in `nonisolated` free functions that return plain Swift value types. Call those functions synchronously from the `@MainActor` ViewModel's poll method.

**When to use:** Whenever a C API is synchronous, sub-millisecond, and returns a value type (not a class or reference type that would need `Sendable` conformance).

**Trade-offs:**
- Pro: No concurrency boundary crossing. Swift 6 strict concurrency is fully satisfied because the C call site is on `@MainActor` and the result is a plain value type.
- Pro: No `Task.detached` or `await` required. The call is inlined in the existing synchronous `updateThermalState()`.
- Pro: `nonisolated` free functions can be called from any isolation context — no actor annotation needed.
- Con: The Mach call blocks the main thread for the duration of the kernel call (~0.05–0.5 ms). This is the same as `ProcessInfo.processInfo.thermalState`, which already blocks the main thread. Acceptable at 10s polling cadence.
- Reject `Task.detached` pattern because: it would require crossing an actor boundary to store the result (back on `@MainActor`), adding `await`, and making the update non-atomic. The synchronous call is strictly simpler and correct.

**Swift 6 concurrency rules for C APIs (HIGH confidence):**
- C functions imported from Mach headers (`host_statistics`, `task_info`, etc.) are global C functions. Swift treats them as `nonisolated`.
- They can be called from any isolation context (including `@MainActor`) without a concurrency boundary crossing.
- Their arguments and return values are C types (`integer_t`, `mach_msg_type_number_t`, etc.) — not Swift types, not `Sendable`. The Swift concurrency checker does not reason about them.
- The only Swift types that must be `Sendable` are values that cross actor boundaries. If the Mach call is made and its result consumed within the same `@MainActor` method, nothing crosses a boundary.

**Example — CPU usage nonisolated helper in `SystemMetrics.swift`:**
```swift
import Darwin

// Stored once; mach_host_self() allocates a kernel port — do not call per-poll.
// nonisolated(unsafe) because it is a C port value, not a Swift Sendable type.
private nonisolated(unsafe) let _machHost: mach_port_t = mach_host_self()

// Previous tick snapshot for delta calculation. Must persist across calls.
// nonisolated(unsafe) is correct here: this variable is accessed only from
// updateSystemMetrics(), which is always called on @MainActor. No concurrent
// access is possible. The unsafe annotation documents the invariant.
private nonisolated(unsafe) var _previousCPULoad = host_cpu_load_info()

/// Returns current CPU usage as a fraction 0.0–1.0, or nil on kernel error.
/// Nonisolated: pure C calls, returns a value type. Safe to call from @MainActor.
nonisolated func readCPUUsage() -> Double? {
    var info = host_cpu_load_info()
    var count = HOST_CPU_LOAD_INFO_COUNT
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(_machHost, HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }

    let user = Double(info.cpu_ticks.0 - _previousCPULoad.cpu_ticks.0)
    let sys  = Double(info.cpu_ticks.1 - _previousCPULoad.cpu_ticks.1)
    let idle = Double(info.cpu_ticks.2 - _previousCPULoad.cpu_ticks.2)
    let nice = Double(info.cpu_ticks.3 - _previousCPULoad.cpu_ticks.3)
    let total = user + sys + idle + nice
    _previousCPULoad = info
    guard total > 0 else { return nil }
    return (user + sys + nice) / total
}
```

**Important:** The first call to `readCPUUsage()` will return an inaccurate result (delta against zeroed initial state). Discard the first sample or pre-warm by calling once in `init()` and discarding the result. The second and subsequent calls at 10s intervals are accurate.

**Example — App memory footprint helper:**
```swift
/// Returns app physical memory footprint in bytes, or nil on kernel error.
/// Uses task_vm_info / phys_footprint — matches Xcode Debug Navigator's value.
/// Do NOT use mach_task_basic_info.resident_size — it diverges from Instruments.
nonisolated func readMemoryFootprint() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, TASK_VM_INFO, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return info.phys_footprint
}
```

**Note on `TASK_VM_INFO_COUNT` and `TASK_VM_INFO_REV1_COUNT`:** These constants are not auto-imported by the Swift C importer in some SDK versions. Compute `count` manually from `MemoryLayout` as shown above — this is the standard workaround documented in Apple Developer Forums.

### Pattern 3: Battery via UIDevice — Event-Driven, Not Polled

**What:** Enable battery monitoring once in `startPolling()`, then read `UIDevice.current.batteryLevel` and `.batteryState` synchronously on each poll tick. Optionally supplement with `UIDeviceBatteryLevelDidChange` notification for between-tick updates.

**When to use:** Battery state changes slowly (level changes ~0.03%/min at idle). The 10s polling cadence is more than sufficient. No dedicated battery timer needed.

**Trade-offs:**
- Pro: `UIDevice` properties are public API, sandbox-safe, no entitlements needed.
- Pro: Stays on `@MainActor` — `UIDevice.current` must be accessed on the main thread (UIKit main-thread rule, same as all UIKit APIs). Since the ViewModel is `@MainActor`, this is already satisfied.
- Pro: `isBatteryMonitoringEnabled` is a one-time toggle, not a resource that needs lifecycle management.
- Con: Level is a `Float` with ~1% granularity on hardware.

**Example:**
```swift
// In startPolling():
UIDevice.current.isBatteryMonitoringEnabled = true

// In updateSystemMetrics() — called from the existing 10s timer:
batteryLevel = UIDevice.current.batteryLevel   // -1.0 if monitoring not enabled
batteryState = UIDevice.current.batteryState   // .unknown if monitoring not enabled
```

**No `Task.detached` needed.** `UIDevice` reads are synchronous and sub-microsecond. The `@MainActor` isolation of the ViewModel satisfies UIKit's main-thread requirement automatically.

### Pattern 4: Shared 10s Timer, One Combined Update Method

**What:** All three new metrics (CPU, memory, battery) are sampled in the same timer callback as the existing thermal state read. No separate timers.

**When to use:** Always, for this app. CPU and memory are O(microseconds) to read. Battery is O(nanoseconds). Separate timers add complexity with zero benefit.

**What changes in `updateThermalState()`:** Rename it to `updateAllMetrics()` (or keep the name and expand it). Add CPU, memory, and battery reads after the thermal state read.

**Cadence rationale:**
- CPU: 10s is appropriate. CPU usage is a rolling average; sub-10s cadence would create noise rather than signal.
- Memory: 10s is appropriate. App memory footprint changes slowly under normal use.
- Battery: 10s is appropriate. Battery level changes on the order of minutes.
- Thermal: Already 10s. No change.

**Example:**
```swift
private func updateAllMetrics() {
    // Thermal (existing)
    thermalState = ProcessInfo.processInfo.thermalState
    let thermalReading = ThermalReading(timestamp: Date(), state: thermalState)
    appendToHistory(&history, thermalReading, max: Self.maxHistory)
    checkAndFireNotification()

    // CPU (new)
    if let usage = readCPUUsage() {
        cpuUsage = usage
        let cpuReading = SystemReading(timestamp: Date(), value: usage)
        appendToHistory(&cpuHistory, cpuReading, max: Self.maxHistory)
    }

    // Memory (new)
    if let bytes = readMemoryFootprint() {
        memoryUsedBytes = bytes
        let memReading = SystemReading(timestamp: Date(), value: Double(bytes))
        appendToHistory(&memoryHistory, memReading, max: Self.maxHistory)
    }

    // Battery (new)
    batteryLevel = UIDevice.current.batteryLevel
    batteryState = UIDevice.current.batteryState
}
```

### Pattern 5: Mach Port Lifecycle — Acquire Once, Reuse Forever

**What:** Call `mach_host_self()` once at module initialization and store the result in a file-private constant. Never call it per poll tick.

**Why:** `mach_host_self()` allocates a kernel port right on every call. The returned port represents the same kernel host object each time, but each call allocates a new name in the process's Mach port namespace, consuming a finite kernel resource. Calling it at 10s intervals for hours would leak port names. Store once, reuse forever.

**Evidence:** SystemKit (widely referenced iOS/macOS system monitoring library) uses exactly this pattern — `static let machHost = mach_host_self()` initialized once at the struct level.

**Contrast with `mach_task_self_`:** This is a macro/global that is always valid — no allocation, no call needed. Use it directly in `task_info()`.

**`IOKit` services in `readIOKitTemperature()` (existing v1.1 code):** The current pattern of acquiring the service per call and releasing it with `defer { IOObjectRelease(service) }` is correct for IOKit — do not cache the io_object_t across calls. IOKit objects have reference-counted lifetimes and the service reference may become stale.

### Pattern 6: UI Organization — Vertical ScrollView with Metric Cards

**What:** Replace the existing `VStack` root in `ContentView` with a `ScrollView` containing a vertical stack of metric cards. Each card is a standalone SwiftUI subview.

**When to use:** When content exceeds the visible screen height on smaller devices (iPhone SE), or when new panels will be added iteratively.

**Why not TabView:** The data is all related system health info — a user glancing at this app wants to see everything at once, not switch tabs. TabView implies independent, non-simultaneous concerns. Metrics on a dashboard are complementary, not alternative.

**Why not expanding cards (DisclosureGroup):** Adds unnecessary interaction for a glance-first tool. The user opens the app to see the state — hiding data behind a tap creates friction.

**Recommended card layout:**
```
ScrollView (vertical)
  VStack(spacing: 16)
    ┌─ App header "Termostato" ─────────────────────────────┐
    │                                                        │
    ├─ ThermalCard ─────────────────────────────────────────┤
    │  Colored badge (Nominal/Fair/Serious/Critical)         │
    │  Thermal history chart (existing)                      │
    │                                                        │
    ├─ CPUCard ─────────────────────────────────────────────┤
    │  "CPU" label + current % (large number)                │
    │  Mini line chart (cpuHistory)                          │
    │                                                        │
    ├─ MemoryCard ──────────────────────────────────────────┤
    │  "Memory" label + current MB (large number)            │
    │  Mini line chart (memoryHistory)                       │
    │                                                        │
    └─ BatteryCard ─────────────────────────────────────────┘
       Battery level % + charging state badge
       No chart needed — level changes too slowly to be useful
```

**Subview decomposition:** Extract each card into a private SwiftUI `View` struct within `ContentView.swift`, or as separate files if the file grows past ~300 lines. Pass ViewModel data as value-type parameters (not the ViewModel itself) to keep cards self-contained and previewable.

**Example card struct:**
```swift
private struct CPUCard: View {
    let usage: Double          // 0.0–1.0
    let history: [SystemReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CPU")
                .font(.headline)
            Text(String(format: "%.0f%%", usage * 100))
                .font(.largeTitle.monospacedDigit())
            // Mini chart...
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}
```

---

## Data Flow

### Poll Cycle (Foreground, every 10s)

```
Timer.publish(every: 10) → onReceive
    → updateAllMetrics()
          ├── ProcessInfo.processInfo.thermalState    (public, sync, main thread)
          ├── readCPUUsage()                          (nonisolated C call, sync, <1ms)
          ├── readMemoryFootprint()                   (nonisolated C call, sync, <1ms)
          └── UIDevice.current.batteryLevel/State     (UIKit, sync, main thread)
    → @Observable mutation (all properties)
    → SwiftUI auto-redraw (ContentView and card subviews)
```

### Background Path (unchanged from v1.1)

```
thermalStateDidChangeNotification
    → handleBackgroundThermalChange()
          → ProcessInfo.processInfo.thermalState
          → checkAndFireNotification()
    NOTE: CPU/memory/battery NOT read in background path.
          beginBackgroundTask window is ~30s; only thermal alerting needed.
```

### Key Data Flows

1. **CPU history:** `readCPUUsage()` returns `Double?`. On non-nil: append `SystemReading(timestamp: Date(), value: usage)` to `cpuHistory[]` ring buffer. Same ring-buffer mechanics as `history[]`.
2. **Memory history:** Same pattern as CPU, value is `Double(memoryUsedBytes)` in bytes. Format as MB in the View (`value / 1_048_576`).
3. **Battery:** No history array. Display current level and state only. Level changes are too slow (~1 reading/min perceptible change) to make a chart meaningful.

---

## Scaling Considerations

This is a personal single-device tool — scaling in the user-count sense is not applicable. Relevant scaling is complexity growth as features are added.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 3–4 metrics (current target) | Single ViewModel, expanded `updateAllMetrics()`, no service layer needed |
| 6–8 metrics | Consider extracting Mach helpers to a dedicated `SystemMetrics` actor or struct with static methods; ViewModel stays as coordinator |
| >8 metrics or multi-screen | Services layer warranted; each domain (thermal, cpu, memory, network) becomes a focused model object injected into a coordinator ViewModel |

### Scaling Priorities

1. **First constraint:** `updateAllMetrics()` method length. At 4 metrics with history appends it will be ~40 lines. Beyond ~80 lines, extract per-domain helpers (`updateCPUMetrics()`, etc.) called from a single orchestrator method.
2. **Second constraint:** `ContentView.swift` file length. At 4 metric cards it will reach ~300 lines. Extract cards to separate files before the file becomes hard to navigate.

---

## Anti-Patterns

### Anti-Pattern 1: Multiple ViewModels for a Single-Screen Dashboard

**What people do:** Create `CPUViewModel`, `MemoryViewModel`, `BatteryViewModel` alongside `TemperatureViewModel`.

**Why it's wrong:** All four data sources share the same timer, the same `scenePhase` lifecycle hooks, and the same screen. Splitting forces `ContentView` to hold multiple `@State` ViewModel instances with no coordination between them — polling cadence, cooldown logic, and background task management must be duplicated or synchronized manually. This is pure overhead.

**Do this instead:** One `TemperatureViewModel` renamed (optionally) to `SystemViewModel` or `DashboardViewModel`, with all metric properties consolidated.

### Anti-Pattern 2: Task.detached for Mach C API Calls

**What people do:** Wrap `host_cpu_load_info` in `Task.detached { ... }` to "avoid blocking the main thread."

**Why it's wrong:** The Mach calls complete in under 1ms — the same order of magnitude as `ProcessInfo.processInfo.thermalState` (which is already called on main). Offloading to a detached task requires an actor-boundary crossing to write the result back to `@MainActor` properties, adding `await`, making the update asynchronous, and potentially causing a frame where the UI shows stale data. The complexity buys nothing.

**Do this instead:** Call synchronously from the `@MainActor` method. If a Mach call ever takes >1ms (it won't for these APIs), profile first, then optimize.

### Anti-Pattern 3: Calling mach_host_self() Per Poll Tick

**What people do:** Call `mach_host_self()` inside `readCPUUsage()` on every timer fire.

**Why it's wrong:** Each call allocates a new Mach port name in the process namespace, a finite kernel resource. Over hours of polling at 10s intervals this is ~360 leaked port names per hour. Mach port exhaustion causes crashes.

**Do this instead:** Store the result once in a file-private `nonisolated(unsafe) let` constant at module scope. Mark `nonisolated(unsafe)` because it is a C integer type that the Swift concurrency system cannot verify as `Sendable` — but it is safe in practice because it is a read-only constant after initialization.

### Anti-Pattern 4: Using resident_size for Memory Display

**What people do:** Use `mach_task_basic_info.resident_size` because it is simpler to obtain.

**Why it's wrong:** `resident_size` does not match what Xcode's Debug Navigator shows and diverges significantly from Instruments. Users who cross-reference the app's reading against Xcode will see different numbers and distrust the app.

**Do this instead:** Use `task_vm_info_data_t.phys_footprint` via `task_info(mach_task_self_, TASK_VM_INFO, ...)`. It matches Xcode's memory gauge exactly.

### Anti-Pattern 5: TabView for Multi-Metric Dashboard

**What people do:** Put each metric in a TabView tab so the screen does not feel crowded.

**Why it's wrong:** A health dashboard's value is seeing all signals simultaneously. A tab forces the user to swipe to find the metric they care about — exactly when they are anxious about device health. ScrollView preserves the simultaneous-glance model.

**Do this instead:** Vertical `ScrollView` with compact metric cards. Each card shows the current value prominently and a mini chart below it. The thermal badge stays at the top as the primary signal.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Mach kernel (`host_statistics`) | Direct C call via Darwin import | No bridging header needed — Darwin module auto-imported in Swift |
| Mach kernel (`task_info`) | Direct C call via Darwin import | Same — `mach_task_self_` macro available |
| `UIDevice` (battery) | Synchronous property read on `@MainActor` | Must enable `isBatteryMonitoringEnabled` before first read |
| `ProcessInfo` (thermal) | Unchanged from v1.1 | |
| `UNUserNotificationCenter` (alerts) | Unchanged from v1.1 | |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `SystemMetrics.swift` → `TemperatureViewModel` | Direct function call (nonisolated → @MainActor, no crossing) | Return plain value types (`Double?`, `UInt64?`) |
| `TemperatureViewModel` → `ContentView` | `@Observable` auto-tracking | View reads properties; no explicit binding needed |
| `ContentView` → Card subviews | Value-type parameters (not the ViewModel) | Keeps subviews previewable and self-contained |

---

## Build Order for v1.2

```
1. SystemReading.swift (new value type)
   → No dependencies. Unblocks CPU and memory history arrays.
   → ~10 lines. Verifiable in isolation.

2. SystemMetrics.swift (nonisolated Mach helpers)
   → Depends on: Darwin import (built-in, no changes needed).
   → Implement readCPUUsage() and readMemoryFootprint().
   → Test: call both from a temp debug print in startPolling() before wiring to history.
   → First CPU reading will be inaccurate (delta vs zeroed baseline); discard by calling once in init().

3. TemperatureViewModel — new properties and updateAllMetrics()
   → Depends on: SystemReading.swift, SystemMetrics.swift.
   → Add cpuUsage, cpuHistory, memoryUsedBytes, memoryHistory, batteryLevel, batteryState.
   → Enable UIDevice.current.isBatteryMonitoringEnabled = true in startPolling().
   → Rename/expand updateThermalState() → updateAllMetrics().
   → Simulator will show CPU and memory (they work in simulator). Battery requires device.

4. ContentView — ScrollView refactor + new metric cards
   → Depends on: TemperatureViewModel step above.
   → Replace VStack root with ScrollView { VStack }.
   → Add CPUCard, MemoryCard, BatteryCard as private subviews.
   → Thermal card is the existing badge + chart, extracted into a ThermalCard subview.
   → Test on simulator first; no device required until battery display.

5. Device verification
   → CPU and memory: verify values are plausible (cpu 0–100%, memory matches Xcode gauge).
   → Battery: verify level and state update when plugged/unplugged.
   → All notification and background behavior: regression test unchanged paths.
```

**Rationale for this order:** Steps 1–2 are pure additions with no risk to existing behavior. Step 3 expands the ViewModel — the rename of `updateThermalState()` is the highest-risk edit (one call site in `startPolling()`). Step 4 refactors the View — the ScrollView change is structural but ContentView has no unit tests, so visual inspection is the gate. Step 5 is device-gated but non-blocking for steps 1–4.

---

## Sources

- `TemperatureViewModel.swift` (existing, read 2026-05-14) — `@Observable @MainActor` pattern, Timer.publish on .main, existing ring buffer mechanics
- `ContentView.swift` (existing, read 2026-05-14) — VStack root structure, scenePhase hook, chart subview
- [SystemKit/System.swift — beltex/SystemKit (GitHub)](https://github.com/beltex/SystemKit/blob/master/SystemKit/System.swift) — `static let machHost = mach_host_self()` one-time init pattern; delta tick CPU calculation; MEDIUM confidence (community library, widely referenced)
- [SystemEye/CPU.swift — zixun/SystemEye (GitHub)](https://github.com/zixun/SystemEye/blob/master/SystemEye/Classes/CPU.swift) — `host_statistics` with `withUnsafeMutablePointer`/`withMemoryRebound` pattern; MEDIUM confidence
- [phys_footprint — Apple Developer Documentation](https://developer.apple.com/documentation/kernel/task_vm_info_data_t/1553210-phys_footprint) — physical footprint definition; HIGH confidence
- [Apple Developer Forums: how XCode calculates Memory](https://developer.apple.com/forums/thread/105088) — `phys_footprint` vs `resident_size` divergence; MEDIUM confidence
- [Apple Developer Forums: how to get iOS app specific heap memory usage](https://forums.developer.apple.com/thread/119906) — `TASK_VM_INFO` count calculation via MemoryLayout; MEDIUM confidence
- [Mach Port Leakage — Apple Developer Forums](https://developer.apple.com/forums/thread/110688) — port allocation per `mach_host_self()` call; MEDIUM confidence
- [Adopting strict concurrency in Swift 6 — Apple Developer Documentation](https://developer.apple.com/documentation/swift/adoptingswift6) — nonisolated, C global import rules; HIGH confidence
- [batteryState — Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uidevice/batterystate-swift.property) — requires `isBatteryMonitoringEnabled = true`; HIGH confidence
- [Exploring concurrency changes in Swift 6.2 — Donny Wals](https://www.donnywals.com/exploring-concurrency-changes-in-swift-6-2/) — approachable concurrency, MainActor defaults; HIGH confidence

---
*Architecture research for: Termostato v1.2 — system metrics integration*
*Researched: 2026-05-14*
