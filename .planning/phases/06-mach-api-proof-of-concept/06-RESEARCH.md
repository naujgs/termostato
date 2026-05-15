# Phase 6: Mach API Proof-of-Concept - Research

**Researched:** 2026-05-15
**Domain:** Darwin/Mach kernel APIs for CPU and memory statistics on iOS 18
**Confidence:** MEDIUM

## Summary

Phase 6 is a validation phase: build minimal probe code that calls three Mach kernel APIs (`host_statistics` for system CPU, `host_statistics64` for system memory, `task_info` for per-process metrics) on a physical iOS 18 device and document which ones return valid data under the free Apple ID sideload sandbox.

The iOS SDK (iPhoneOS 26.4) includes all required Mach headers (`mach/mach.h`, `mach/host_info.h`, `mach/task_info.h`, `mach/thread_info.h`) and the existing bridging header already imports `<mach/mach.h>`. The code will compile. The open question -- which is the entire point of this phase -- is whether the iOS 18 sandbox blocks these calls at runtime (returning `KERN_FAILURE`) or silently degrades them (returning `KERN_SUCCESS` with zeroed data).

**Primary recommendation:** Implement all three probes in pure Swift using `withUnsafeMutablePointer` (no C wrapper needed since `<mach/mach.h>` is already bridged). The bridging header already exists and imports the right header. Per-process `task_info` is very likely to work; system-wide `host_statistics`/`host_statistics64` have uncertain status that only physical device testing can resolve.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Create a separate `SystemMetrics.swift` file for all Mach API probe code. Do not extend TemperatureViewModel -- keep probe logic isolated from shipped thermal code.
- **D-02:** Probe all three APIs in one pass: `host_statistics` (system CPU), `host_statistics64` (system memory), and `task_info` (per-process CPU/memory). This covers everything Phase 7 might need.
- **D-03:** Claude's Discretion -- choose the best engineering approach (Swift-only via `withUnsafeMutablePointer` or bridging header with C wrapper) based on conventions and scalability.
- **D-04:** Add a temporary debug screen as a SwiftUI `.sheet()` overlay showing per-API status (accessible/degraded/blocked with color coding). Thermal dashboard stays intact underneath.
- **D-05:** The debug sheet is triggered by a hidden gesture or button -- it is throwaway UI for Phase 6 validation only.
- **D-06:** Use three-tier classification: **Accessible** (KERN_SUCCESS + non-zero plausible data), **Degraded** (KERN_SUCCESS but zeroed or stale data), **Blocked** (KERN_FAILURE or other error code).
- **D-07:** Take 3 samples per API over 30 seconds (10s spacing, matching the existing polling interval). Final verdict = majority result across the 3 samples.
- **D-08:** Write a structured verdict report as `06-VERDICTS.md` in the phase directory.
- **D-09:** Include raw evidence alongside each verdict: `kern_return_t` codes, actual sample data values, and timestamps.

### Claude's Discretion
- Internal structure of SystemMetrics.swift (method signatures, return types, error handling patterns)
- Debug sheet layout and visual design (as long as it shows per-API status clearly)
- How the 3-sample probe sequence is triggered (automatic on sheet open, manual button, etc.)
- Console logging format and verbosity

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CPU-02 | User can see system-wide CPU usage if iOS 18 sandbox permits (graceful fallback to hidden if `host_statistics` is blocked) | Probe `host_statistics` with `HOST_CPU_LOAD_INFO` flavor; verdict determines Phase 7 go/no-go |
| MEM-02 | User can see system-wide memory usage (free/used) if iOS 18 sandbox permits (graceful fallback to hidden if `host_statistics64` is blocked) | Probe `host_statistics64` with `HOST_VM_INFO64` flavor; verdict determines Phase 7 go/no-go |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Language:** Swift 6.3 (ships with Xcode 26.4.1) -- strict concurrency default-on, use `@MainActor`
- **UI:** SwiftUI only, no UIKit views
- **Architecture:** MVVM with single ViewModel pattern (`@Observable`, `@MainActor`)
- **Dependencies:** Zero external dependencies -- Apple frameworks only
- **Deployment target:** iOS 18.x minimum
- **Polling pattern:** `Timer.publish(every: 10, ...)` with `startPolling()`/`stopPolling()` lifecycle
- **Bridging header:** Already exists at `Termostato/Termostato/Termostato-Bridging-Header.h` with `#import <mach/mach.h>` and IOKit declarations
- **Console logging:** `print("[Termostato] ...")` format

## Standard Stack

