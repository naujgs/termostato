---
phase: 2
slug: dashboard-ui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-12
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — no XCTest target in project; manual Simulator/device verification only |
| **Config file** | none |
| **Quick run command** | N/A — manual Simulator verification |
| **Full suite command** | N/A |
| **Estimated runtime** | ~5 minutes (manual) |

---

## Sampling Rate

- **After every task commit:** Build in Xcode (⌘B must succeed with zero errors)
- **After every plan wave:** Run on Simulator, verify badge and chart visually
- **Before `/gsd-verify-work`:** Full manual checklist below must be complete
- **Max feedback latency:** ~5 minutes (Simulator boot + manual visual check)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | DISP-01 | — | N/A | manual | N/A | ✅ | ⬜ pending |
| 2-01-02 | 01 | 1 | DISP-01 | — | N/A | manual | N/A | ✅ | ⬜ pending |
| 2-02-01 | 02 | 2 | DISP-02 | — | N/A | manual | N/A | ✅ | ⬜ pending |
| 2-02-02 | 02 | 2 | DISP-02 | — | N/A | manual | N/A | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None — no automated test target exists and none is in scope for this phase. All verification is manual.

*Existing Xcode build system covers compile-time correctness. Functional correctness requires Simulator/device.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Badge shows correct state name and color for each of 4 levels (Nominal/Fair/Serious/Critical → green/yellow/orange/red) | DISP-01 | `ProcessInfo.thermalState` cannot be injected in unit tests without a custom abstraction out of scope for this phase | On Simulator: use `#Preview` with `@State` overrides cycling all 4 states; verify name and color match spec |
| Chart updates in real time as polling tick fires | DISP-02 | Requires live timer firing against SwiftUI rendering | On device: open app, observe chart receives new readings each tick |
| Chart enforces 120-entry cap without crash | DISP-02 | Ring buffer eviction requires extended runtime | On device: leave app open until 120+ readings accumulated; verify chart scrolls/shifts left, no crash |
| History resets on cold launch | DISP-02 | App lifecycle test | Kill app from app switcher, re-launch; verify chart starts empty then populates from first reading |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 300s (manual)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
