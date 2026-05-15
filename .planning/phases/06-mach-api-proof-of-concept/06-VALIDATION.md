---
phase: 6
slug: mach-api-proof-of-concept
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-15
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built into Xcode 26.4.1) |
| **Config file** | Termostato/TermostatoTests/ (if exists) |
| **Quick run command** | `xcodebuild test -scheme Termostato -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TermostatoTests 2>&1 \| tail -20` |
| **Full suite command** | `xcodebuild test -scheme Termostato -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 \| tail -40` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | CPU-02 | — | N/A | manual | Device probe | N/A | ⬜ pending |
| TBD | TBD | TBD | MEM-02 | — | N/A | manual | Device probe | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. Phase 6 is a validation/probe phase — primary verification is manual on-device testing.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| host_statistics returns valid CPU data | CPU-02 | Requires physical iOS 18 device — simulator may differ | Run app on device, open debug sheet, check CPU API status |
| host_statistics64 returns valid memory data | MEM-02 | Requires physical iOS 18 device — simulator may differ | Run app on device, open debug sheet, check memory API status |
| task_info returns per-process data | CPU-02, MEM-02 | Requires physical device to confirm sandbox behavior | Run app on device, open debug sheet, check per-process API status |
| Graceful fallback confirmed if system APIs blocked | CPU-02, MEM-02 | Design decision depends on probe results | Document in 06-VERDICTS.md |

*All phase behaviors require physical device verification — this is a probe/validation phase.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
