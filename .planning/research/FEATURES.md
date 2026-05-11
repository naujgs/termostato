# Feature Landscape

**Domain:** iOS device internal temperature / thermal monitoring app (sideloaded, personal use)
**Researched:** 2026-05-11
**Confidence:** MEDIUM — App Store competitors surveyed; UX conventions from Swift Charts + HIG docs; some private-API specifics remain LOW confidence until implementation

---

## Table Stakes

Features users expect from any temperature/thermal monitor. Missing one of these and the app feels broken or pointless.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Live numeric temperature display (°C/°F) | Core value prop — the number is the product | Low (once API access solved) | Requires private IOKit/CoreMotion API; public `ProcessInfo.thermalState` alone is not enough |
| Unit toggle (°C ↔ °F) | Every temperature app has this; omitting it feels amateurish | Low | Persist preference via UserDefaults |
| Thermal state badge/label | `ProcessInfo.thermalState` is the only guaranteed-public signal; users of competing apps expect to see Nominal / Fair / Serious / Critical | Low | Four states, color-coded (green/yellow/orange/red is the de-facto convention) |
| Color-coded status indicator | Heat level should be obvious at a glance, no reading required | Low | Color band or icon tint tied to thermal state enum |
| Session history line chart | All surveyed competitors (Thermals, Status Monitor, System Status) show a time-series graph of the current session | Medium | Swift Charts `LineChart` + `AreaMark`; x-axis = elapsed time, y-axis = temperature °C or °F |
| Alert/notification when threshold crossed | Explicitly in project requirements; users need this to put the phone down | Medium | Local notification via `UNUserNotificationCenter`; foreground polling + state-change observer |
| User-configurable alert threshold | Without this, the alert fires at a hardcoded number that may not match the user's tolerance | Low | Simple numeric picker or stepper; default ~42 °C (device warning territory) |

---

## Differentiators

Features that would make Termostato stand out from App Store competitors. Not required for v1, but worth knowing about for roadmap ordering.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Thermal-state band overlay on chart | Annotates exactly when device entered Fair/Serious/Critical; competing apps show thermal state separately from the temperature line | Medium | Swift Charts `RuleMark` or `RectangleMark` as background bands; requires storing state-change timestamps alongside readings |
| Crosshair / scrub interaction on chart | Tap/drag to inspect a past reading at a specific time | Medium | iOS 17+ `chartXSelection` modifier; makes the history chart interactive rather than decorative |
| "Cool-down timer" estimate | After a Critical alert, estimate how long until Nominal based on recent rate-of-change | High | Requires trend analysis; speculative — rate of cooling is not linear and depends on ambient conditions |
| Apple Watch companion glance | Show live thermal state + temperature on wrist | High | Separate WatchKit target; overkill for personal v1 |
| Export to CSV / JSON | Useful for debugging sustained heat events; Thermals app offers this | Low-Medium | Only worth adding once persistent history exists (deferred in v1) |
| Lock screen / home screen widget | Thermal state visible without opening app | Medium | WidgetKit; requires at minimum `ProcessInfo.thermalState` (the numeric reading may not be accessible from an extension) |
| Trend-based alert ("rising fast") | Alert fires not at a fixed threshold but when temperature rises N degrees in M seconds | High | More nuanced than threshold alerting; complex to tune without false positives |

---

## Anti-Features

