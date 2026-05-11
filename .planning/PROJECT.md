# Termostato

## What This Is

Termostato is a personal iOS app (sideloaded, not App Store) that monitors the internal temperature of an iPhone in real time. It displays both a numeric temperature reading (via private iOS APIs) and the system thermal state level, rendered in a live dashboard with a session-length history chart and push-notification alerts when the device overheats.

## Core Value

The phone's actual internal temperature, always visible at a glance — with an alert before it gets dangerously hot.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Display real-time numeric temperature (°C / °F) via private iOS thermal APIs
- [ ] Display iOS thermal state level (Nominal / Fair / Serious / Critical) via public API
- [ ] Dashboard UI with live temperature readout and session-length history chart
- [ ] Push notifications when temperature crosses a user-defined hot threshold
- [ ] App installable via Xcode sideload (no App Store)

### Out of Scope

- App Store distribution — personal sideload only
- Persistent history across sessions — session data only, no on-disk storage for v1
- Android / other platforms — iPhone only

## Context

- **Target device:** iPhone (any model supported by the iOS version Xcode targets)
- **Dev machine:** MacBook Air, Apple M3, 16 GB RAM
- **Toolchain:** Xcode (free, Mac App Store) + free Apple Developer account (7-day signing)
- **Distribution:** Sideloaded directly via Xcode over USB
- **Private API access:** Feasible because app is never submitted to App Store; no binary review gate
- **iOS thermal APIs:** `ProcessInfo.thermalState` (public, 4 levels) + IOKit / private CoreMotion thermal readings for numeric values

## Constraints

- **Platform:** iOS only — no cross-platform framework needed
- **API access:** Private APIs required for numeric temperature; accepted risk since sideloaded
- **Signing:** Free Apple ID → 7-day certificate expiry, must re-install weekly unless upgraded to $99/yr Developer account
- **Background execution:** Push-notification-based alerting needs a background task or local notification strategy; full background execution is restricted on iOS

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Sideload only (no App Store) | Avoids App Store review, enabling private API access | — Pending |
| Use private IOKit APIs for numeric temp | Public API only gives 4-level state, not raw °C | — Pending |
| Session-length history (not persistent) | Simplifies v1; persistent storage deferred | — Pending |
| Swift + UIKit or SwiftUI | Native stack, no added dependencies | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-11 after initialization*
