# Pitfalls Research

**Domain:** iOS system metrics — Mach kernel APIs, UIDevice battery, SwiftUI display in a Swift 6.3 @MainActor sideloaded app
**Researched:** 2026-05-14
**Milestone:** v1.2 — CPU usage, memory pressure, battery level added to existing Termostato dashboard
**Confidence:** HIGH (Mach API behavior, Swift 6.3 concurrency, UIDevice battery API); MEDIUM (energy impact thresholds — Apple does not publish specific interval guidelines)

> This file replaces v1.1 PITFALLS.md for the v1.2 milestone. v1.2 adds Mach kernel API calls for
> CPU/memory, UIDevice battery monitoring, and SwiftUI display of rapidly-updating scalar values to an
> existing Swift 6.3 @MainActor @Observable ViewModel. Pitfalls focus exclusively on these new
> surfaces — v1.0/v1.1 pitfalls (icon, TrollStore, timer RunLoop) are not repeated.

---

## Critical Pitfalls

### Pitfall 1: Zero-Initialized `previousLoad` Produces a Since-Boot Delta on First Sample

**What goes wrong:**
`host_cpu_load_info` returns cumulative tick counts since device boot — not per-interval activity. To compute a meaningful CPU %, you must subtract the previous sample from the current sample. If `previousLoad` is stored as `host_cpu_load_info_data_t()` (zero-initialized struct), the first "delta" is actually the total ticks since boot. On a device that has been running for hours, this produces a first reading of 5–40% CPU when the device is idle — wrong and misleading. It does not crash. It silently displays incorrect data on the very first screen the user sees.

**Why it happens:**
Swift struct initialization requires an initial value. Developers write `var previousLoad = host_cpu_load_info_data_t()` because it compiles cleanly. The since-boot corruption is only visible at runtime.

**How to avoid:**
Store `previousLoad` as an `Optional` initialized to `nil`. Return `nil` (display as "—") on the first call:

```swift
private var previousLoad: host_cpu_load_info_data_t?

func fetchCPUPercent() -> Double? {
    // ... call host_statistics, get current load ...
    guard let prev = previousLoad else {
        previousLoad = load   // first call — store, don't report
        return nil
    }
    previousLoad = load
    // compute delta from prev
}
```

**Warning signs:**
- First CPU reading is suspiciously high (10–60%) then drops sharply on the second tick
- `previousLoad` declared as `host_cpu_load_info_data_t()` (zero struct, not Optional)
- The problem disappears after the app has run for 10 seconds — making it easy to miss in short test sessions

**Phase to address:**
Research / proof-of-concept. This is the first thing to get right before writing any UI code.

---

### Pitfall 2: CPU Percentage Formula Includes Idle in the Numerator

**What goes wrong:**
The correct CPU-in-use percentage formula is:

```
active = user + sys + nice
total  = user + sys + nice + idle
pct    = active / total * 100
```

A common mistake is including `idle` in both numerator and denominator, producing a number that is always near 100%. Another mistake is using only `user` in the numerator and omitting `sys`, undercounting by 10–30% under load. A third mistake is dividing `active` by total-ticks-since-boot rather than delta-ticks-over-the-polling-interval — producing a slow-moving rolling average that never reflects current load.

**Why it happens:**
Online examples vary. Some show per-core percentages (divide by core count), some show system-wide (no division). Some include `nice` in the denominator only. Copy-paste without understanding propagates the error.

**The correct delta formula in Swift:**
```swift
let userDiff = Double(load.cpu_ticks.0 &- prev.cpu_ticks.0)   // CPU_STATE_USER
let sysDiff  = Double(load.cpu_ticks.1 &- prev.cpu_ticks.1)   // CPU_STATE_SYSTEM
let idleDiff = Double(load.cpu_ticks.2 &- prev.cpu_ticks.2)   // CPU_STATE_IDLE
let niceDiff = Double(load.cpu_ticks.3 &- prev.cpu_ticks.3)   // CPU_STATE_NICE

let total = userDiff + sysDiff + idleDiff + niceDiff
guard total > 0 else { return 0 }
return (userDiff + sysDiff + niceDiff) / total * 100.0
```

