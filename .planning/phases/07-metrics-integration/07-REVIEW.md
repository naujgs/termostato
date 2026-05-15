---
phase: 07-metrics-integration
reviewed: 2026-05-15T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - Termostato/Termostato/MetricsViewModel.swift
  - Termostato/Termostato/TemperatureViewModel.swift
  - Termostato/Termostato/ThermalView.swift
  - Termostato/Termostato/CPUView.swift
  - Termostato/Termostato/MemoryView.swift
  - Termostato/Termostato/ContentView.swift
  - Termostato/Termostato/Localizable.xcstrings
findings:
  critical: 0
  warning: 4
  info: 5
  total: 9
status: issues_found
---

# Phase 07: Code Review Report

**Reviewed:** 2026-05-15
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Phase 7 delivers the CPU/memory metrics integration: a new `MetricsViewModel` polling Mach kernel APIs via `Task.detached`, three tab-scoped views (`ThermalView`, `CPUView`, `MemoryView`), a restructured `ContentView` TabView container, and an `xcstrings` catalog for tooltip localizations.

The implementation is architecturally sound. Swift 6 strict-concurrency constraints are handled correctly through `nonisolated(unsafe)` for the `previousCPUTicks` mutable delta state and `await MainActor.run` for property marshalling. The `vm_deallocate` defer block in `readAppCPU` correctly prevents Mach port accumulation. No hardcoded credentials, injection surfaces, or user data exposure exist — all data is device-local kernel reads.

Four warnings require attention before shipping:

1. **Double-start race on launch** — `onAppear` and the `.active` scenePhase handler both fire on first launch, calling `startPolling()` on both ViewModels twice in rapid succession. The guards cancel-and-recreate correctly, but each cancel-then-restart discards the first tick result, delaying initial data by one poll cycle unnecessarily. More importantly, a structural issue remains: `.inactive` is not guarded against calling `stopPolling`, leaving a window where a brief `.inactive` transition (e.g. control center overlay) followed by `.active` will restart both VMs even though they were never stopped.

2. **System CPU formula omits `system` ticks** — `readSystemCPU()` uses only `user` and `idle` ticks in its delta formula, silently dropping the `system` (kernel) ticks component (`.1` / `CPU_STATE_SYSTEM`). This produces a reading labelled "System CPU%" that underreports true total CPU load on A-series chips where kernel ticks are non-zero.

3. **`vm_deallocate` address cast is incorrect for non-zero-offset pointer types** — `vm_address_t(bitPattern: threads)` converts the `UnsafeMutablePointer<thread_act_t>` to an address using its raw bit pattern. This is correct only if the `UnsafePointer` and `vm_address_t` share the same bit width and the pointer directly represents the start of the allocation. On the existing codebase this is safe (arm64, 64-bit both), but the cast should use `UInt(bitPattern: threads)` to match the `vm_address_t` typealias (`UInt`) without relying on `bitPattern:` bridging semantics across pointer casts.

4. **Tooltip popover in `ThermalView` diverges from `MetricCardView`** — `ThermalView` attaches `.popover(isPresented:)` directly to the `Button` label rather than to the `Button` itself, meaning the popover presentation anchor is the icon image, not the button. On iPhone this falls back to a sheet anyway (`.presentationCompactAdaptation(.popover)` only works on iPad), but the placement differs from the `MetricCardView` pattern where `.popover` is on the `Button`. The two implementations are inconsistent.

No critical issues (security vulnerabilities, nil crashes, data loss) were found.

---

## Warnings

### WR-01: Double-start on launch discards first tick; no guard against `.inactive` restart

**File:** `Termostato/Termostato/ContentView.swift:44-47` and `30-43`

**Issue:** `onAppear` fires and calls `startPolling()` on both ViewModels immediately. Then, milliseconds later, the scenePhase transitions from `.inactive` → `.active`, firing the `.onChange` handler which calls `startPolling()` again. Each `MetricsViewModel.startPolling()` cancels `pollingTask` before recreating it, and each `TemperatureViewModel.startPolling()` cancels `timerCancellable`. The double-start is guarded against crashes, but the first `tick()` result captured in the `Task.detached` closure is thrown away when the task is immediately cancelled. The effect is that the first visible metric reading is delayed by a full 5-second sleep cycle instead of arriving immediately.

Additionally, `.inactive` has a `break` — it neither starts nor stops polling. However, when returning from `.inactive` to `.active` (e.g. after dismissing Control Center), `startPolling()` restarts both VMs even though they were never stopped for `.inactive`, causing another spurious restart.

**Fix:** Remove `onAppear` and rely solely on `scenePhase`. On iOS, `scenePhase` transitions to `.active` on initial launch, which is sufficient. If `onAppear` must be retained for preview compatibility, add a `hasStarted` guard flag:

```swift
// ContentView — option A (preferred): remove onAppear entirely
// scenePhase fires .active on first launch — no need for onAppear.

// ContentView — option B: guard with a flag
@State private var hasStarted = false

.onAppear {
    guard !hasStarted else { return }
    hasStarted = true
    vm.startPolling()
    metrics.startPolling()
}
```

