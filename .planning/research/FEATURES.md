# Feature Landscape

**Domain:** iOS device internal temperature / thermal monitoring app (sideloaded, personal use)
**Researched:** 2026-05-11 (v1.0); updated 2026-05-13 (v1.1)
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

## v1.1 Feature Research: App Icon, Numeric Temperature, 10s Polling

Research date: 2026-05-13. Covers the three features targeted in the v1.1 milestone.

---

### Feature 1: App Icon

**Category:** Table stakes. Any production-feeling app must have a custom icon. The Xcode placeholder (white/gray default) signals "dev build" — even for a personal tool it degrades the experience.

**How it works on iOS 18 sideloaded apps:**

iOS applies the same icon pipeline to sideloaded and App Store apps. The home screen, Spotlight, and Settings all pull from the same `AppIcon` asset catalog entry. No special treatment for sideloaded installs.

**Required sizes — Xcode 14+ (includes Xcode 26.4.1):**

Since Xcode 14, the asset catalog supports a "Single Size" mode. You provide one 1024×1024 PNG and Xcode generates all sizes at build time. This is the correct approach for new projects and is what modern Xcode projects default to.

| Mode | What you provide | What Xcode generates |
|------|-----------------|---------------------|
| Single Size (Xcode 14+) | One 1024×1024 PNG | All required sizes automatically |
| Legacy multi-size | Individual PNGs for each slot | Nothing — you must provide each |

The generated sizes that iOS 18 uses at runtime:
- 180×180 px — Home screen @3x (Super Retina)
- 120×120 px — Home screen @2x (older Retina)
- 87×87 px — Settings @3x
- 58×58 px — Settings @2x
- 80×80 px — Spotlight @2x
- 60×60 px — Notifications @3x
- 40×40 px — Notifications @2x

**Technical requirements:**
- PNG format, no alpha channel (fully opaque)
- No pre-applied rounded corners — iOS applies the squircle mask automatically
- sRGB color space recommended

**When no icon is set:** iOS displays a generic white square (or grey default icon). The app still installs and runs. Occasionally the icon fails to render after a fresh sideload and requires a device restart to appear — this is a known Xcode/iOS caching quirk, not a missing-icon bug.

**Complexity:** Low. Drop one 1024×1024 PNG into the AppIcon asset catalog slot. No code changes needed.

**Dependencies on existing architecture:** None. Pure asset change.

**Confidence:** HIGH — Verified via official Apple documentation and Xcode 14 release notes from SwiftLee (avanderlee.com).

---

### Feature 2: Numeric Temperature via IOKit IOPMPowerSource (TrollStore Path)

**Category:** Table stakes for this app's core value (the project's stated reason for v1.1). Without it the app shows only 4-level categorical state.

**How IOKit temperature access works:**

The relevant key is `"Temperature"` inside the `IOPMPowerSource` dictionary. The value is an integer in centidegrees Celsius (hundredths of a degree). Divide by 100 to get °C.

```swift
// The key and unit (verified from leminlimez gist and iOS-Battery-Info-Demo)
let rawValue = batteryInfo["Temperature"] as? NSNumber  // e.g. 3150
let celsius = (rawValue?.doubleValue ?? 0) / 100.0      // → 31.50 °C
```

**Entitlement required:** `systemgroup.com.apple.powerlog`

Under a standard free Apple ID sideload, AMFI blocks this entitlement. The app compiles and installs but the IOKit call returns no temperature data (confirmed in Phase 1 research). TrollStore bypasses AMFI by exploiting the CoreTrust bug, allowing arbitrary entitlements — including `systemgroup.com.apple.powerlog` — to be preserved on install.

**TrollStore compatibility — critical constraint:**

TrollStore exploits a CoreTrust/AMFI vulnerability patched in iOS 17.0.1. Support matrix:

