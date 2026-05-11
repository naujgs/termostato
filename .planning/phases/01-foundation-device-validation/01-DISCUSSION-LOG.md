# Phase 1: Foundation & Device Validation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 01-foundation-device-validation
**Areas discussed:** IOKit probe scope, Code reuse intent, Polling interval, ScenePhase approach

---

## IOKit Probe Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Write a minimal probe | Add ~5 lines of IOKit code, run on device, log result — decision record writes itself from real data | ✓ |
| Document known answer only | Skip IOKit code, write decision record from existing research in CLAUDE.md/REQUIREMENTS.md | |
| Skip the decision record too | IOKit is Out of Scope, strike success criterion #3 | |

**User's choice:** Write a minimal probe
**Notes:** None

---

## IOKit probe — cleanup after Phase 1

| Option | Description | Selected |
|--------|-------------|----------|
| Remove after Phase 1 | Delete probe once decision record captured; Phase 2 starts clean | ✓ |
| Keep behind a debug flag | Keep under `#if DEBUG` for future re-runs if iOS behavior changes | |

**User's choice:** Remove after Phase 1
**Notes:** None

---

## Code Reuse Intent

| Option | Description | Selected |
|--------|-------------|----------|
| Architectural seed | Create real `TemperatureViewModel` Phase 2 extends — no rewrite | ✓ |
| Throwaway spike | Simplest possible app (ContentView + print()), Phase 2 starts fresh | |
| Hybrid — minimal ViewModel | ViewModel stub with just enough shape to validate | |

**User's choice:** Architectural seed
**Notes:** None

---

## Polling Interval

| Option | Description | Selected |
|--------|-------------|----------|
| Every 5 seconds | Balanced — responsive, minimal battery impact | |
| Every 1 second | Maximally responsive, unnecessary overhead | |
| Every 10 seconds | Conservative, may feel sluggish | |
| Event-only | No timer, thermalStateDidChangeNotification only | |
| Every 30 seconds | User-specified via free text | ✓ |

**User's choice:** Every 30 seconds (free text)
**Notes:** User explicitly specified 30s — not one of the presented options

---

## ScenePhase Approach — mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| SwiftUI scenePhase | `@Environment(\.scenePhase)` + `.onChange(of:)` — pure SwiftUI | ✓ |
| UIApplication notifications | NotificationCenter observers in ViewModel — UIKit dependency | |
| Both | Split: scenePhase for View, UIApplication for ViewModel | |

**User's choice:** SwiftUI scenePhase
**Notes:** None

---

## ScenePhase Approach — timer lifecycle

| Option | Description | Selected |
|--------|-------------|----------|
| Cancel and re-create | Background: cancel timer. Foreground: new timer. Simple, no shared state. | ✓ |
| Pause / resume same timer | Keep timer reference, invalidate/restart. Requires nil-handling. | |

**User's choice:** Cancel and re-create
**Notes:** None

---

## Claude's Discretion

- IOKit bridging header setup
- Console logging format for Phase 1 output
- Xcode project settings (bundle ID, display name, signing team)

## Deferred Ideas

None