Use Swift's wrapping subtraction operator `&-` on `natural_t` (UInt32) before casting to Double. This correctly handles the theoretical UInt32 wraparound (occurs after ~497 days at 100 ticks/sec — unlikely but defensively correct).

Note: `host_cpu_load_info` tick counts are aggregate across ALL cores. The result is already normalized to 0–100% of total device capacity. Do not multiply or divide by core count.

**Warning signs:**
- CPU displays 95–100% when device is clearly idle
- CPU displays 1–5% during an intensive workload (omitting sys or nice)
- CPU does not respond to a sudden workload spike for 30+ seconds (using cumulative ticks not deltas)

**Phase to address:**
Research. Validate the formula on physical device against Xcode's CPU Gauge before integrating into the ViewModel.

---

### Pitfall 3: Non-Sendable C Struct Triggers Swift 6.3 Concurrency Compiler Errors — Wrong Fix Is to Use a Background Task

**What goes wrong:**
`host_cpu_load_info_data_t` and `vm_statistics64_data_t` are C structs imported into Swift. They are not `Sendable`. When a `@MainActor`-isolated function uses `withUnsafeMutablePointer` to pass a pointer to one of these structs to a C function, the compiler may emit:

```
Capture of 'load' with non-sendable type 'host_cpu_load_info_data_t' in a @Sendable closure
```

The instinctive "fix" is to move the Mach call off the main actor into a background `Task`. This is wrong for two reasons: (1) Mach calls complete in under 100 microseconds — they do not need to be async, (2) moving the call off `@MainActor` makes the type-crossing problem worse because the C struct result must now cross actor boundaries to get back to the ViewModel, which requires it to be `Sendable`.

**Why it happens:**
Swift 6 strict concurrency aggressively flags C struct captures in closures. The natural instinct is "make it async / background," which is the correct fix for I/O-bound work but the wrong fix for in-process C calls.

**How to avoid:**
Keep all Mach calls synchronous and on `@MainActor`. The struct is created, used, and discarded within one function call — the compiler error is a false alarm caused by the closure capture analysis. Annotate the closure explicitly with `@MainActor` to confirm isolation:

```swift
@MainActor
private func fetchCPULoad() -> host_cpu_load_info_data_t? {
    var load = host_cpu_load_info_data_t()
    var size = mach_msg_type_number_t(
        MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let kr = withUnsafeMutablePointer(to: &load) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
            host_statistics(machHost, HOST_CPU_LOAD_INFO, intPtr, &size)
        }
    }
    return kr == KERN_SUCCESS ? load : nil
}
```

For stored intermediate state (`previousLoad: host_cpu_load_info_data_t?`), mark the property `@ObservationIgnored` to prevent the `@Observable` macro from generating tracking accessors for a non-Sendable C struct.

**Warning signs:**
- `Task { }` wrapping a Mach call — unnecessary and creates new actor-crossing problems
- `nonisolated(unsafe)` on `previousLoad` — wrong annotation; this property is on MainActor and should be `@ObservationIgnored`
- Second round of compiler errors after "fixing" the first error by adding a Task

**Phase to address:**
Research phase. All compiler warnings must be zero before wiring metrics into the ViewModel.

---

### Pitfall 4: `host_statistics` Count Argument Calculated from Raw `sizeof` — Struct-Integer Mismatch Causes KERN_INVALID_ARGUMENT

**What goes wrong:**
`host_statistics` and `host_statistics64` take a `mach_msg_type_number_t` count argument representing the number of `integer_t`-sized units in the info struct. Developers often pass `MemoryLayout<host_cpu_load_info_data_t>.size` directly. This is wrong — it passes the byte count, not the integer_t count. The call returns `KERN_INVALID_ARGUMENT` (error code 4) and the struct is left in an undefined state. The `KERN_SUCCESS` guard then catches this, but the real bug is the wrong count formula.

**Why it happens:**
In C, the idiom `HOST_CPU_LOAD_INFO_COUNT` is a macro defined as `sizeof(host_cpu_load_info_data_t) / sizeof(integer_t)`. Swift developers reproduce this as `MemoryLayout<host_cpu_load_info_data_t>.size` without the division, which is half the idiom.

**How to avoid:**
Always divide by `MemoryLayout<integer_t>.size`:

```swift
var size = mach_msg_type_number_t(
    MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
)
```