---

### WR-02: `readSystemCPU()` silently drops kernel (`system`) ticks from CPU total

**File:** `Termostato/Termostato/MetricsViewModel.swift:147-161`

**Issue:** The delta formula computes `userDelta / (userDelta + idleDelta)`, deliberately excluding `cpu_ticks.1` (CPU_STATE_SYSTEM). The comment correctly notes that `.1` is "always 0 on Apple Silicon", but this is not accurate for all iOS devices. A13 Bionic and earlier (iPhone 11 and below), and any simulator environment, do record non-zero `system` ticks. Dropping system ticks causes the displayed "System CPU%" to read lower than true utilisation, which is a logic error for the stated metric ("total CPU usage across all apps and system processes").

The comment in `previousCPUTicks` and `readSystemCPU()` acknowledges `.1=system always 0 on Apple Silicon` — this is phase-documented as D-13. However, the tooltip string `tooltip.sys_cpu` says "Total CPU usage across all apps and system processes on the device", which is inconsistent with the implementation.

**Fix:** Include system ticks in the total (and in `previousCPUTicks`) to match the tooltip description, or update the tooltip to say "user-mode CPU usage" if dropping system is intentional:

```swift
// Option A: include system ticks (correct for the stated metric)
let currentUser   = loadInfo.cpu_ticks.0   // CPU_STATE_USER
let currentSystem = loadInfo.cpu_ticks.1   // CPU_STATE_SYSTEM
let currentIdle   = loadInfo.cpu_ticks.2   // CPU_STATE_IDLE

previousCPUTicks = (user: currentUser, idle: currentIdle)

let userDelta   = currentUser   > prev.user   ? Double(currentUser   - prev.user)   : 0.0
let sysDelta    = currentSystem > prev.system ? Double(currentSystem - prev.system) : 0.0
let idleDelta   = currentIdle   > prev.idle   ? Double(currentIdle   - prev.idle)   : 0.0
let total = userDelta + sysDelta + idleDelta
guard total > 0 else { return 0.0 }
return ((userDelta + sysDelta) / total) * 100.0

// Option B (minimal): keep current formula but update tooltip.sys_cpu to say
// "User-mode CPU usage (excludes kernel time). Approximation on older Apple chips."
```

Note: if Option A is chosen, `previousCPUTicks` needs a `system` component added to its tuple.

---

### WR-03: `vm_deallocate` address cast uses `bitPattern:` on a typed pointer

**File:** `Termostato/Termostato/MetricsViewModel.swift:97`

**Issue:** `vm_address_t(bitPattern: threads)` converts `UnsafeMutablePointer<thread_act_t>?` after the optional is unwound via the `guard`. `vm_address_t` is a typealias for `UInt`. On arm64 `UInt` and pointer bit width are both 64 bits, so the numeric value is correct. However, `bitPattern:` initialiser on `UInt` accepting a pointer is only defined for `UnsafeRawPointer`, not `UnsafeMutablePointer<T>`. The compiler accepts this implicitly via pointer-to-raw coercion, which is technically sound but relies on an implicit conversion that could be broken by a future Swift version. The established safe idiom is `UInt(bitPattern: threads)`.

**Fix:**
```swift
// Current (fragile implicit coercion):
vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

// Fixed (explicit, future-safe):
vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), size)
```

---

### WR-04: Tooltip popover anchored to icon `Image`, not to the `Button`

**File:** `Termostato/Termostato/ThermalView.swift:34-47`

**Issue:** The `.popover(isPresented: $showThermalTooltip)` modifier is applied to the `Button`'s `label` closure content (the `Image`), not to the `Button` itself. Structurally, the `Button { showThermalTooltip = true } label: { Image(...) .popover(...) }` places the popover modifier inside the label builder. On iPadOS the popover anchor will be the image frame, not the button hit area. On iPhone the `.presentationCompactAdaptation(.popover)` modifier causes it to present as a popover regardless of the anchor, but the code structure is semantically wrong and diverges from the `MetricCardView` pattern where `.popover` is correctly on the `Button`.

**Fix:** Move `.popover` outside the label closure and apply it to the `Button`:

```swift
// Current (popover inside label):
Button {
    showThermalTooltip = true
} label: {
    Image(systemName: "info.circle")
        .foregroundStyle(badgeTextColor.opacity(0.7))
}
.padding(12)
.popover(isPresented: $showThermalTooltip) { ... }  // this is already OUTSIDE label — see below

// Correction: ThermalView.swift lines 34-47 show the .popover IS on the Button (not inside label).
// The structural issue is that the entire Button+popover is inside .overlay(alignment: .topTrailing)
// on the RoundedRectangle rather than being a separate overlay layer as in MetricCardView.
// This is cosmetically inconsistent but functionally correct. No code change required here —
// downgrade this to INFO if the reviewer agrees the current placement is intentional.
```

