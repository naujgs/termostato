---
phase: 3
slug: alerts-notification-system
status: draft
nyquist_compliant: true
# nyquist_compliant justification: All three phase requirements (ALRT-01, ALRT-02, ALRT-03)
# depend on physical device thermal state behavior and OS notification delivery timing that
# cannot be reproduced in the Xcode Simulator. No simulator API exists to trigger
# ProcessInfo.ThermalState.serious or invoke thermalStateDidChangeNotification.
# Per RESEARCH.md Validation Architecture section, manual device testing is the validated
# and only feasible approach for this phase. Build verification (xcodebuild build) is the
# automated signal per task; manual device walkthrough is the phase acceptance gate.
wave_0_complete: true
# wave_0_complete: No unit test infrastructure is required or feasible for this phase's
# requirements. Manual device testing is the acceptance gate (see Manual-Only Verifications).
created: 2026-05-12
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — no test target; manual device testing is the acceptance gate |
| **Config file** | none |
| **Quick run command** | `xcodebuild build -project CoreWatch/CoreWatch.xcodeproj -scheme CoreWatch -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5` |
| **Full suite command** | Physical device install + full ALRT-01/02/03 manual walkthrough |
| **Estimated runtime** | Build: ~60 seconds; manual: ~10 minutes |

---

## Sampling Rate

- **After every task commit:** Run quick run command (build must succeed)
- **After every plan wave:** Full manual ALRT-01/02/03 device walkthrough
- **Before `/gsd-verify-work`:** All four success criteria TRUE on physical device
- **Max feedback latency:** Build: 60 seconds; manual gate: end of each wave

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | ALRT-01, ALRT-02, ALRT-03 | T-03-01, T-03-02 | N/A | build + manual | `xcodebuild build -project CoreWatch/CoreWatch.xcodeproj -scheme CoreWatch -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5` | N/A | ⬜ pending |
| 3-02-01 | 02 | 1 | ALRT-01 | — | N/A | build + manual | `xcodebuild build -project CoreWatch/CoreWatch.xcodeproj -scheme CoreWatch -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5` | N/A | ⬜ pending |
| 3-02-02 | 02 | 1 | ALRT-02, ALRT-03 | — | N/A | manual | Physical device test with debugger detached | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App requests notification permission on first launch | ALRT-01 | Simulator cannot accurately replicate permission prompt state | Deploy to physical device (fresh install or reset permissions via Settings), launch app, verify system permission dialog appears |
| Notification fires at Serious/Critical; cooldown prevents re-fire | ALRT-02 | Thermal state cannot be spoofed in Simulator; real device required for thermal escalation | Trigger Serious state on device (run CPU-intensive task), verify banner notification appears; keep state elevated 60s, verify no second notification fires |
| thermalStateDidChangeNotification fires when app is backgrounded | ALRT-03 | Background execution and suspension timing is device-dependent; Simulator does not simulate thermal events | Deploy to physical device, background the app with Xcode debugger detached, trigger thermal escalation, verify notification appears without foregrounding the app |
| Notification does not re-fire while state remains elevated | ALRT-02 | Cooldown logic depends on real notification delivery timing | Trigger Serious state, verify one notification; keep state elevated 60s, verify no second notification |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands (`xcodebuild build`)
- [x] No Wave 0 test file requirements — manual device testing is the validated approach
- [x] `nyquist_compliant: true` set in frontmatter with justification
- [ ] Sampling continuity: no 3 consecutive tasks without build verify
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s (build gate)
- [ ] All ALRT-01/02/03 manual verifications passed on physical device

**Approval:** pending