For `vm_statistics64_data_t`:
```swift
var size = mach_msg_type_number_t(
    MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
)
```

**Warning signs:**
- `host_statistics` returns a non-zero value (not KERN_SUCCESS)
- CPU or memory reading is always nil after adding the KERN_SUCCESS guard
- Adding a print on kr reveals `4` (KERN_INVALID_ARGUMENT)

**Phase to address:**
Research / proof-of-concept. Add a `precondition(kr == KERN_SUCCESS)` during development to catch this immediately rather than silently returning nil.

---

### Pitfall 5: `vm_statistics64` `free_count` Alone Understates Available Memory by 20–50%

**What goes wrong:**
`host_statistics64` with `HOST_VM_INFO64` returns a `vm_statistics64_data_t`. Using `free_count` alone as "available memory" produces a figure 20–50% lower than what Instruments / Xcode Memory Report shows. The missing component is `speculative_count` — pages that have been read ahead by the kernel and not yet dirtied. These pages are immediately reclaimable and functionally equivalent to free memory from the app's perspective. Reporting only `free_count` makes the device appear more memory-constrained than it is.

**How to avoid:**
Use the Activity Monitor formula:
```swift
let pageSize = UInt64(vm_kernel_page_size)   // 16384 on modern iPhones; do NOT use 4096
let freeBytes = UInt64(stats.free_count + stats.speculative_count) * pageSize
let totalBytes = ProcessInfo.processInfo.physicalMemory
let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0
```

Always multiply page counts by `vm_kernel_page_size` (not 1024, not 4096). On iPhones with A9+ the page size is 16384 bytes. Using 4096 produces numbers 4× too small.

**Warning signs:**
- Displayed "free memory" is consistently 30–50% lower than Xcode's Memory Report gauge
- Raw page count displayed without multiplication by page size (numbers like "24,576 free")
- `vm_kernel_page_size` not used — `4096` or `1024` hardcoded instead

**Phase to address:**
Research. Validate displayed figure against Xcode Memory Report on physical device before shipping.

---

## Moderate Pitfalls

### Pitfall 6: `UIDevice.isBatteryMonitoringEnabled` Left `true` After App Backgrounds

**What goes wrong:**
`isBatteryMonitoringEnabled = true` activates a system-level monitoring process. Leaving it permanently enabled — even when the app is backgrounded and battery metrics are not being displayed — runs that process during periods when the app produces no value from the data. This is a minor but real energy cost and signals a lifecycle mismatch.

**How to avoid:**
Mirror the existing `startPolling()` / `stopPolling()` pattern in the ViewModel:

```swift
// In startPolling():
UIDevice.current.isBatteryMonitoringEnabled = true

// In stopPolling():
UIDevice.current.isBatteryMonitoringEnabled = false
```

Register `UIDeviceBatteryLevelDidChange` and `UIDeviceBatteryStateDidChange` observers in `startPolling()` and remove them in `stopPolling()`. Do not rely on `deinit` alone — the ViewModel stays alive in memory while the app is backgrounded.

**Warning signs:**
- `isBatteryMonitoringEnabled = true` in `init()` with no matching `false`
- Battery notification observers added without paired `removeObserver` calls
- `UIDevice.current.batteryLevel` returns `-1.0` — monitoring was not enabled before reading

**Phase to address:**
Implementation — lifecycle pairing is required before merging the battery feature.

---

### Pitfall 7: `UIDeviceBatteryLevelDidChange` Fires Infrequently — Do Not Rely on It for Live Display

**What goes wrong:**
Developers register for `UIDeviceBatteryLevelDidChange` expecting it to fire on every 1% battery change. It does not. iOS fires this notification at system-determined intervals (documentation says "when battery level changes" but in practice the threshold is multiple percentage points or significant time). Building the battery level display to update only on this notification results in a label that appears frozen between updates.

**How to avoid:**
Poll `UIDevice.current.batteryLevel` on the existing 10-second timer tick (same as the thermal state poll). Use `UIDeviceBatteryStateDidChange` only for charging state changes (plugged in / unplugged), which fire reliably. Display format: multiply by 100, round to Int, show as "73%". Guard for `-1.0` (monitoring not enabled or simulator) — display "—".

