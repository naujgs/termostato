# Phase 3: Alerts & Notification System - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 03-alerts-notification-system
**Areas discussed:** Notification content, Background/foreground cooldown sharing

---

## Notification content

### Title

| Option | Description | Selected |
|--------|-------------|----------|
| State name only | "Serious" or "Critical" — glanceable, matches the badge label | |
| App name + state | "Termostato — Serious" — source clear in Notification Center | |
| Alert framing | "iPhone Overheating" — describes the event rather than mirroring the state name | ✓ |

**User's choice:** Alert framing — "iPhone Overheating"
**Notes:** User preferred describing the event over mirroring the state name.

---

### Body

| Option | Description | Selected |
|--------|-------------|----------|
| State level | "Thermal state: Serious" — precise, matches what the app shows | |
| Throttling warning | "Performance may be limited" — consequence in plain language | |
| Combined | "Thermal state: Serious — performance may be limited" — state + consequence | ✓ |

**User's choice:** Combined format
**Notes:** Both precision (state name) and consequence in one line.

---

### Action button

| Option | Description | Selected |
|--------|-------------|----------|
| Tap opens app | Standard iOS behavior — no extra buttons | |
| Dismiss button only | UNNotificationCategory with a Dismiss action | ✓ |
| You decide | Claude picks simplest default | |

**User's choice:** Dismiss button only
**Notes:** Tapping notification body still opens app (standard iOS); Dismiss button added for explicit acknowledgment without opening the app.

---

## Background/foreground cooldown sharing

### Cooldown scope

| Option | Description | Selected |
|--------|-------------|----------|
| Shared — carry over | One cooldown state for whole app lifecycle; prevents duplicate alerts across transitions | ✓ |
| Reset on foreground | Cooldown clears each time app foregrounds; re-fires if state still elevated | |

**User's choice:** Shared — carry over
**Notes:** Single `lastAlertedState` property covers both foreground and background notification paths.

---

### Cooldown reset trigger

| Option | Description | Selected |
|--------|-------------|----------|
| State drops below threshold | Clears when thermal state returns to Nominal/Fair; event-driven, no arbitrary timer | ✓ |
| Time-based (e.g. 10 min) | Re-fire after N minutes regardless of current state | |
| State escalates further | Only re-fire if state gets worse (Serious → skip, Critical → fire) | |

**User's choice:** State drops below threshold
**Notes:** Cooldown tied entirely to thermal state level, not time. Clean, deterministic behavior.

---

## Claude's Discretion

- Exact banner copy and visual styling for permission-denied UI
- `UNNotificationCategory` identifier string constant
- `UNUserNotificationCenter` delegate setup (foreground notification presentation)
- OSLog vs print() for background path logging

## Deferred Ideas

None — discussion stayed within phase scope.
