---
phase: 3
slug: alerts-notification-system
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-12
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in, ships with Xcode 26.4.1) |
| **Config file** | none — standard Xcode test target |
| **Quick run command** | `xcodebuild test -scheme Termostato -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20` |
| **Full suite command** | `xcodebuild test -scheme Termostato -destination 'platform=iOS Simulator,name=iPhone 16'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | ALRT-01 | — | N/A | unit | `xcodebuild test -scheme Termostato ...` | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 1 | ALRT-02 | — | N/A | unit | `xcodebuild test -scheme Termostato ...` | ❌ W0 | ⬜ pending |
| 3-01-03 | 01 | 2 | ALRT-03 | — | N/A | manual | Physical device test with debugger detached | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `TermostatoTests/AlertsTests.swift` — stubs for ALRT-01, ALRT-02
- [ ] `TermostatoTests/NotificationPermissionTests.swift` — permission grant/deny flows

*Background delivery (ALRT-03) cannot be automated in Simulator — see Manual-Only Verifications.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| thermalStateDidChangeNotification fires when app is backgrounded | ALRT-03 | Simulator does not simulate thermal state changes; background suspension timing is device-dependent | Deploy to physical device, background the app, use Xcode's thermal simulation or run a CPU-intensive task, verify notification appears without opening the app |
| Notification does not re-fire while state remains elevated | ALRT-02 | Cooldown logic depends on real notification delivery timing | Trigger Serious state, verify one notification; keep state elevated 60s, verify no second notification |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