**Warning signs:**
- Battery level label not updating despite obvious battery drain
- `UIDeviceBatteryLevelDidChange` handler contains the only battery level read in the codebase

**Phase to address:**
Implementation — wire battery level into the existing polling update function.

---

### Pitfall 8: Displaying Raw CPU % in SwiftUI — Visible Jitter From Natural Variance

**What goes wrong:**
`host_cpu_load_info` at 10-second intervals produces delta percentages that naturally vary 5–15 points between polls even under stable workloads. The label jumps visibly every tick, making the display look broken even when the formula is correct. This is a readability problem, not a correctness problem — but it erodes user trust.

**How to avoid:**
Apply a 3-sample Exponential Moving Average (EMA) for the display value. Keep the raw value for diagnostics:

```swift
private var cpuEMA: Double = 0.0
private let cpuAlpha: Double = 0.4   // weight for newest sample

// After computing rawCPU:
cpuEMA = cpuAlpha * rawCPU + (1.0 - cpuAlpha) * cpuEMA
// Publish cpuEMA to the UI, not rawCPU
```

Alpha of 0.4 gives a ~3-sample weighted average. Do not use a window larger than 5 samples (50 seconds at 10s polling) — genuine spikes will appear slow to respond.

**Warning signs:**
- CPU label visibly jumping 10+ points between stable-load ticks
- User reports "the number looks random" on an idle device
- Instruments Core Animation trace shows view redraws exactly coinciding with timer ticks with large delta values

**Phase to address:**
Polish — after formula correctness is established and verified. Do not smooth during research; raw values are needed to diagnose the formula.

---

### Pitfall 9: Adding Multiple `@Observable` Properties That All Change on One Timer Tick

**What goes wrong:**
Adding `cpuPercent`, `memoryUsedBytes`, `memoryFreeBytes`, `batteryLevel`, and `batteryState` as individual `@Observable` properties causes SwiftUI to re-evaluate every body that reads any of these properties, separately, on each timer tick. With 5 new observable properties all changing simultaneously, a view reading all five triggers 5 separate diff cycles — not 1.

**How to avoid:**
Bundle all system health metrics into a single value type:

```swift
struct SystemMetrics {
    var cpuPercent: Double?
    var memoryUsedMB: Int
    var memoryFreeMB: Int
    var batteryPercent: Int?   // nil when monitoring not enabled
    var batteryState: UIDevice.BatteryState
}

// In ViewModel:
private(set) var metrics = SystemMetrics(...)
```

SwiftUI diff now runs once per tick on the `metrics` property, not once per sub-property. Mark sub-properties that SwiftUI does not need to observe directly as non-`@Observable` if using the struct bundle pattern.

**Warning signs:**
- Instruments SwiftUI trace shows multiple body re-evaluations per timer tick for the same view
- Adding 4+ new scalar properties to the ViewModel without grouping them

**Phase to address:**
Implementation — decide on the grouping structure before writing any new ViewModel properties.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Displaying raw (unsmoothed) CPU % | Simpler code during research | Label jitter; looks broken at 10s interval | Research/proof-of-concept only — add EMA before Polish is done |
| Storing `previousLoad` as zero-struct instead of Optional | No nil-check in caller | First sample always corrupted; silent wrong data | Never — one-line fix |
| Calling `mach_host_self()` inline each poll tick instead of caching | Fewer stored properties | Harmless for host port (it is a special non-destructible port) but establishes a misleading pattern that will be wrong if applied to other ports | Acceptable in minimal personal app; prefer caching for clarity |
| Leaving `isBatteryMonitoringEnabled = true` permanently | No lifecycle teardown code | Minor energy cost; slight battery monitoring overhead when backgrounded | Acceptable in a personal foreground monitoring tool — document the decision |
| Individual scalar `@Observable` properties for each metric | Easier to add one at a time | SwiftUI runs multiple diff cycles per tick; adds boilerplate as metrics grow | Acceptable for 1–2 metrics; prefer struct grouping at 3+ |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Polling at 1–2s interval "for better resolution" | App appears in Xcode Energy report as High impact; CPU reading includes its own polling overhead (self-reinforcing) | Keep 10s for display; if 1s data is needed for research, collect silently without publishing to UI | Immediately — visible in Instruments Energy Log on first test |
| Rolling CPU + memory + battery all into the session chart at 10s resolution | 360 entries × 3 metrics = 1080 chart points at 1-hour session; Swift Charts redraws all on each tick | Cap chart at 120–180 entries for the new metrics; use same ring buffer pattern as thermal history | Perceptible chart redraw lag after 20–30 minutes of continuous use |
| `UIDeviceBatteryLevelDidChange` observer doing synchronous heavy work | Battery state changes occasionally but handler runs on unspecified queue; data race in Swift 6 strict mode | Register observer with `queue: .main`; keep handler lightweight | Silent data race — detected by Thread Sanitizer, not crash at runtime |
| Using `host_statistics` (32-bit) instead of `host_statistics64` for memory | Correct on iOS 17 and earlier; `host_statistics64` is required for accurate stats on 64-bit devices and current iOS | Use `host_statistics64` with `HOST_VM_INFO64` — the 64-bit version has been available since iOS 6 | Silent numeric truncation on large-RAM devices (4GB+ iPhones) |