### Core (all built-in, zero dependencies)
| Framework | Source | Purpose | Notes |
|-----------|--------|---------|-------|
| `mach/mach.h` | Darwin kernel headers (via bridging header) | `host_statistics`, `host_statistics64`, `task_info`, `mach_host_self()`, `mach_task_self_` | Already imported in bridging header [VERIFIED: local filesystem] |
| `mach/host_info.h` | Darwin kernel headers (included by mach.h) | `HOST_CPU_LOAD_INFO` (flavor 3), `HOST_VM_INFO64` (flavor 4), `host_cpu_load_info_data_t`, `vm_statistics64_data_t` | [VERIFIED: iOS SDK header at iPhoneOS26.4.sdk] |
| `mach/task_info.h` | Darwin kernel headers (included by mach.h) | `MACH_TASK_BASIC_INFO` (flavor 20), `TASK_VM_INFO` (flavor 22), `mach_task_basic_info_data_t` | [VERIFIED: iOS SDK header] |
| `mach/thread_info.h` | Darwin kernel headers (included by mach.h) | `THREAD_BASIC_INFO` (flavor 3), `thread_basic_info_data_t` with `cpu_usage` field | [VERIFIED: iOS SDK header] |
| SwiftUI | Apple built-in | Debug sheet overlay | Existing pattern in ContentView |

### No Installation Required
All APIs are kernel headers available through the existing bridging header. No SPM packages, no CocoaPods, no additional frameworks.

## Architecture Patterns

### Recommended Project Structure
```
Termostato/Termostato/
├── SystemMetrics.swift          # NEW: Mach API probe code (D-01)
├── MachProbeDebugView.swift     # NEW: Debug sheet UI (D-04)
├── TemperatureViewModel.swift   # UNCHANGED
├── ContentView.swift            # MODIFIED: add .sheet() for debug view
├── Termostato-Bridging-Header.h # UNCHANGED (already has mach/mach.h)
├── NotificationDelegate.swift   # UNCHANGED
└── TermostatoApp.swift          # UNCHANGED
```

### Pattern 1: Swift-only Mach API Calls (D-03 Recommendation)

**Recommendation: Pure Swift with `withUnsafeMutablePointer`.** No C wrapper needed.

**Rationale:** The bridging header already imports `<mach/mach.h>`, which makes all Mach C functions and types available directly in Swift. A C wrapper would add a file and indirection for no benefit. The `withUnsafeMutablePointer` + `withMemoryRebound` pattern is the established Swift idiom for these calls, used by SystemKit, GDPerformanceView-Swift, and Apple's own documentation. [VERIFIED: SystemKit source code on GitHub, iOS SDK headers]

**Example -- host_statistics for CPU:**
```swift
// Source: SystemKit (github.com/beltex/SystemKit) + iOS SDK headers
func probeSystemCPU() -> (kern_return_t, host_cpu_load_info?) {
    var loadInfo = host_cpu_load_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result: kern_return_t = withUnsafeMutablePointer(to: &loadInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    return (result, result == KERN_SUCCESS ? loadInfo : nil)
}
```

**Example -- host_statistics64 for Memory:**
```swift
// Source: SystemKit + iOS SDK headers
func probeSystemMemory() -> (kern_return_t, vm_statistics64?) {
    var vmStat = vm_statistics64()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result: kern_return_t = withUnsafeMutablePointer(to: &vmStat) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    return (result, result == KERN_SUCCESS ? vmStat : nil)
}
```

**Example -- task_info for Per-Process Memory:**
```swift
// Source: github.com/pejalo gist + iOS SDK headers
func probeTaskMemory() -> (kern_return_t, mach_task_basic_info?) {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MACH_TASK_BASIC_INFO_COUNT)
    let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return (result, result == KERN_SUCCESS ? info : nil)
}
```

**Example -- Per-Process CPU via thread enumeration:**
```swift
// Source: GDPerformanceView-Swift pattern
func probeTaskCPU() -> (kern_return_t, Double?) {
    var threadList: thread_act_array_t?
    var threadCount: mach_msg_type_number_t = 0
    let result = task_threads(mach_task_self_, &threadList, &threadCount)
    guard result == KERN_SUCCESS, let threads = threadList else {
        return (result, nil)
    }
    var totalUsage: Double = 0
    for i in 0..<Int(threadCount) {
        var info = thread_basic_info()
        var infoCount = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
            }
        }
        if kr == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
            totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }
    }
    // Deallocate thread list
    let size = vm_size_t(MemoryLayout<thread_act_t>.size * Int(threadCount))
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
    return (KERN_SUCCESS, totalUsage)
}
```

