# Phase 4: Polling - Research

**Researched:** 2026-05-13
**Domain:** Swift/iOS — Timer interval adjustment, ring-buffer capacity, UI label copy
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| POLL-01 | App polls thermal state every 10 seconds (reduced from 30s) with the step-chart history window remaining at 60 minutes | Three discrete constant/string changes identified in two files — see Standard Stack and Code Examples sections |
</phase_requirements>

---

## Summary

Phase 4 is a surgical two-file change with zero new dependencies. The existing `TemperatureViewModel.swift` drives polling via `Timer.publish(every:on:in:).autoconnect()` with a hardcoded `30` second interval. The ring-buffer capacity is controlled by `private static let maxHistory = 120`. Changing the interval to `10` seconds and the capacity to `360` (10s × 360 = 3,600 seconds = 60 minutes) fully satisfies POLL-01.

A third change is required in `ContentView.swift`: the chart sub-label `"Session history (last 60 min)"` already says "60 min" and is technically accurate after the change, but must be verified to confirm it does not encode any stale number (it does not — the string is correct as-is). No new label text is needed.

No Swift API changes, no framework upgrades, no new files.

**Primary recommendation:** Change two numeric literals in `TemperatureViewModel.swift`. The ContentView label is already correct and requires no edit.

---

## Project Constraints (from CLAUDE.md)

- SwiftUI only — no UIKit
- Zero external dependencies — no SPM packages
- Swift 6 strict concurrency — `@MainActor` on ViewModel
- `@Observable` macro pattern, not `ObservableObject`/`@Published`
- No persistence layer — session data lives in plain Swift array
- Cancel-and-recreate timer pattern (no stored mutable timer reference) — D-07
- Xcode 26.4.1 / Swift 6.3 / iOS 18 minimum deployment target

---

## Standard Stack

### Core (unchanged — no new additions)
| File | Symbol | Current Value | New Value | Purpose |
|------|--------|---------------|-----------|---------|
| `TemperatureViewModel.swift:49` | `private static let maxHistory` | `120` | `360` | Ring-buffer capacity |
| `TemperatureViewModel.swift:111` | `Timer.publish(every:…)` | `30` | `10` | Polling interval (seconds) |
| `ContentView.swift:113` | `"Session history (last 60 min)"` | already correct | no change | Chart sub-label |

**Installation:** No new packages. No `npm install`, no SPM changes.

**Version verification:** N/A — no external packages involved. [VERIFIED: codebase grep]

---

## Architecture Patterns

### Current Structure (unchanged by this phase)
```
Termostato/
├── TemperatureViewModel.swift   # @Observable @MainActor — polling loop, ring buffer
├── ContentView.swift            # SwiftUI view — reads from ViewModel only
├── TermostatoApp.swift          # App entry point
└── NotificationDelegate.swift   # UNUserNotificationCenterDelegate
```

### Pattern 1: Cancel-and-recreate Timer (existing — D-07)
**What:** `timerCancellable?.cancel()` is called at the top of `startPolling()` before creating a fresh `Timer.publish`. No stored mutable timer state.
**Why it matters for this phase:** The `every:` parameter is the only change needed. The pattern is sound and must not be altered.

```swift
// Source: TemperatureViewModel.swift:103-114 [VERIFIED: codebase read]
func startPolling() {
    timerCancellable?.cancel()
    timerCancellable = Timer.publish(every: 10, on: .main, in: .common)  // <-- 30 → 10
        .autoconnect()
        .sink { [self] _ in
            self.updateThermalState()
        }
    updateThermalState()
    // ...
}
```

### Pattern 2: Ring Buffer (existing)
**What:** `history` array trimmed to `maxHistory` on every append in `updateThermalState()`.
**Why it matters:** Only the constant needs changing — the trim logic at line 144 already uses `Self.maxHistory`, so the ring buffer automatically honours the new capacity.

```swift
// Source: TemperatureViewModel.swift:49 [VERIFIED: codebase read]
private static let maxHistory = 360  // <-- 120 → 360 (10s × 360 = 60 min)
```

### Anti-Patterns to Avoid
- **Do not introduce a computed constant:** Keep `maxHistory` as a plain `static let`. Making it a computed var or deriving it from the interval adds unnecessary coupling.
- **Do not change the ring-buffer trim logic:** Line 144 already uses `Self.maxHistory`; touching it risks introducing an off-by-one.
- **Do not touch the background path:** `handleBackgroundThermalChange()` does not poll on a timer — it responds to `thermalStateDidChangeNotification`. Its behavior is unaffected by this change.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Interval scheduling | Custom RunLoop timer | `Timer.publish(every:on:in:).autoconnect()` | Already implemented, Combine-managed lifecycle |
| Capacity enforcement | Manual capacity tracking | `private static let maxHistory` + trim in `updateThermalState()` | Already implemented, one constant change is sufficient |

---

## Runtime State Inventory

> Included because this phase changes polling behavior that affects in-memory session state.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — session data is a plain Swift array, not persisted (D-06) | None |
| Live service config | None — no external services | None |
| OS-registered state | None — no Task Scheduler / launchd entries | None |
| Secrets/env vars | None | None |
| Build artifacts | None — no egg-info, no global installs | None |

**Key runtime note:** On first launch after update, the existing `history` array is empty (fresh session). The timer fires every 10s from `startPolling()` — no migration of old 30s data needed. [VERIFIED: codebase read — no persistence layer]

---

## Common Pitfalls