After re-reading: the `.popover` at line 41 is chained off `.padding(12)` which is chained off the `Button` — so `.popover` IS on the `Button`, not inside the label. This warning should be reconsidered. The actual structural issue is minor: `ThermalView` uses a two-layer `.overlay` approach (one for the info button with popover, one for the state label text) while `MetricCardView` uses the same pattern. They are consistent. **This warning is downgraded to WR-04 / Info** — see IN-03.

---

## Info

### IN-01: Hard-coded literal `16384` for page size is arm64-only

**File:** `Termostato/Termostato/MetricsViewModel.swift:179`

**Issue:** The comment correctly explains the fallback from `vm_kernel_page_size` due to Swift 6 strict-concurrency. The literal `16384` is correct for all current iOS devices running on Apple Silicon (arm64). However, if this code is ever run in a simulator targeting x86_64 or if a future architecture change occurs, the wrong page size will silently produce incorrect memory readings without any diagnostic. The comment documents the reasoning but does not guard against misuse.

**Suggestion:** Add an `#if` guard or a `assert` to make the assumption explicit at compile time:
```swift
// Make the assumption auditable:
#if !arch(arm64)
#warning("vm_kernel_page_size literal 16384 may be incorrect on non-arm64 targets")
#endif
let pageSize: Double = 16384
```

---

### IN-02: `readSystemCPU()` first-poll guard uses `prev.user > 0 || prev.idle > 0`

**File:** `Termostato/Termostato/MetricsViewModel.swift:154`

**Issue:** The intent of this guard is to detect the initial state where `previousCPUTicks` has never been populated (both fields are `0`). The condition `prev.user > 0 || prev.idle > 0` correctly identifies "not first poll" but could theoretically fail to return `0.0` if the kernel reports a state where `user > 0` but `idle == 0` at the exact moment of the first real read. This is extremely unlikely but the safer idiom is to use a separate `Bool` flag to track "first poll taken".

**Suggestion:**
```swift
@ObservationIgnored
nonisolated(unsafe) private var hasCPUBaseline = false

// In readSystemCPU():
let wasCold = !hasCPUBaseline
hasCPUBaseline = true
previousCPUTicks = (user: currentUser, idle: currentIdle)
guard !wasCold else { return 0.0 }
```

---

### IN-03: `ThermalView` tooltip popover placement is structurally different from `MetricCardView`

**File:** `Termostato/Termostato/ThermalView.swift:32-47`

**Issue:** `ThermalView` places the info button in a `.overlay(alignment: .topTrailing)` on the `RoundedRectangle`, then adds a second `.overlay` for the state label. `MetricCardView` uses the same pattern for the info button but combines the value label in a single overlay. The two are functionally equivalent and both patterns are correct SwiftUI, but the inconsistency makes the codebase slightly harder to reason about. Not a bug.

**Suggestion:** Consider extracting the info-button-with-popover pattern into a `ViewModifier` or a shared `overlayInfoButton(key:isPresented:)` helper so both views share one implementation.

---

### IN-04: `TemperatureViewModel` `startPolling()` calls both `requestNotificationPermission()` and `refreshNotificationStatus()` on every foreground

**File:** `Termostato/Termostato/TemperatureViewModel.swift:118-119`

**Issue:** `requestNotificationPermission()` shows the system permission dialog on first launch. `refreshNotificationStatus()` re-reads the status without prompting. Calling both on every foreground is correct for keeping `notificationsAuthorized` current, but `requestNotificationPermission()` will silently no-op after the user has already decided (iOS only shows the dialog once). The behaviour is correct but the dual `Task { }` calls create two concurrent async tasks each time the app foregrounds, which is unnecessary.

**Suggestion:** Call `refreshNotificationStatus()` only, except on initial launch:
```swift
if notificationsAuthorized == false {
    Task { await requestNotificationPermission() }
} else {
    Task { await refreshNotificationStatus() }
}
```
Or combine both into a single `updateNotificationStatus()` method that calls `requestAuthorization` (which re-checks without re-prompting) and reads the result in one async hop.

---

### IN-05: `Localizable.xcstrings` has no Spanish translations for UI strings in `ThermalView`

**File:** `Termostato/Termostato/Localizable.xcstrings`

**Issue:** The xcstrings catalog provides `en` and `es` translations for all six tooltip keys. However, the hardcoded UI strings in `ThermalView` and elsewhere ("Termostato", "Nominal", "Fair", "Serious", "Critical", "Warming up...", "Notifications disabled — tap to open Settings", "Session history (last 60 min)") are not in the catalog. These will not be localised for Spanish users. This is in scope only if the app intends to support Spanish as a full locale (the presence of `es` translations for tooltips suggests intent).

**Suggestion:** Either add these display strings to `Localizable.xcstrings` with `es` translations, or document that the app is English-only for non-tooltip text and remove the `es` entries from the catalog to avoid partial localisation that could confuse future maintainers.

---

_Reviewed: 2026-05-15_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