---

## "Looks Done But Isn't" Checklist

- [ ] **CPU % formula:** Verify idle ticks are in the denominator but NOT the numerator. Including idle in the numerator yields 95–100% at idle.
- [ ] **First-sample guard:** UI shows "—" or "Warming up" for CPU on first display tick. A reading of 20–60% on first render is the zero-struct initialization bug.
- [ ] **KERN_SUCCESS guard:** Every call to `host_statistics` and `host_statistics64` is guarded. Return value 4 means KERN_INVALID_ARGUMENT — the count formula is wrong.
- [ ] **`vm_kernel_page_size` multiplication:** Memory bytes = page count × `vm_kernel_page_size` (16384), not × 4096 or × 1024.
- [ ] **`free_count + speculative_count`:** Available memory uses both fields, not `free_count` alone. Validate within 10% of Xcode Memory Report.
- [ ] **Battery monitoring lifecycle:** `isBatteryMonitoringEnabled = false` is called in `stopPolling()`. Background the app and verify Console shows no ongoing battery monitoring activity.
- [ ] **`batteryLevel` guard:** UI displays "—" when `batteryLevel == -1.0` (monitoring not started or Simulator).
- [ ] **Swift 6 clean build:** Zero non-sendable or actor-isolation warnings in the new metrics code path. `Product > Build` must be clean.
- [ ] **Energy impact baseline:** Xcode Energy Gauge shows no more than one tier increase (Low → Fair acceptable; Low → High is not) after adding metrics polling to the existing 10s timer.
- [ ] **EMA alpha tuning on device:** Under an artificial load spike, the smoothed CPU % responds visibly within 2 poll ticks (20 seconds). If it takes longer, alpha is too low.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Zero-struct `previousLoad` producing inflated first sample | LOW | Change type to `host_cpu_load_info_data_t?`, return nil on first call — 3 lines |
| Background Task wrapping Mach call causes new actor-crossing errors | MEDIUM | Remove Task wrapper; move Mach call back to synchronous `@MainActor` path — 15–30 min |
| Memory figure 30–50% below Instruments | LOW | Add `speculative_count` to free_count in the available-memory calculation — 1 line |
| CPU % at 95–100% idle | LOW | Audit formula numerator; remove idle from numerator; verify subtraction uses previous sample not boot-cumulative |
| `KERN_INVALID_ARGUMENT` from host_statistics | LOW | Fix count formula: add `/ MemoryLayout<integer_t>.size` to the size calculation |
| Battery monitoring leaving energy footprint in background | LOW | Add `UIDevice.current.isBatteryMonitoringEnabled = false` to `stopPolling()` — 1 line |
| UI thrashing / visible CPU label jitter | MEDIUM | Add EMA smoothing to display value; separate display cadence from data-collection cadence — 1–2 hours |
| 5 new scalar `@Observable` properties causing redundant SwiftUI diffs | MEDIUM | Refactor into a `SystemMetrics` struct; update ViewModel and View reads — 2–4 hours |

---

## Pitfall-to-Phase Mapping

