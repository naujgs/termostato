---
phase: 02-dashboard-ui
reviewed: 2026-05-12T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - CoreWatch/CoreWatch/TemperatureViewModel.swift
  - CoreWatch/CoreWatch/ContentView.swift
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-05-12
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Both files are well-structured and follow the MVVM pattern correctly. The `@Observable @MainActor` ViewModel is properly constrained, the lifecycle wiring via `scenePhase` is idiomatic SwiftUI, and the Swift Charts integration is clean. Two warnings require attention: a strong-capture retain cycle in the Combine sink, and a double-poll on cold launch due to overlapping `onAppear` / `onChange(of: scenePhase)` firing. Three info-level items cover debug `print` statements in production code, a naming mismatch on the "ring buffer," and a cosmetic inaccuracy in the chart sub-label.

---

## Warnings

### WR-01: Strong self-capture in Combine sink creates retain cycle

**File:** `CoreWatch/CoreWatch/TemperatureViewModel.swift:67`

**Issue:** The `sink` closure uses `[self]` (strong capture). The `AnyCancellable` returned by `sink` is stored as `timerCancellable` on `self`, so `self` holds the cancellable, and the cancellable closure holds `self` — a retain cycle. If the view is torn down before `stopPolling()` is called (e.g., preview recycling, unit test teardown, or a future navigation change), the ViewModel will never deallocate. Swift 6 strict concurrency does not break this cycle automatically; only cancellation or weak capture does.

**Fix:**
```swift
timerCancellable = Timer.publish(every: 30, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in
        self?.updateThermalState()
    }
```

### WR-02: Double `startPolling()` on cold launch produces two back-to-back readings

**File:** `CoreWatch/CoreWatch/ContentView.swift:97-111`

**Issue:** On cold launch, both `onAppear` (line 109) and `onChange(of: scenePhase)` with `.active` (line 99) fire, causing `startPolling()` — and therefore `updateThermalState()` — to be called twice within the same run-loop tick. This appends two identical `ThermalReading` entries to `history` with the same timestamp and state, making the history inaccurate from the very first second. On subsequent re-foreground events only `onChange` fires, so launch behavior differs from resume behavior.

The guard in `startPolling()` cancels the previous timer and recreates it, but it still calls `updateThermalState()` immediately each time, so two readings are produced regardless.

**Fix:** Remove the `onAppear` call and rely solely on `onChange(of: scenePhase)`. SwiftUI delivers the initial `.active` scene phase change reliably on app launch:

```swift
// Remove this block entirely:
// .onAppear {
//     viewModel.startPolling()
// }

// Keep only the scenePhase observer, which also fires on cold launch:
.onChange(of: scenePhase) { _, newPhase in
    switch newPhase {
    case .active:
        viewModel.startPolling()
    case .background:
        viewModel.stopPolling()
    case .inactive:
        break
    @unknown default:
        break
    }
}
```

If there is any concern about `onChange` not firing before the first frame, an alternative is to keep `onAppear` and gate `startPolling()` with an `isStarted` flag on the ViewModel to make the call idempotent at the read level.

---

## Info

### IN-01: `print()` debug statements not guarded by `#if DEBUG`

**File:** `CoreWatch/CoreWatch/TemperatureViewModel.swift:72, 80, 92`

**Issue:** Three `print(...)` calls will appear in release builds. On a sideloaded personal app this is low-stakes, but the output (thermal state every 30 seconds) will appear in Console.app and device logs indefinitely.

**Fix:** Wrap with a debug guard, or use `os_log` with a subsystem if structured logging is desired:

```swift
#if DEBUG
print("[CoreWatch] Polling started.")
#endif
```

### IN-02: "Ring buffer" comment describes an Array with `removeFirst()`, which is O(n)

**File:** `CoreWatch/CoreWatch/TemperatureViewModel.swift:46`

**Issue:** The comment reads `"Session history ring buffer"` but the implementation uses `Array.removeFirst()`, which is O(n) due to element shifting. With `maxHistory = 120` this is functionally irrelevant. The mislabeling is the only concern — a future developer might assume ring-buffer semantics (constant-time head removal) and be surprised.

**Fix:** Either rename the comment to `"Session history (capped array)"` or, if true ring-buffer semantics are ever needed, swap to a `Deque` from the Swift Collections package. For 120 elements, no action is required beyond the comment correction:

```swift
/// Session history (capped array) — max 120 readings (D-05). Session-only, never persisted (D-06).
```

### IN-03: Chart sub-label claims "last 60 min" regardless of actual session duration

**File:** `CoreWatch/CoreWatch/ContentView.swift:87`

**Issue:** The label `"Session history (last 60 min)"` is displayed from the moment the first reading appears. During the first 60 minutes, the label is misleading (e.g., after 2 minutes it shows "last 60 min" but only 4 readings exist). The buffer capacity is 60 minutes at 30-second intervals, but the label states a maximum, not the actual window shown.

**Fix:** Make the label dynamic based on actual history span, or use wording that describes the capacity rather than the current window:

```swift
// Option A — dynamic actual duration:
let span: String = {
    guard let first = viewModel.history.first else { return "" }
    let minutes = Int(Date().timeIntervalSince(first.timestamp) / 60)
    return minutes < 2 ? "last \(minutes < 1 ? "<1" : "\(minutes)") min" : "last \(minutes) min"
}()
Text("Session history (\(span))")

// Option B — simple capacity label (no computation):
Text("Session history (up to 60 min)")
```

Option B is simpler and avoids the dynamic computation in the view body.

---

_Reviewed: 2026-05-12_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