### Pattern 2: Three-Tier Verdict Classification (D-06)

```swift
enum APIVerdict: String {
    case accessible = "Accessible"   // KERN_SUCCESS + non-zero plausible data
    case degraded   = "Degraded"     // KERN_SUCCESS but zeroed or stale data
    case blocked    = "Blocked"      // KERN_FAILURE or other error code
}
```

**Plausibility checks for "accessible" vs "degraded":**
- CPU: `cpu_ticks` tuple should have non-zero values (at least idle ticks > 0)
- Memory: `free_count + active_count + inactive_count + wire_count > 0`
- Task memory: `resident_size > 0` (app is running, so it must use some memory)
- Task CPU: `totalUsage >= 0` (can legitimately be near-zero)

### Pattern 3: Concurrency Model (matches existing codebase)

SystemMetrics should follow the same `@MainActor` isolation pattern as TemperatureViewModel:
```swift
@Observable
@MainActor
final class SystemMetricsProbe {
    // probe state, results, verdict
}
```

This keeps the debug sheet's data binding simple and matches the established pattern. [VERIFIED: TemperatureViewModel.swift in codebase]

### Anti-Patterns to Avoid
- **Extending TemperatureViewModel:** D-01 explicitly forbids this. Keep probe code isolated.
- **Using DispatchQueue for timer:** The codebase uses `Timer.publish` with Combine. Don't introduce a different timing mechanism.
- **Calling Mach APIs from background thread without MainActor hop:** The Mach calls themselves are thread-safe, but updating `@Observable` state must happen on MainActor.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mach type sizes | Manual byte counting | `MemoryLayout<T>.size / MemoryLayout<integer_t>.size` | Correct on both arm64 and simulator |
| Thread list cleanup | Forgetting to deallocate | `vm_deallocate(mach_task_self_, ...)` after `task_threads()` | Leaks mach ports otherwise |
| Per-process CPU % | Custom tick-delta calculation | `thread_basic_info.cpu_usage / TH_USAGE_SCALE` | Kernel already computes a scaled percentage |

## Common Pitfalls

### Pitfall 1: Forgetting to Deallocate Thread List
**What goes wrong:** `task_threads()` allocates a mach port array via the kernel. If not deallocated with `vm_deallocate()`, each probe leaks memory proportional to thread count.
**Why it happens:** Swift's ARC doesn't manage Mach-allocated memory.
**How to avoid:** Always pair `task_threads()` with `vm_deallocate()` in a defer block.
**Warning signs:** Memory growth visible in Instruments over repeated probes.

### Pitfall 2: Wrong Count Type for host_statistics vs host_statistics64
**What goes wrong:** Using `HOST_VM_INFO_COUNT` (32-bit struct) with `host_statistics64` or vice versa causes buffer overrun or truncated data.
**Why it happens:** The 32-bit and 64-bit variants have different struct sizes.
**How to avoid:** Match flavor to function: `HOST_VM_INFO` with `host_statistics`, `HOST_VM_INFO64` with `host_statistics64`. Compute count from the matching struct type.
**Warning signs:** Garbage data in high fields of the struct.

### Pitfall 3: Confusing mach_task_self_ (variable) with mach_task_self() (function)
**What goes wrong:** `mach_task_self()` is a function on macOS but on iOS/arm64 `mach_task_self_` is the global variable. Using the wrong one may compile but behave differently.
**Why it happens:** Platform differences in Mach headers.
**How to avoid:** Use `mach_task_self_` (the global) in Swift -- it's what the iOS SDK exposes. [VERIFIED: iOS SDK headers]
**Warning signs:** Compilation warnings about function vs variable.

### Pitfall 4: Swift 6 Strict Concurrency and Mach Calls
**What goes wrong:** Mach API calls are synchronous C functions. If called from a nonisolated context, Swift 6 may warn about sendability when passing results to `@MainActor` code.
**Why it happens:** Swift 6 strict concurrency is default-on.
**How to avoid:** Keep probe methods on `@MainActor` (the Mach calls are fast -- microseconds). Or if you want off-main-thread, wrap the entire probe in a `Task` and use `@MainActor` to publish results.
**Warning signs:** Swift concurrency warnings at compile time.

### Pitfall 5: KERN_SUCCESS with Zeroed Data (the "Degraded" Case)
**What goes wrong:** The kernel returns `KERN_SUCCESS` but fills the struct with zeros. Code that only checks `kern_return_t` would report success when data is useless.
**Why it happens:** Apple may silently neuter APIs rather than fail them outright -- returning success with empty data avoids breaking app launch.
**How to avoid:** Always validate data plausibility after checking return code (D-06 three-tier classification).
**Warning signs:** All fields are zero despite KERN_SUCCESS.

