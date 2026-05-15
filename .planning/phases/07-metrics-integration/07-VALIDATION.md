---
phase: 7
slug: metrics-integration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-15
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — no XCTest/Swift Testing target in this project |
| **Config file** | None |
| **Quick run command** | Build in Xcode (⌘B) — compiler errors = red |
| **Full suite command** | Deploy to physical iOS 18 device, verify all 3 tabs display live data |
| **Estimated runtime** | ~2 min (build + deploy + manual on-device check) |

---

## Sampling Rate

- **After every task commit:** Run `⌘B` (build) — must compile with 0 errors
- **After every plan wave:** Deploy to physical device, verify the wave's outputs on-device
- **Before `/gsd-verify-work`:** All 6 requirements verified on-device

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 1 | — | — | N/A | build | `xcodebuild build` | ✅ | ⬜ pending |
| 7-01-02 | 01 | 1 | — | — | N/A | build | `xcodebuild build` | ✅ | ⬜ pending |
| 7-02-01 | 02 | 1 | CPU-01, MEM-01 | — | N/A | manual | Deploy + verify CPU/Memory tabs | ✅ | ⬜ pending |
| 7-02-02 | 02 | 2 | CPU-02, MEM-02 | — | N/A | manual | Deploy + verify system readings | ✅ | ⬜ pending |
| 7-03-01 | 03 | 2 | DASH-01, DASH-02 | — | N/A | manual | Deploy + verify TabView + thermal regression | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None — no test infrastructure to create. The project has no XCTest or Swift Testing target. All validation is on-device observation.

*Existing infrastructure (Xcode build system) covers all phase requirements that can be automated.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App CPU% visible and updating on 5s interval | CPU-01 | Requires physical iOS 18 device; Mach APIs unavailable in Simulator | Open CPU tab, observe App CPU card updating every ~5 seconds with non-zero percentage |
| App Memory MB visible and updating | MEM-01 | Requires physical device | Open Memory tab, observe App Memory card showing ~79 MB, updating each tick |
| System CPU% visible (Phase 6 confirmed accessible) | CPU-02 | Requires physical device | Open CPU tab, observe System CPU card showing plausible % (non-zero after first delta) |
| System Memory free/used GB visible | MEM-02 | Requires physical device | Open Memory tab, observe System Memory card showing free and used GB values |
| TabView with 3 tabs (Thermal, CPU, Memory) navigable | DASH-01 | UI interaction — physical device | Tap each tab; confirm correct content loads; tab bar icons visible |
| Thermal tab regression-free | DASH-02 | Must verify existing features didn't break | On Thermal tab: temperature badge visible, chart scrolls, long-press debug sheet appears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify (build) or manual-only justification
- [ ] Sampling continuity: build check after every task commit
- [ ] Wave 0 covers all MISSING references (N/A — no test target)
- [ ] No watch-mode flags
- [ ] Feedback latency < 2 minutes (build + deploy)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