v1.2 phases: **Research** (probe all APIs, validate formulas on device), **Implement** (wire confirmed metrics into ViewModel and dashboard UI), **Polish** (smoothing, UX, energy validation).

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Zero-struct `previousLoad` / inflated first sample | Research | First displayed CPU reading is "—", not a suspicious high value |
| CPU formula numerator includes idle | Research | CPU label shows ~2–5% on an idle device, not 95%+ |
| `KERN_SUCCESS` guard / wrong count formula | Research | `precondition(kr == KERN_SUCCESS)` passes on every call during development |
| Non-sendable C struct / Swift 6 concurrency errors | Research | `Product > Build` zero concurrency warnings before any ViewModel integration |
| `vm_statistics64` field misinterpretation | Research | Displayed available memory within 10% of Xcode Memory Report on physical device |
| `vm_kernel_page_size` not used | Research | Memory in MB/GB, not in pages; cross-checked with Instruments |
| `isBatteryMonitoringEnabled` lifecycle mismatch | Implement | stopPolling() sets it false; verified by Console log after backgrounding |
| `UIDeviceBatteryLevelDidChange` for live display | Implement | Battery label updates every 10s alongside thermal state update |
| Multiple `@Observable` scalars causing redundant diffs | Implement | All new metrics bundled in `SystemMetrics` struct before merging |
| UI thrashing from raw CPU variance | Polish | CPU label does not jump more than 4 points between ticks under stable load |
| EMA lag hiding genuine spikes | Polish | Simulated load spike (video encode) visible in CPU reading within 2 ticks (20s) |
| Multi-metric chart performance at long sessions | Polish | Chart updates without perceptible lag after 30 minutes of continuous use on device |

---

## Sources

- [Apple Developer Forums — Do we need to release the reference count on host port](https://developer.apple.com/forums/thread/725854) — confirms `mach_host_self()` is a special non-destructible port; `mach_port_deallocate` not required
- [SystemKit/System.swift (beltex/SystemKit)](https://github.com/beltex/SystemKit/blob/master/SystemKit/System.swift) — reference implementation: tick delta pattern, struct allocation/deallocation, `processorLoadInfo` showing `mach_port_deallocate` on non-host ports
- [CPU.swift gist (paalgyula)](https://gist.github.com/paalgyula/47c8e37f6785bed6634d1cc1fb5697bc) — CPU percentage formula: `(user + sys + nice) / (user + sys + nice + idle) * 100`
- [Apple Developer Documentation — host_statistics64](https://developer.apple.com/documentation/kernel/1502863-host_statistics64) — official API docs
- [Apple Developer Documentation — vm_statistics64_data_t](https://developer.apple.com/documentation/kernel/vm_statistics64_data_t) — memory struct fields including `speculative_count`
- [Apple Developer Documentation — isBatteryMonitoringEnabled](https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled) — battery monitoring lifecycle; default is NO
- [Apple Developer Documentation — Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance) — view redraw cost guidance
- [Swift Forums — How to update SwiftUI many times a second while being performant](https://forums.swift.org/t/how-to-update-swiftui-many-times-a-second-while-being-performant/71249) — UI thrashing and debounce patterns
- [Apple Energy Efficiency Guide for iOS Apps — Fundamental Concepts](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/FundamentalConcepts.html) — polling and energy cost principles; no specific interval thresholds published
- [Swift.org — Common Swift 6 concurrency migration problems](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems/) — non-sendable types, actor isolation, C interop patterns
- [Hacking With Swift — Swift 6.0 complete concurrency](https://www.hackingwithswift.com/swift/6.0/concurrency) — Sendable enforcement and non-sendable closure captures
- [Get virtual memory usage on iOS — gist (algal)](https://gist.github.com/algal/cd3b5dfc16c9d577846d96713f7fba40) — `vm_statistics64` usage pattern including `speculative_count`
- [Apple Developer Documentation — host_cpu_load_info_t](https://developer.apple.com/documentation/kernel/host_cpu_load_info_t) — official struct reference
- [Apple Developer Forums — how to get overall CPU utilization of iPhone](https://developer.apple.com/forums/thread/11393) — Apple engineer notes on `host_statistics` vs process-specific APIs

---
*Pitfalls research for: Termostato v1.2 — Mach kernel CPU/memory APIs, UIDevice battery, SwiftUI metrics display*
*Researched: 2026-05-14*
