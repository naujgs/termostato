---
phase: 06-mach-api-proof-of-concept
reviewed: 2026-05-15T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - Termostato/Termostato/ContentView.swift
  - Termostato/Termostato/MachProbeDebugView.swift
  - Termostato/Termostato/SystemMetrics.swift
  - Termostato/Termostato/NotificationDelegate.swift
  - Termostato/Termostato/TemperatureViewModel.swift
  - Termostato/Termostato/TermostatoApp.swift
findings:
  critical: 1
  warning: 4
  info: 3
  total: 8
status: issues_found
---

# Phase 06: Code Review Report

**Reviewed:** 2026-05-15
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Phase 6 introduces `SystemMetricsProbe` — a Mach API probe engine — along with a debug sheet UI (`MachProbeDebugView`) and a long-press trigger in `ContentView`. The existing files (`TemperatureViewModel`, `NotificationDelegate`, `TermostatoApp`) carry forward from prior phases.

The new Mach API code is largely well-structured. Memory management for the `task_threads` call is handled correctly via `defer`/`vm_deallocate`. The `@Observable @MainActor` approach is consistent with the rest of the codebase. However, there is one critical concurrency bug in `SystemMetrics.swift`: the probe `Task` calls synchronous Mach APIs directly on the main actor despite being spawned as an unstructured `Task`, which blocks the main thread for the full probe duration. There are also several meaningful warnings around the `vm_deallocate` pointer cast, cancelled-task result propagation, and a logic omission in `probeTaskCPU`.

---

## Critical Issues

### CR-01: Synchronous Mach API calls block the main thread for 30+ seconds

**File:** `Termostato/Termostato/SystemMetrics.swift:71-103`

**Issue:** `runProbeSequence()` is `@MainActor`-isolated, and the `Task` it spawns inherits that isolation. The probe methods `probeSystemCPU()`, `probeSystemMemory()`, `probeTaskMemory()`, and `probeTaskCPU()` are all synchronous and marked `private func` on the same `@MainActor` class. Calling them inside the `Task` body runs them on the main actor's serial executor — i.e., on the main thread. The three-sample loop with two `Task.sleep(for: .seconds(10))` awaits does yield correctly between samples, but each of the four Mach kernel calls in a sample round executes synchronously on the main thread. On a loaded device, `task_threads` with a thread-info inner loop can be slow. More critically, the UI remains responsive only during the `sleep` awaits; all four probes within a single sample are dispatched synchronously on the main thread without any yield point between them.

The deeper structural issue: the `Task { [weak self] in ... }` body begins execution on the main actor because `runProbeSequence()` is `@MainActor` and the unstructured `Task` captures `self`. Swift 6 will inherit the actor context unless you explicitly request a background executor. For CPU-bound or blocking work, the probe methods should run on a background thread.

**Fix:** Move probe logic to a nonisolated context so the kernel calls execute off the main thread, then marshal results back to `@MainActor`:

```swift
func runProbeSequence() {
    guard !isProbing else { return }
    isProbing = true
    samplesCompleted = 0
    results = [:]
    finalVerdicts = [:]

    probeTask = Task.detached(priority: .userInitiated) { [weak self] in
        guard let self else { return }
        // These four helper methods are now nonisolated
        for i in 0..<3 {
            if Task.isCancelled { break }
            let cpuResult     = probeSystemCPU()
            let memResult     = probeSystemMemory()
            let procMemResult = probeTaskMemory()
            let procCPUResult = probeTaskCPU()
            // Marshal results back to @MainActor
            await MainActor.run {
                self.results[SystemMetricsProbe.cpuAPI, default: []].append(cpuResult)
                self.results[SystemMetricsProbe.memoryAPI, default: []].append(memResult)
                self.results[SystemMetricsProbe.processMemoryAPI, default: []].append(procMemResult)
                self.results[SystemMetricsProbe.processCPUAPI, default: []].append(procCPUResult)
                self.samplesCompleted = i + 1
            }
            if i < 2 {
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        let allAPIs = SystemMetricsProbe.allAPIs
        let snapResults = await MainActor.run { self.results }
        var computed: [String: APIVerdict] = [:]
        for api in allAPIs {
            computed[api] = self.majorityVerdict(from: snapResults[api] ?? [])
        }
        await MainActor.run {
            self.finalVerdicts = computed
            self.isProbing = false
        }
    }
}
```