## Code Examples

### Complete SystemMetrics Probe Structure
```swift
// Source: Synthesized from iOS SDK headers + SystemKit patterns + project conventions
import Foundation
import Observation

struct MachProbeResult {
    let api: String
    let kernReturn: kern_return_t
    let verdict: APIVerdict
    let rawData: String          // Human-readable dump of values
    let timestamp: Date
}

enum APIVerdict: String {
    case accessible = "Accessible"
    case degraded   = "Degraded"
    case blocked    = "Blocked"
}

@Observable
@MainActor
final class SystemMetricsProbe {
    private(set) var results: [MachProbeResult] = []
    private(set) var isProbing: Bool = false
    private(set) var samplesCompleted: Int = 0
    
    // 3 samples at 10s intervals (D-07)
    func runProbeSequence() { /* ... */ }
}
```

### Debug Sheet Integration Point
```swift
// In ContentView.swift -- add .sheet() modifier
@State private var showDebugSheet = false

// Hidden trigger (D-05): long press on title
Text("Termostato")
    .onLongPressGesture { showDebugSheet = true }

.sheet(isPresented: $showDebugSheet) {
    MachProbeDebugView()
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `host_statistics` with `HOST_VM_INFO` (32-bit) | `host_statistics64` with `HOST_VM_INFO64` (64-bit) | iOS 8+ | Use 64-bit variant for memory -- avoids overflow on devices with >4GB RAM |
| `TASK_BASIC_INFO` (flavor 4) | `MACH_TASK_BASIC_INFO` (flavor 20) | iOS 7+ | Apple explicitly says "Don't use this, use MACH_TASK_BASIC_INFO instead" in task_info.h |
| `task_info` with `resident_size` for memory | `task_info` with `TASK_VM_INFO` + `phys_footprint` | iOS 7+ | `phys_footprint` more closely matches Xcode's memory gauge |
| `os_proc_available_memory()` | Still current (iOS 13+) | 2019 | Apple's blessed API for "how much memory can I use?" -- but only per-process, not system-wide |

**Key insight:** Apple has been tightening iOS sandbox restrictions incrementally. `task_info` (per-process) has historically remained accessible because it only reports about the calling process. `host_statistics` (system-wide) is the one most likely to be restricted because it violates the sandbox philosophy of "apps should only know about themselves." [CITED: Apple Developer Forums thread/11393]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `host_statistics` with `HOST_CPU_LOAD_INFO` may return valid data on iOS 18 sideloaded apps | Architecture Patterns | LOW -- this is exactly what the probe validates. If blocked, the graceful fallback (hide system-wide gauge) is already the planned response. |
| A2 | `host_statistics64` with `HOST_VM_INFO64` may return valid data on iOS 18 sideloaded apps | Architecture Patterns | LOW -- same as A1, probe validates this. |
| A3 | `task_info` with `MACH_TASK_BASIC_INFO` works on iOS 18 sideloaded apps for per-process memory | Architecture Patterns | MEDIUM -- widely used by performance monitoring libraries (GDPerformanceView, SystemKit). If blocked, Phase 7 CPU-01/MEM-01 would need alternative approach. |
| A4 | `task_threads` + `THREAD_BASIC_INFO` works for per-process CPU on iOS 18 | Architecture Patterns | MEDIUM -- same reasoning as A3. GDPerformanceView uses this pattern. |
| A5 | The Mach C functions are fast enough (<1ms) to call on MainActor without jank | Common Pitfalls | LOW -- these are kernel traps, not network calls. Microsecond latency. |

**All assumptions are explicitly what this phase exists to validate.** The probe will convert A1-A4 from ASSUMED to VERIFIED.

## Open Questions

1. **Will `host_statistics` return KERN_SUCCESS or KERN_FAILURE on iOS 18?**
   - What we know: The API is in the SDK headers and compiles. Apple's sandbox philosophy suggests system-wide APIs may be restricted. No definitive documentation found confirming blocking on iOS 18 specifically.
   - What's unclear: Whether iOS 18 actively blocks this or silently degrades it.
   - Recommendation: This is the core question the probe answers. No pre-resolution possible.

2. **Does the free Apple ID sideload have different Mach API restrictions than App Store apps?**
   - What we know: Free sideload uses standard iOS sandbox entitlements (no private entitlements). The IOKit probe (Phase 1) was already blocked by AMFI.
   - What's unclear: Whether Mach host APIs are filtered at the same level as IOKit or are more permissive.
   - Recommendation: Probe will answer this. The fact that IOKit was blocked does NOT necessarily mean Mach host APIs are -- they're different subsystems.

3. **Should `TASK_VM_INFO` with `phys_footprint` be probed in addition to `MACH_TASK_BASIC_INFO`?**
   - What we know: `phys_footprint` is more accurate for memory reporting (matches Xcode gauge).
   - What's unclear: Whether both should be probed or just one.
   - Recommendation: Probe both -- it's minimal additional code and gives Phase 7 better data for choosing the right metric.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Physical device manual testing (no automated test framework -- probe results depend on iOS runtime sandbox) |
| Config file | None -- probe is the test |
| Quick run command | Build and run on physical device via Xcode |
| Full suite command | Same -- trigger debug sheet, observe 3-sample probe sequence |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CPU-02 | host_statistics returns valid CPU data or is documented as blocked | manual-only | Run on device, open debug sheet | N/A |
| MEM-02 | host_statistics64 returns valid memory data or is documented as blocked | manual-only | Run on device, open debug sheet | N/A |

**Manual-only justification:** The entire phase is a runtime sandbox probe. The verdict depends on iOS 18 kernel behavior on a physical device, which cannot be simulated in unit tests or the Simulator.

### Sampling Rate
- **Per task commit:** Build succeeds in Xcode (compile-time validation)
- **Per wave merge:** N/A (single-plan phase)
- **Phase gate:** Debug sheet shows verdicts for all APIs; 06-VERDICTS.md written with raw evidence

### Wave 0 Gaps
None -- no test infrastructure needed. The probe code IS the test.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A -- reading own process info, no sensitive data |
| V5 Input Validation | No | N/A -- no user input involved |
| V6 Cryptography | No | N/A |

This phase reads system/process statistics via kernel APIs. No user data, no authentication, no network calls. No security controls needed beyond what iOS sandbox already enforces.

## Sources

### Primary (HIGH confidence)
- iOS SDK headers at `/Applications/Xcode.app/.../iPhoneOS26.4.sdk/usr/include/mach/` -- verified `host_info.h`, `task_info.h`, `thread_info.h` contain all required types and constants [VERIFIED: local filesystem]
- Existing bridging header at `Termostato/Termostato/Termostato-Bridging-Header.h` -- confirms `#import <mach/mach.h>` already present [VERIFIED: local filesystem]
- XNU source (`apple-oss-distributions/xnu` on GitHub) -- `host_statistics` and `host_statistics64` use `host_priv` parameter type [VERIFIED: GitHub raw fetch]

