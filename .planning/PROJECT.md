# Termostato

## What This Is

Termostato is a personal iOS app (sideloaded, not App Store) that monitors the iPhone's thermal state in real time. It displays the current thermal state (Nominal / Fair / Serious / Critical) on a color-coded badge, a session-length step-chart history, and delivers local push-notification alerts when the device overheats — whether the app is foregrounded or backgrounded.

## Core Value

The phone's thermal state, always visible at a glance — with an alert before it gets dangerously hot.

## Current State

**v1.0 shipped — 2026-05-13**

494 lines of Swift. Three phases, six plans, all verified on physical device.

- Xcode 26.4.1 + Swift 6.3 strict concurrency + SwiftUI + Swift Charts
- `ProcessInfo.thermalState` polling (30s) + `thermalStateDidChangeNotification` observer
- `UIApplication.beginBackgroundTask` for ~30s background execution window
- Free Apple ID sideload — 7-day certificate, USB install via Xcode

## Requirements

### Validated (v1.0)

- ✓ App installable via Xcode sideload (no App Store) — *Phase 1*
- ✓ Display iOS thermal state (Nominal / Fair / Serious / Critical) with color coding — *Phase 1 & 2*
- ✓ Session-length step-chart history (in-memory, 120-entry ring buffer) — *Phase 2*
- ✓ Local notifications at Serious/Critical with cooldown — *Phase 3*
- ✓ Background thermal alerts via `thermalStateDidChangeNotification` — *Phase 3*
- ✓ Permission-denied banner with Settings deep-link — *Phase 3*

### Active (v1.1+)

- [ ] State duration display ("Serious for 4 min")
- [ ] "Back to Nominal" recovery notification
- [ ] Persistent session history across app restarts

### Out of Scope

- App Store distribution — personal sideload only
- Numeric °C temperature — IOKit blocked by AMFI under free Apple ID (confirmed Phase 1, deferred indefinitely)
- APNs remote push — requires `aps-environment` entitlement; local notifications are the right approach
- Android / other platforms — iPhone only
- Persistent cross-session history — adds complexity for zero core-value gain in v1

## Context

- **Target device:** iPhone (any model running iOS 18+)
- **Dev machine:** MacBook Air, Apple M3, 16 GB RAM
- **Toolchain:** Xcode 26.4.1, Swift 6.3, free Apple Developer account (7-day signing)
- **Distribution:** Sideloaded directly via Xcode over USB
- **Data source:** `ProcessInfo.thermalState` (public, 4 levels) — IOKit numeric temp confirmed blocked

## Constraints

- **Platform:** iOS only
- **Signing:** Free Apple ID → 7-day certificate expiry, must re-install weekly
- **Background execution:** `beginBackgroundTask` buys ~30s; no indefinite background polling without APNs

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Sideload only (no App Store) | Avoids App Store review | ✓ Confirmed — installed via Xcode free Apple ID |
| IOKit for numeric temp | Public API only gives 4-level state | ✗ Blocked — AMFI prevents IOKit under free Apple ID. Numeric °C out of scope. |
| Session-length history, no persistence | Simplifies v1 | ✓ Confirmed — no CoreData/SQLite |
| SwiftUI over UIKit | Single-screen dashboard | ✓ Confirmed — SwiftUI throughout |
| `thermalStateDidChangeNotification` for background alerts | Event-driven, no polling timer needed in background | ✓ Confirmed — works with `beginBackgroundTask` window |
| `beginBackgroundTask` for background execution | Keeps process alive ~30s after backgrounding so observer can fire | ✓ Confirmed on device — notifications fire within window |
| Local notifications over APNs | No server infrastructure needed for personal sideloaded app | ✓ Confirmed — `UNUserNotificationCenter` works correctly |

## Evolution

This document evolves at phase transitions and milestone boundaries.

---
*Last updated: 2026-05-13 — v1.0 milestone complete*
