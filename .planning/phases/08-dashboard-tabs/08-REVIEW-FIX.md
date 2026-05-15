---
phase: 08-dashboard-tabs
fixed_at: 2026-05-15T00:00:00Z
review_path: .planning/phases/08-dashboard-tabs/08-REVIEW.md
iteration: 1
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 8: Code Review Fix Report

**Fixed at:** 2026-05-15
**Source review:** .planning/phases/08-dashboard-tabs/08-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 1
- Fixed: 1
- Skipped: 0

## Fixed Issues

### WR-01: `startPolling()` called on every `.active` transition including `.inactive → .active`

**Files modified:** `Termostato/Termostato/ContentView.swift`
**Commit:** b34269a
**Applied fix:** Changed the `onChange(of: scenePhase)` closure from `{ _, newPhase in` to `{ oldPhase, newPhase in }` and added an `if oldPhase == .background` guard inside the `.active` case. Polling (and the associated `requestNotificationPermission` / `refreshNotificationStatus` call path) now only restarts on a genuine background→active return, not on every `inactive→active` transition such as Notification Centre dismissal or call end. The `.background` stop path and `onAppear` initial start are unchanged.

---

_Fixed: 2026-05-15_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