The four probe methods and `majorityVerdict` should be made `nonisolated` (they have no `self` state dependencies — they only read from Mach kernel, not from `@Observable` properties).

---

## Warnings

### WR-01: `vm_deallocate` pointer cast is unsound on 32-bit (and technically UB on any arch)

**File:** `Termostato/Termostato/SystemMetrics.swift:256`

```swift
vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
```

**Issue:** `threads` is of type `thread_act_array_t` which is `UnsafeMutablePointer<thread_act_t>?` (an `UnsafePointer`). The correct way to convert an unsafe pointer to `vm_address_t` is `UInt(bitPattern: threads)`, not `vm_address_t(bitPattern: threads)`. On arm64 iOS both `UInt` and `vm_address_t` are 64-bit, so this works in practice, but `vm_address_t` is `UInt` in Darwin headers already — the cast is correct as written, but the idiom should explicitly go through `UInt` to make the intent clear and match the Darwin convention used in all sample code. More importantly, the cast itself compiles only because `vm_address_t` is a typealias for `UInt` on arm64; if someone ever builds for a 32-bit simulator the pointer truncation would silently corrupt the deallocation address.

**Fix:**
```swift
vm_deallocate(
    mach_task_self_,
    vm_address_t(UInt(bitPattern: threads)),
    size
)
```

### WR-02: `probeTaskCPU` always returns `.accessible` verdict even when no thread data is retrieved

**File:** `Termostato/Termostato/SystemMetrics.swift:278-284`

**Issue:** After the loop over threads, the method unconditionally returns verdict `.accessible` regardless of whether `threadCount` is 0 or `totalUsage` is 0. If `task_threads` succeeds but returns 0 threads (which can happen in constrained environments), the verdict will be `.accessible` when it should arguably be `.degraded` (matching the pattern in the other three probe methods).

**Fix:**
```swift
let verdict: APIVerdict = threadCount > 0 ? .accessible : .degraded
return MachProbeResult(
    api: SystemMetricsProbe.processCPUAPI,
    kernReturn: result,
    verdict: verdict,
    rawData: rawData,
    timestamp: Date()
)
```

### WR-03: `cancelProbe()` does not wait for task completion before resetting `isProbing`

**File:** `Termostato/Termostato/SystemMetrics.swift:106-110`

```swift
func cancelProbe() {
    probeTask?.cancel()
    probeTask = nil
    isProbing = false
}
```

**Issue:** `Task.cancel()` is cooperative — it only sets the cancellation flag. The task's body may still be executing (e.g., in the middle of a Mach kernel call that has no cancellation point). Setting `isProbing = false` synchronously while the task's body has not yet reached a `Task.isCancelled` check means the UI's "Run Probe" button will re-enable and `runProbeSequence()` could be called again, creating a second task. If that happens while the first task is still in the `samplesCompleted += 1` path, both tasks race to mutate `results`. Because `cancelProbe()` is called from `onDisappear` (when the sheet is dismissed), in practice the race window is small — but it is a real concurrent mutation risk.

**Fix:** After `probeTask?.cancel()`, do not immediately set `isProbing = false`. Instead, let the task's own completion path (`self.isProbing = false` on line 101) handle it, which it will once the cancellation propagates. Remove the explicit `isProbing = false` from `cancelProbe()`:

```swift
func cancelProbe() {
    probeTask?.cancel()
    probeTask = nil
    // isProbing will be set false by the task's own completion path
    // once Task.isCancelled propagates through the sleep/check points
}
```

