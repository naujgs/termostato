---
phase: 4
slug: polling
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-13
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — no XCTest target in project |
| **Config file** | None |
| **Quick run command** | Manual Simulator launch — observe console for 30s |
| **Full suite command** | Manual smoke checks (all 3 success criteria) |
| **Estimated runtime** | ~30 seconds per spot-check |

---

## Sampling Rate

- **After every task commit:** Manual Simulator launch — observe console for `[CoreWatch] thermalState = …` printing at ~10s intervals (3 prints in 30s confirms 10s cadence)
- **After every plan wave:** All three success criteria checked manually in Simulator
- **Before `/gsd-verify-work`:** Full manual smoke suite must pass
- **Max feedback latency:** ~30 seconds (one Simulator launch cycle)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | POLL-01 | — | N/A | manual-smoke | — manual only — | N/A | ⬜ pending |
| 4-01-02 | 01 | 1 | POLL-01 | — | N/A | manual-smoke | — manual only — | N/A | ⬜ pending |
| 4-01-03 | 01 | 1 | POLL-01 | — | N/A | visual-inspection | — manual only — | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements — no test framework to scaffold. No XCTest target exists in the project. Manual verification protocol substitutes for automated tests.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Timer fires every 10s (chart density increases) | POLL-01 | No XCTest target; Timer.publish behavior is observable via debug console | Run in Simulator, observe `[CoreWatch] thermalState = …` prints — 3 prints should appear within ~30 seconds |
| history retains 360 data points | POLL-01 | No XCTest target; ring-buffer capacity requires runtime observation | Run 6-minute spot-check: after 60 readings at 10s the array should stop growing (confirm via debug print showing history count capped at 360) |
| Chart label displays "60 min" description | POLL-01 | Visual UI label, no snapshot tests | Open app in Simulator, verify chart sub-label reads "Session history (last 60 min)" |

---

## Validation Sign-Off

- [ ] All tasks have manual verify instructions or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without manual verify
- [ ] Wave 0 covers all MISSING references (N/A — no automated infra)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