| iOS Version | TrollStore supported? |
|-------------|----------------------|
| 14.0 beta 2 – 16.6.1 | Yes |
| 16.7 RC (20H18) | Yes |
| 17.0 | Yes (via TrollRestore tool) |
| 17.0.1 and later | No — patch applied by Apple |
| iOS 18.x | No |
| iOS 26.x | No |

**This is the single most important constraint for v1.1.** The target device must be on iOS 17.0 or earlier. The project's target device runs iOS 18+ (per PROJECT.md "Target device: iPhone (any model running iOS 18+)"). This means the TrollStore IOKit path is blocked on the current target device. The numeric temperature feature cannot be delivered via TrollStore on iOS 18.

**What "Temperature" key actually returns:**

The `IOPMPowerSource` `"Temperature"` key reflects battery temperature, not CPU die temperature. On iPhones the battery thermal sensor is located near the battery — it correlates with but is not identical to SoC temperature. This is still more useful than the 4-level `thermalState` enum. At idle the value is typically in the 28–35 °C range; under heavy load it reaches 38–45 °C before the thermal state transitions to Serious.

**Confidence:** HIGH for the key name and unit (verified from leminlimez gist). HIGH for TrollStore iOS version cap (verified from official TrollStore GitHub and iDevice Central). HIGH for iOS 18 incompatibility.

**UI pattern for displaying numeric temperature alongside the thermal badge:**

The established pattern in thermal monitoring apps is to show the numeric °C reading as secondary text inside or directly below the badge, not as a replacement for the state label. Two sub-patterns:

1. **Badge + subtitle** (recommended): Keep the large bold state label ("Serious") as the primary read. Place the numeric value as a smaller caption below it ("38.2 °C"). Preserves the at-a-glance color cue while adding the numeric precision.

2. **Badge replaced by number** (not recommended): Show only "38.2 °C" in the badge. Loses the state name. Forces the user to remember thresholds to interpret the number.

For this app's existing `RoundedRectangle` badge with `.overlay { Text(thermalStateLabel) }`, the natural extension is to add a `VStack` inside the overlay with two `Text` views: the state label at `.largeTitle` weight and the °C value at `.title3` or `.body` below it. The temperature text can be conditionally rendered — showing only when numeric data is available, so the badge degrades gracefully when IOKit returns nothing.

**Complexity:** Medium. Requires:
- Bridging header to import IOKit C headers
- `getBatteryInfo()` function calling `IOServiceGetMatchingService` / `IORegistryEntryCreateCFProperties`
- Entitlement added to the `.entitlements` file
- `TemperatureViewModel` extended with `numericTemperature: Double?` published property
- `ContentView` updated to render the secondary label inside the badge overlay
- TrollStore install flow replacing the Xcode sideload (device must be on a compatible iOS version)

**Blocker:** iOS 18 device is incompatible with TrollStore. This feature cannot ship to the current target device. Either accept this as a known limitation (the feature works when tested on an older device) or remove it from v1.1 scope.

---

### Feature 3: Polling Interval — 30s → 10s

**Category:** Differentiator (UX responsiveness improvement), not table stakes. The app already works at 30s; 10s makes state transitions feel snappier.

**How ProcessInfo.thermalState polling works:**

`ProcessInfo.processInfo.thermalState` is a synchronous property read — no I/O, no syscall overhead comparable to network or disk. The Timer.publish call wakes the main thread, reads the property, updates the array, and returns. The entire operation is microseconds of CPU time.

**Trade-offs: 10s vs 30s:**

| Dimension | 10s interval | 30s interval |
|-----------|-------------|-------------|
| UI responsiveness | State shown within 10s of change | State shown within 30s of change |
| Battery impact | Negligible — timer wake overhead is immeasurable at this frequency | Also negligible |
| CPU overhead | Immeasurable for a single property read | Immeasurable |
| Notification latency | 10s worst-case additional lag before polling path fires | 30s worst-case additional lag |
| History resolution | 3× more data points per minute | Baseline |
| Ring buffer fill rate | 120-entry buffer covers 20 minutes at 10s | Covers 60 minutes at 30s |