If you need to reset the button state immediately (UX preference), accept that there may be a brief overlap and add a `guard !isProbing else { return }` in `runProbeSequence()` — which already exists, so the double-start case is already guarded. The existing guard on line 65 handles it. Removing `isProbing = false` from `cancelProbe()` is still the safer approach.

### WR-04: `DateFormatter` allocated per `VerdictRowView` render cycle

**File:** `Termostato/Termostato/MachProbeDebugView.swift:109-111`

```swift
private var timestampText: String {
    guard let sample = latestSample else { return "---" }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: sample.timestamp)
}
```

**Issue:** `DateFormatter` is expensive to construct (it accesses locale, calendar, and timezone at init time). `timestampText` is a computed property called during SwiftUI layout — it runs on every render pass. Because `VerdictRowView` is a struct re-created on every observation change, a fresh `DateFormatter` is created on every render cycle for every visible row. With 4 rows and probe updates arriving every 10 seconds this is not catastrophic, but it is a known iOS performance anti-pattern specifically flagged by Apple's performance documentation.

**Fix:** Use a static shared formatter:

```swift
private static let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

private var timestampText: String {
    guard let sample = latestSample else { return "---" }
    return VerdictRowView.timestampFormatter.string(from: sample.timestamp)
}
```

---

## Info

### IN-01: `sensoryFeedback` fires on initial render, not only on long-press

**File:** `Termostato/Termostato/ContentView.swift:29`

```swift
.sensoryFeedback(.impact, trigger: showDebugSheet)
```

**Issue:** `.sensoryFeedback(_:trigger:)` fires whenever `showDebugSheet` changes value — including the transition from `false` → `true` when long-pressed, and from `true` → `false` when the sheet is dismissed. The dismiss path will also produce haptic feedback, which is unexpected UX (haptic when closing the debug sheet). This is not a bug, but it is likely unintentional.

**Fix:** Use the two-argument condition variant to fire only on `false → true`:
```swift
.sensoryFeedback(.impact, trigger: showDebugSheet) { old, new in new == true }
```

### IN-02: `ProgressView` total hard-coded to `3.0` without referencing the loop constant

**File:** `Termostato/Termostato/MachProbeDebugView.swift:21`

```swift
ProgressView(value: Double(probe.samplesCompleted), total: 3.0)
```

**Issue:** The number of probe samples (3) is duplicated here as a magic literal and in `SystemMetrics.swift` line 73 (`for i in 0..<3`). If the sample count changes, this progress bar will silently show wrong fractions.

**Fix:** Expose a constant on `SystemMetricsProbe`:
```swift
// In SystemMetrics.swift
static let probeRounds = 3

// In MachProbeDebugView.swift
ProgressView(value: Double(probe.samplesCompleted), total: Double(SystemMetricsProbe.probeRounds))
```

### IN-03: `startPolling()` called twice on cold launch

**File:** `Termostato/Termostato/ContentView.swift:130-144`

**Issue:** On first app launch, `onAppear` fires (line 143, calls `startPolling()`), and then `scenePhase` transitions to `.active` also fires (line 133, calls `startPolling()` again). The second call hits `timerCancellable?.cancel()` before re-creating the timer, so there is no functional bug — but two permission-request tasks (`requestNotificationPermission()`) are launched in parallel, and two `refreshNotificationStatus()` tasks run concurrently. `requestAuthorization` is idempotent so there is no crash risk, but it adds unnecessary noise and could produce two log lines per launch.

**Fix:** Remove the `onAppear` call and rely solely on the `scenePhase == .active` path, or guard with a `hasStarted` flag:
```swift
// Remove:
.onAppear {
    viewModel.startPolling()
}
// The .onChange(of: scenePhase) handler covers the active case on launch.
```

---

_Reviewed: 2026-05-15_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