Things to deliberately exclude from v1. Including them adds scope and risk without adding core value.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Persistent cross-session history + database | PROJECT.md explicitly defers this; adds CoreData/SQLite dependency, migration concerns, and privacy questions | Keep everything in-memory; clear on app launch |
| Network/speed/latency monitoring | Scope creep — competing system-monitor apps bundle this but it has nothing to do with thermal state | Reject feature; refer users to dedicated network tools |
| Battery wear / health metrics | Different domain; Apple restricts detailed battery health APIs for App Store apps (sideload may expose more, but it's a new scope item) | Out of scope v1 |
| CPU/memory usage dashboard | Useful but orthogonal to heat; turns the app into a system monitor instead of a focused thermal tool | Resist adding; the focus is temperature |
| Push/remote notifications via APNs server | Requires a server, APNS certificates, and ongoing infrastructure — massively disproportionate for a sideloaded personal app | Use local notifications (`UNUserNotificationCenter`) delivered entirely on-device |
| Social sharing / screenshots | No user need for a personal tool | Skip entirely |
| iPad / macOS port | Different thermal profiles, different API availability; dilutes focus | iPhone only as per PROJECT.md |

---

## Feature Dependencies

```
Private IOKit/CoreMotion API access
    └─> Live numeric temperature reading
            └─> Session history chart
            └─> Threshold alert (numeric comparison)
            └─> Trend-based alert [differentiator, deferred]

ProcessInfo.thermalState (public API)
    └─> Thermal state badge/label
    └─> Color-coded indicator
    └─> Thermal-state band overlay on chart [differentiator]
    └─> thermalStateDidChangeNotification
            └─> State-change alert (fires on Serious or Critical)

UNUserNotificationCenter permission grant
    └─> Threshold alert notification delivery
    └─> State-change alert notification delivery

Unit preference (UserDefaults)
    └─> Live display
    └─> Chart y-axis label
    └─> Alert threshold input
```

---

## Alert Pattern Recommendation

Three alert strategies exist in the monitoring-app space. For Termostato v1:

**Recommended: hybrid threshold + state-change**

1. **Threshold-based** — Fire a local notification when the numeric temperature crosses a user-set value (e.g. 42 °C). Simple, predictable, user-controlled. Implement first.
2. **State-change-based** — Also fire when `thermalState` transitions to `.serious` or `.critical` via `NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification ...)`. This is free (no polling) and catches cases where the private numeric API and the system threshold diverge.

Avoid for v1:
- **Trend-based** alerts (rising N degrees/minute) — requires a stable rolling-window calculation, hard to tune, high false-positive risk with no usage data to calibrate against.

**Notification delivery constraint:** iOS heavily restricts background execution. The app must be foregrounded (or have Background App Refresh active) for polling to run. For state-change notifications via `ProcessInfo.thermalStateDidChangeNotification`, the system delivers them even in the background as long as the app has not been terminated. Local notifications can be posted from within the app's background state. This is sufficient for a personal monitoring tool where the user typically has the phone nearby.

---

## History Chart Conventions

Based on Swift Charts documentation and competitor app patterns:

| Axis | Convention | Notes |
|------|-----------|-------|
| X-axis | Elapsed time since session start (MM:SS or HH:MM) | Not wall-clock time — relative time is more useful for "how long has it been hot?" |
| Y-axis | Temperature in the user's selected unit | Always show the unit label; cap visible range at ~20–80 °C (36–176 °F) to avoid axis compression on normal readings |
| Line | Single `LineMark` connecting readings | Anti-aliased; medium weight (2pt) |
| Area fill | Semi-transparent fill below line | Improves readability of peaks at a glance |
| Thermal state bands | `RectangleMark` background bands (green / yellow / orange / red) behind the line | Differentiator; shows when the device was in each thermal state |
| Threshold marker | Horizontal `RuleMark` at user's alert temperature | Reminds user where their alert fires |
| Current reading callout | Trailing annotation on the last data point showing live numeric value | Avoids needing a separate "current temp" label in the chart area |
| Interaction | iOS 17+ `chartXSelection` drag-to-scrub | Differentiator; skip for v1 if scope is tight |

**Sampling rate:** Poll every 5 seconds (consistent with competing apps). At 5 s intervals, a 30-minute session = 360 data points — trivially held in memory, renders without performance issues in Swift Charts.

---

## MVP Recommendation

**Build in this order:**

1. Live temperature readout (numeric + unit toggle) — validates that the private API works on the target device
2. Thermal state badge with color coding — free confidence signal using public API
3. Threshold alert (local notification) with user-configurable temperature — delivers the "alert before it's dangerous" core value
4. State-change alert (`.serious` / `.critical` transitions) — zero extra polling cost, significantly improves alert reliability
5. Session history line chart — makes the app feel complete; allows users to see how temperature evolved

**Defer:**
- Thermal-state band overlay: add in a second milestone once the basic chart works
- Crosshair scrub interaction: non-essential, add if polish milestone follows
- Widget: requires separate WidgetKit target; skip v1
- Export: requires persistent storage; out of scope per PROJECT.md

---

## Sources

- App Store: [Thermals](https://apps.apple.com/us/app/thermals/id1567050762), [Status Monitor](https://apps.apple.com/us/app/status-monitor/id6743127438), [System Status & Device Monitor](https://apps.apple.com/us/app/system-status-device-monitor/id6760554255)
- Apple Developer: [ProcessInfo.ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum), [thermalState property](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- Apple Developer: [Swift Charts](https://developer.apple.com/documentation/Charts), [Managing Notifications HIG](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)
- Apple Developer: [BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler)
- Community: [Apple Developer Forums — iOS CPU/GPU/battery temperature](https://developer.apple.com/forums/thread/696700)