**The notification path already catches state transitions in real time.** `thermalStateDidChangeNotification` fires immediately when iOS changes the thermal state — regardless of polling interval. The polling timer is a belt-and-suspenders fallback for the foreground UI update, not the primary alert mechanism.

**Apple's guidance on timer energy:** Apple recommends against frequent polling in favor of event-driven approaches, and advises setting a tolerance of ~10% on repeating timers to allow system batching. For a 10s timer, set `tolerance` to 1.0 seconds. This allows the OS to batch the wakeup with other system activity, reducing energy impact further.

**Ring buffer consequence:** At 10s polling, the existing 120-entry ring buffer covers 20 minutes of history (down from 60 minutes at 30s). If "session history" should still cover ~60 minutes, the buffer size should be increased to 360 entries. At one `ThermalReading` struct per entry (a UUID, Date, and enum value — roughly 80–100 bytes), 360 entries is ~36 KB — still trivially in memory.

**Code change is a one-liner in TemperatureViewModel.swift:**

```swift
// Change in startPolling():
Timer.publish(every: 10, on: .main, in: .common)   // was: every: 30
```

Plus optionally updating the comment on line 114 in `ContentView.swift` ("Session history (last 60 min)") to reflect the new coverage.

**Complexity:** Low. One integer constant change. Optionally also resize the ring buffer.

**Dependencies on existing architecture:** `Timer.publish(every:on:in:)` in `startPolling()`. The `.autoconnect().sink` pattern is unchanged.

**Confidence:** HIGH for the change itself. HIGH that battery impact is negligible (Apple Energy Guide + community sources agree timer wakeup overhead at 10s frequency is unmeasurable). MEDIUM for the ring buffer recommendation (derived from arithmetic, not a verified constraint).

---

## v1.1 Feature Summary Table

| Feature | Category | Complexity | Blocker? | Key Dependency |
|---------|----------|------------|----------|----------------|
| Custom app icon | Table stakes (visual) | Low | None | AppIcon asset catalog slot |
| Numeric °C via TrollStore | Table stakes (core value) | Medium | iOS 18 incompatible with TrollStore | Device must be iOS ≤ 17.0 |
| 10s polling interval | Differentiator (responsiveness) | Low | None | `startPolling()` in TemperatureViewModel |

---

## Sources

- App Store: [Thermals](https://apps.apple.com/us/app/thermals/id1567050762), [Status Monitor](https://apps.apple.com/us/app/status-monitor/id6743127438), [System Status & Device Monitor](https://apps.apple.com/us/app/system-status-device-monitor/id6760554255)
- Apple Developer: [ProcessInfo.ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum), [thermalState property](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- Apple Developer: [Swift Charts](https://developer.apple.com/documentation/Charts), [Managing Notifications HIG](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)
- Apple Developer: [BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler)
- Apple Developer: [Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- Apple Developer: [Energy Efficiency Guide — Minimize Timer Use](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeTimerUse.html)
- Community: [Apple Developer Forums — iOS CPU/GPU/battery temperature](https://developer.apple.com/forums/thread/696700)
- Community: [leminlimez gist — IOPMPowerSource Temperature key, systemgroup.com.apple.powerlog entitlement](https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc)
- Community: [SwiftLee — App Icon Generator no longer needed with Xcode 14](https://www.avanderlee.com/xcode/replacing-app-icon-generators/)
- Community: [iDevice Central — TrollStore on iOS 17.0.1–26.2](https://idevicecentral.com/tweaks/can-you-install-trollstore-on-ios-17-0-1-ios-18-3/)
- Community: [TrollStore GitHub (opa334)](https://github.com/opa334/TrollStore)
- Community: [iOS Guide — Installing TrollStore](https://ios.cfw.guide/installing-trollstore/)