### Secondary (MEDIUM confidence)
- [SystemKit source code](https://github.com/beltex/SystemKit/blob/master/SystemKit/System.swift) -- reference implementation of `host_statistics`, `host_statistics64`, CPU/memory usage in Swift [VERIFIED: GitHub raw fetch]
- [Swift iOS memory usage gist](https://gist.github.com/pejalo/671dd2f67e3877b18c38c749742350ca) -- `task_info` with `MACH_TASK_BASIC_INFO` pattern [VERIFIED: WebFetch]
- [Apple Developer Forums thread/11393](https://developer.apple.com/forums/thread/11393) -- Apple's sandbox philosophy re: system-wide APIs
- [Apple Developer Forums thread/655349](https://developer.apple.com/forums/thread/655349) -- per-process CPU usage via Mach APIs
- [os_proc_available_memory documentation](https://developer.apple.com/documentation/os/3191911-os_proc_available_memory) -- Apple's blessed per-process memory API

### Tertiary (LOW confidence)
- WebSearch results about iOS 18 sandbox changes -- no specific confirmation of host_statistics blocking found [ASSUMED: blocking status unknown, probe will determine]
- [GDPerformanceView-Swift](https://github.com/dani-gavrilov/GDPerformanceView-Swift) -- uses Mach APIs for CPU/memory in iOS apps, suggesting they worked at time of last update [ASSUMED: may not reflect iOS 18 behavior]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all APIs are in iOS SDK headers, bridging header exists, code patterns well-established
- Architecture: HIGH -- pattern follows existing codebase conventions exactly
- Pitfalls: HIGH -- well-documented in open-source implementations
- Runtime behavior on iOS 18: LOW -- this is what the probe exists to determine; no pre-existing definitive source

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 (stable kernel APIs, unlikely to change without iOS version bump)