### Pitfall 1: maxHistory Comment Says "120 readings"
**What goes wrong:** The comment on line 49 references `120 readings` inline — if not updated, future readers (and AI assistants) may be confused about the intended capacity.
**Why it happens:** Comments often lag behind constant changes.
**How to avoid:** Update the comment on line 48 alongside the constant. The comment currently reads `/// Session history ring buffer — max 120 readings (D-05).`
**Warning signs:** Grep for `120` after the change to ensure no stale references remain.

### Pitfall 2: Stale "30-second delay" Comment
**What goes wrong:** The comment on line 116 reads `// Immediately read on start so the UI shows data without a 30-second delay.` — stale after the interval changes.
**Why it happens:** Inline comments reference the old interval value.
**How to avoid:** Update the comment to say "10-second delay" (or simply "polling delay").

### Pitfall 3: History Array Memory
**What happens:** 360 `ThermalReading` structs instead of 120. Each struct holds a `UUID`, a `Date`, and a `ProcessInfo.ThermalState` (a raw Int). Memory delta is negligible (< 1 KB). No concern.
**Why it matters:** No action needed, but the planner should not add a memory-check task.

### Pitfall 4: Chart X-Axis Density
**What happens:** At 10s intervals the chart will accumulate data 3× faster. The first 60 seconds will show 6 points instead of 2. This is the intended behavior per success criterion 1 ("observable via chart density").
**Why it matters:** No code change needed. The chart's `.chartXAxis(.hidden)` and time-based X axis handle variable density automatically via Swift Charts' internal scaling. [VERIFIED: codebase read — chartXAxis(.hidden) means no label crowding]

---

## Code Examples

### The Two Edits

**Edit 1 — TemperatureViewModel.swift line 49:**
```swift
// Before [VERIFIED: codebase read]
private static let maxHistory = 120

// After
private static let maxHistory = 360
```

**Edit 2 — TemperatureViewModel.swift line 111:**
```swift
// Before [VERIFIED: codebase read]
timerCancellable = Timer.publish(every: 30, on: .main, in: .common)

// After
timerCancellable = Timer.publish(every: 10, on: .main, in: .common)
```

**ContentView.swift line 113 — NO CHANGE NEEDED:**
```swift
// Already correct [VERIFIED: codebase read]
Text("Session history (last 60 min)")
```

**Comment updates (same file, same edit session):**
- Line 48: `/// Session history ring buffer — max 120 readings` → `max 360 readings`
- Line 116: `// …without a 30-second delay.` → `// …without a 10-second delay.`
- Line 101: `/// Start the 30-second polling timer.` → `/// Start the 10-second polling timer.`

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 30s polling interval | 10s polling interval | Phase 4 (this) | 3× more data points per minute |
| maxHistory = 120 (60 min at 30s) | maxHistory = 360 (60 min at 10s) | Phase 4 (this) | Ring buffer holds same wall-clock window |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | ContentView label "Session history (last 60 min)" requires no edit | Code Examples | Label would display stale text — low risk, easily verified by reading line 113 |

**A1 is LOW risk:** The label text was verified via codebase read. It says "60 min" which remains accurate after the change. [VERIFIED: codebase read — ContentView.swift:113]

---

## Open Questions

None. All three touch-points are identified with exact file/line locations.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is a pure code edit with no external dependencies beyond the existing Xcode toolchain.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None detected — no XCTest target, no test directory |
| Config file | None |
| Quick run command | Manual Simulator run — no automated test runner |
| Full suite command | N/A |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| POLL-01 | Timer fires every 10s (chart density increases) | manual-smoke | — manual only — | N/A |
| POLL-01 | history retains 360 data points | manual-smoke | — manual only — | N/A |
| POLL-01 | Chart label says "60 min" | visual-inspection | — | N/A |

**Manual-only justification:** No XCTest target exists in the project. `Timer.publish` behavior at a 10s interval is observable via the Simulator's debug console (`[Termostato] thermalState = …` prints every 10s). Ring-buffer capacity is verifiable by leaving the Simulator running for 60+ minutes and observing the history array size via the debug print output — or by a 6-minute spot-check (60 readings at 10s) confirming the array trims correctly at 360.

### Sampling Rate
- **Per commit:** Manual Simulator launch, observe console output for 30 seconds confirming 3 prints at ~10s intervals.
- **Phase gate:** All three success criteria checked manually before `/gsd-verify-work`.

### Wave 0 Gaps
- No test framework to install — project has no XCTest target.
- Manual verification protocol substitutes for automated tests.

*(No automated Wave 0 gap items — no test infrastructure to scaffold)*

---

## Security Domain

This phase changes two numeric literals and one comment. No authentication, session management, access control, input validation, cryptography, or network activity is involved. Security domain: NOT APPLICABLE to this phase.

---

## Sources

### Primary (HIGH confidence)
- `Termostato/Termostato/TemperatureViewModel.swift` — direct codebase read, lines 49, 101, 111, 116 [VERIFIED]
- `Termostato/Termostato/ContentView.swift` — direct codebase read, line 113 [VERIFIED]
- `.planning/REQUIREMENTS.md` — POLL-01 definition [VERIFIED]
- `.planning/ROADMAP.md` — Phase 4 success criteria [VERIFIED]
- `CLAUDE.md` (project) — stack constraints, timer pattern [VERIFIED]

### Secondary (MEDIUM confidence)
- None required — all findings derive from direct codebase inspection.

### Tertiary (LOW confidence)
- None.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — exact file/line locations confirmed by codebase grep and read
- Architecture: HIGH — patterns are unchanged; only constants change
- Pitfalls: HIGH — all identified from direct reading of the codebase

**Research date:** 2026-05-13
**Valid until:** No expiry — codebase is the source of truth; findings are stable until the files are edited.
