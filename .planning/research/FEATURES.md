# Feature Landscape

**Domain:** iOS device internal temperature / thermal monitoring app (sideloaded, personal use)
**Researched:** 2026-05-11 (v1.0); updated 2026-05-13 (v1.1); updated 2026-05-14 (v1.2)
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

Features that would make CoreWatch stand out from App Store competitors. Not required for v1, but worth knowing about for roadmap ordering.

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

Three alert strategies exist in the monitoring-app space. For CoreWatch v1:

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

## v1.2 Feature Research: System Health Metrics (CPU, Memory, Battery)

Research date: 2026-05-14. Covers features being considered after the user asked: "Are we able to access temperature data of more than one component/area? Like CPU, GPU, battery?"

**Context:** IOKit numeric temperature APIs are confirmed blocked under free Apple ID on iOS 18. Numeric °C for any component is out of reach. However, three categories of system health data ARE accessible via public sandbox-safe APIs: CPU usage (app process only), system memory pressure, and battery level/state. This section defines what to build from these.

---

### API Accessibility Map

Before defining features, confirm what each candidate API can actually return:

| Metric | API | Scope | Sandboxed? | Confidence |
|--------|-----|-------|------------|------------|
| CPU usage % (this app's process) | `task_threads()` + `thread_info()` with `THREAD_BASIC_INFO` | Per-process (app only) | Yes — works in sandbox | MEDIUM — widely used in open-source iOS monitors; sandbox restrictions affect cross-process reads, not self-reads |
| System-wide CPU % | `host_processor_info()` / `host_statistics()` | Whole device | Uncertain — may be blocked by sandbox on iOS 18 | LOW — Apple forums note sandbox may block mach host APIs; "works from user space but not sandbox" |
| System memory (used / free / wired) | `host_statistics64()` with `HOST_VM_INFO64` | Whole device | Uncertain — same sandbox concern as host CPU | LOW — gist author noted "probably works on iOS but haven't tried"; not confirmed in sandbox |
| App memory footprint | `task_info()` with `TASK_VM_INFO` → `phys_footprint` | Per-process (app only) | Yes — Apple-recommended approach | HIGH — documented, Apple uses this in Instruments |
| Battery level (0.0–1.0) | `UIDevice.current.batteryLevel` | Device | Yes — public API | HIGH — documented public UIKit API |
| Battery charge state | `UIDevice.current.batteryState` (.unknown / .unplugged / .charging / .full) | Device | Yes — public API | HIGH — documented public UIKit API |
| Battery time remaining | No public API | — | N/A | HIGH — confirmed not available via any public API |
| Memory pressure level | `ProcessInfo.processInfo.isLowMemoryWarning` notification | System | Yes — public | HIGH — `UIApplication.didReceiveMemoryWarningNotification` is public |
| Per-core CPU breakdown | `host_processor_info()` per-processor flavor | Whole device | Uncertain / likely blocked | LOW |
| GPU temperature / load | No public API | — | N/A | HIGH — confirmed not available |

**Conclusion:** Build features around the HIGH-confidence APIs. Treat LOW-confidence mach host APIs as implementation-time experiments that may or may not work — do not promise them to users.

---

### Feature A: App Process CPU Usage %

**Category:** Differentiator — adds meaningful context to thermal state. If the device is at "Serious" thermal and CPU is pegged at 95%, the user understands why.

**What it shows:** The percentage of one CPU core being consumed by the CoreWatch process itself. This is honest about its scope — it is not "the device's CPU load," it is "how hard this app is working." On a monitoring app the value will typically be low (1–5%), which is itself useful signal (the monitor itself is not the problem).

**API approach:** Sum `cpu_usage` fields across all of the app's threads via `task_threads()` + `thread_info(thread, THREAD_BASIC_INFO, ...)`. Divide by `TH_USAGE_SCALE` (1000) to get 0.0–1.0. This is the approach used by GDPerformanceView-Swift and every iOS in-app performance overlay library. It is self-scoped (reads only this process's threads) and confirmed sandbox-safe.

```swift
// Sketch — add to TemperatureViewModel
var appCPUUsage: Double {
    var threadList: thread_act_array_t?
    var threadCount = mach_msg_type_number_t(0)
    guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
          let threads = threadList else { return 0 }
    defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads),
                          vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)) }
    var total = 0.0
    for i in 0..<Int(threadCount) {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(THREAD_INFO_MAX)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE)
        }
    }
    return total
}
```

**Limitation:** This only reflects CoreWatch's own process. It will not tell you that a game running in the foreground is consuming 80% CPU. For a personal thermal dashboard this is a reasonable limitation — the primary signal is still `thermalState`.

**Display recommendation:** A single numeric percentage label ("CPU: 3.2%") in a secondary row below the thermal badge. A SwiftUI `Gauge` view (iOS 16+, `.accessoryCircular` style) works well for an at-a-glance ring showing 0–100%. No chart needed for v1.2 — the existing thermalState chart already provides the session history narrative.

**Update cadence:** Same 10s polling as thermalState. CPU usage for a monitoring app changes slowly. More frequent polling (e.g. 1s) would produce noisy values with no user benefit.

**Complexity:** Low-Medium. The Mach C API requires a bridging header or `import Darwin`. Wrapping it cleanly in a `@MainActor` method on the ViewModel is straightforward. No additional permissions or entitlements needed.

**Dependencies:** None on existing architecture beyond adding a computed property to `TemperatureViewModel`.

**Confidence:** MEDIUM — The per-process thread approach is well-established in the iOS developer community (GDPerformanceView-Swift, numerous Apple Forum answers). The sandbox restriction applies to reading OTHER processes' thread info, not the app's own. The Swift 6 strict concurrency requirement means the Mach call must happen off the main actor or be explicitly `nonisolated`.

---

### Feature B: App Memory Footprint

**Category:** Table stakes for a health dashboard. Every competitor app (System Status, System Monitor & Device Info) shows memory. Users expect it.

**What it shows:** How much physical memory (RAM) CoreWatch is consuming, in MB. This is the `phys_footprint` value from `TASK_VM_INFO` — the same number Xcode's memory gauge shows.

**API approach:** Apple recommends `task_info()` with `TASK_VM_INFO` and reading `task_vm_info.phys_footprint`. This is a documented, sanctioned API for reading one's own process memory. Apple's own engineers posted this in the developer forums.

```swift
var appMemoryMB: Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Double(info.phys_footprint) / 1_048_576  // bytes → MB
}
```

**Limitation:** This is the app's own memory footprint, not system-wide free/used memory. System-wide memory requires `host_statistics64()` which has uncertain sandbox behavior on iOS 18. Do not promise system-wide memory until it is confirmed working on device.

**Display recommendation:** A label showing "Memory: 42 MB" is sufficient. A `ProgressView` (linear bar) against a fixed upper bound (e.g. 500 MB for context) provides visual intuition. Alternatively, pair it with the CPU gauge in a two-column row of `Gauge` views.

**Update cadence:** Same 10s polling. App memory for a passive monitoring app changes slowly and smoothly — no need for faster updates.

**Complexity:** Low. Same Mach import as CPU feature. One additional computed property.

**Dependencies:** If built alongside Feature A (CPU), they share the same Darwin/Mach import infrastructure.

**Confidence:** HIGH — `TASK_VM_INFO` / `phys_footprint` is explicitly documented and recommended by Apple for reading own-process memory. Not a gray-area API.

---

### Feature C: Battery Level and Charge State

**Category:** Table stakes. Every system health monitor shows battery. The data is available via a clean, public UIKit API with zero risk.

**What it shows:**
- Battery level as a percentage (0–100%)
- Charge state: Unplugged / Charging / Full / Unknown

**API:** `UIDevice.current.batteryLevel` (returns Float 0.0–1.0; multiply by 100 for %) and `UIDevice.current.batteryState` (4-case enum). Requires `UIDevice.current.isBatteryMonitoringEnabled = true` set once on app launch. Without this, `batteryLevel` returns -1.0 and `batteryState` returns `.unknown`.

**Notification-based updates:** Register for `UIDevice.batteryLevelDidChangeNotification` and `UIDevice.batteryStateDidChangeNotification`. Level notifications fire at most once per minute (Apple's rate limit). State notifications fire immediately on plug/unplug events.

**Battery time remaining:** No public API exists. `UIDevice` does not expose it. This is confirmed not available.

**Display recommendation:** Show level as a percentage label ("Battery: 78%") and state as an icon or short label ("Charging" / "On battery"). A `Gauge` view with a battery-appropriate 0–100 range and a green/yellow/red tint (below 20% = red, 20–50% = yellow, above 50% = green) is the natural SwiftUI pattern. The existing thermal state color convention primes the user to read color as severity.

**Update cadence:** Notification-driven, not polling. Set `isBatteryMonitoringEnabled = true` once and subscribe to notifications. No timer needed. The ViewModel adds two published properties (`batteryLevel: Float` and `batteryState: UIDevice.BatteryState`) and updates them in the notification handler.

**Complexity:** Low. Pure UIKit public API, no bridging header needed, no entitlements. Two `NotificationCenter` observers added to the existing ViewModel pattern.

**Dependencies:** Must set `isBatteryMonitoringEnabled = true` before reading. This is a per-session setting — not persisted.

**Confidence:** HIGH — `UIDevice.batteryLevel` and `batteryState` are documented public APIs. Confirmed working in sideloaded apps (no special entitlements required). Rate-limited to ~1 min for level notifications, immediate for state changes.

---

### Feature D: System-Wide Memory (Exploratory — Implement and Verify)

**Category:** Differentiator if it works; drop if sandbox blocks it.

**What it shows:** Device-wide RAM broken down as: used, wired (kernel-reserved), free/available. This is the data shown by apps like System Status and Activity Monitor.

**API:** `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` with `vm_statistics64_t`. Multiply page counts by `vm_kernel_page_size` to get bytes.

**Sandbox risk:** This API reads host-level kernel statistics. On iOS, the sandbox philosophy restricts apps to information about themselves. Multiple Apple Forum posts from 2016–2020 note that mach host APIs "may run afoul of the sandbox at some point." The exact current behavior on iOS 18 under a free sideload is not confirmed in public sources as of May 2026.

**Recommendation:** Implement behind a safe guard — wrap the call to return nil on failure. Test on device. If it returns valid data, ship it. If KERN_SUCCESS is not returned or values are obviously wrong, drop the feature and note it in project docs. Do not block the milestone on this feature.

**Display if it works:** Three-segment horizontal bar (wired / used / free) with byte counts. This is the conventional display in all competitor apps surveyed.

**Update cadence:** Same 10s polling as other metrics. System memory changes slowly.

**Complexity:** Medium — requires bridging header, pointer manipulation similar to Feature A. Risk is the API silently returning garbage or failing on iOS 18 sandbox.

**Confidence:** LOW for sandbox compatibility on iOS 18 sideload. HIGH for the API call itself being correct if the sandbox permits it.

---

### Feature E: SwiftUI Gauge for Metric Display

**Category:** UI pattern — not a standalone feature, but the recommended display primitive for all new metrics.

**What it is:** `Gauge` is a native SwiftUI view added in iOS 16 (available in this project's deployment target). It supports both linear and circular styles. The `.accessoryCircular` style renders as a partial arc ring — ideal for a compact dashboard showing multiple metrics at once.

**Why use it instead of custom views:**
- Zero dependencies, pure SwiftUI
- Tintable with `.tint(Color)` — use the same color convention as the thermal badge (green / yellow / orange / red)
- Scales automatically across Dynamic Type sizes
- Supports a `currentValueLabel` in the center of the ring
- Reads as a standard iOS UI element — users understand it immediately

**Recommended layout:** Two `Gauge` views side by side in an `HStack` (CPU % and battery %) with the app memory footprint as a text label below. This keeps the screen single-screen without requiring a scroll view. The existing thermalState chart fills the lower half of the screen unchanged.

**Complexity:** Low. SwiftUI declarative, no new state management needed beyond the ViewModel properties from Features A–C.

---

### v1.2 Feature Summary Table

| Feature | Category | API | Sandbox Safety | Complexity | Priority |
|---------|----------|-----|---------------|------------|----------|
| App CPU % | Differentiator | `task_threads` + `thread_info` | Confirmed safe (self-read) | Low-Med | P1 — implement |
| App memory footprint | Table stakes | `task_info` TASK_VM_INFO | HIGH — Apple-recommended | Low | P1 — implement |
| Battery level + state | Table stakes | `UIDevice.batteryLevel` / `batteryState` | HIGH — public API | Low | P1 — implement |
| System-wide memory | Differentiator | `host_statistics64` | LOW — uncertain on iOS 18 sandbox | Medium | P2 — implement and verify on device |
| Gauge display layout | UI pattern | SwiftUI `Gauge` (iOS 16+) | N/A | Low | P1 — use for all new metrics |
| Per-core CPU breakdown | Anti-feature | `host_processor_info` per-processor | LOW — likely sandbox-blocked | N/A | Drop — not worth the risk |
| Battery time remaining | Anti-feature | No public API | N/A | N/A | Drop — API does not exist |
| GPU temperature/load | Anti-feature | No public API (IOKit blocked) | N/A | N/A | Drop — confirmed blocked |

---

### v1.2 Anti-Features (What NOT to Build)

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| System-wide CPU % | `host_processor_info` is likely sandbox-blocked on iOS 18; returning wrong values is worse than not showing the metric | Show app CPU only; label it clearly as "App CPU" |
| Battery time remaining | No public API. Implementing an estimate from level-change rate is complex and inaccurate. | Show level % and state only |
| Per-core CPU bars | `host_processor_info` per-processor flavor has same sandbox uncertainty as system-wide CPU | Not worth the risk for a personal tool |
| Rolling CPU/memory charts | The existing thermalState chart already owns that screen real estate. Adding three more charts creates a cluttered multi-scroll interface. | Use Gauge rings for current value; no chart for new metrics in v1.2 |
| Memory warning alert | `didReceiveMemoryWarning` fires only under extreme conditions; almost never actionable for the user of a monitoring app | Omit; thermal alerts are the primary notification mechanism |

---

### v1.2 Feature Dependencies

```
UIDevice.isBatteryMonitoringEnabled = true (set in ViewModel.init)
    └─> batteryLevel display
    └─> batteryState display
    └─> UIDevice.batteryLevelDidChangeNotification
    └─> UIDevice.batteryStateDidChangeNotification

Darwin/Mach bridging (import Darwin or bridging header)
    └─> app CPU % (task_threads + thread_info)
    └─> app memory footprint (task_info TASK_VM_INFO)
    └─> system-wide memory (host_statistics64) [optional / verify on device]

SwiftUI Gauge (iOS 16+, in deployment target)
    └─> CPU gauge display
    └─> battery gauge display
```

---

### Design References for v1.2

**System Status (techet.net/sysstat):** The reference app for this genre on iOS. Uses separate pages per metric category (CPU, Memory, Battery, Storage, Network). Not appropriate to copy — CoreWatch should remain a single-screen dashboard, not a multi-page system inspector. Take: the visual convention of real-time graphs per metric. Reject: the paginated navigation structure.

**GDPerformanceView-Swift:** Open-source overlay showing CPU %, memory, FPS above the status bar. Confirms that the per-process `task_threads` approach works in a standard iOS app context (though it targets in-app dev overlays, not sideloaded monitors). Design reference for compact metric display.

**SwiftUI Gauge (Apple HIG):** The `.accessoryCircular` gauge style is explicitly documented for widgets and compact UI. Its circular ring design is immediately legible for percentage metrics. Color gradient via `.tint()` matches the existing thermal badge color language.

---

## Sources

- App Store: [Thermals](https://apps.apple.com/us/app/thermals/id1567050762), [Status Monitor](https://apps.apple.com/us/app/status-monitor/id6743127438), [System Status & Device Monitor](https://apps.apple.com/us/app/system-status-device-monitor/id6760554255)
- Apple Developer: [ProcessInfo.ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum), [thermalState property](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- Apple Developer: [Swift Charts](https://developer.apple.com/documentation/Charts), [Managing Notifications HIG](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)
- Apple Developer: [BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler)
- Apple Developer: [Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- Apple Developer: [Energy Efficiency Guide — Minimize Timer Use](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeTimerUse.html)
- Apple Developer: [UIDevice.batteryLevel](https://developer.apple.com/documentation/uikit/uidevice/batterylevel), [UIDevice.BatteryState](https://developer.apple.com/documentation/uikit/uidevice/batterystate)
- Apple Developer: [Gauge view documentation](https://developer.apple.com/documentation/swiftui/gauge)
- Community: [Apple Developer Forums — iOS CPU/GPU/battery temperature](https://developer.apple.com/forums/thread/696700)
- Community: [Apple Developer Forums — Obtaining CPU usage by process](https://developer.apple.com/forums/thread/655349)
- Community: [Apple Developer Forums — Swift 3 iOS Memory Usage](https://developer.apple.com/forums/thread/64665)
- Community: [Apple Developer Forums — how to overall cpu utilization of iphone device](https://developer.apple.com/forums/thread/11393)
- Community: [leminlimez gist — IOPMPowerSource Temperature key, systemgroup.com.apple.powerlog entitlement](https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc)
- Community: [algal gist — Get virtual memory usage on iOS or macOS (vm_statistics64)](https://gist.github.com/algal/cd3b5dfc16c9d577846d96713f7fba40)
- Community: [GDPerformanceView-Swift — per-process CPU/memory overlay](https://github.com/dani-gavrilov/GDPerformanceView-Swift)
- Community: [SwiftLee — App Icon Generator no longer needed with Xcode 14](https://www.avanderlee.com/xcode/replacing-app-icon-generators/)
- Community: [iDevice Central — TrollStore on iOS 17.0.1–26.2](https://idevicecentral.com/tweaks/can-you-install-trollstore-on-ios-17-0-1-ios-18-3/)
- Community: [TrollStore GitHub (opa334)](https://github.com/opa334/TrollStore)
- Community: [iOS Guide — Installing TrollStore](https://ios.cfw.guide/installing-trollstore/)
- Reference app: [System Status by Techet](https://techet.net/sysstat/)
- Reference app: [System Monitor & Device Info (App Store)](https://apps.apple.com/us/app/system-monitor-device-info/id6741153865)
- SwiftUI: [Gauge — accessoryCircular style (useyourloaf.com)](https://useyourloaf.com/blog/swiftui-gauges/)
- SwiftUI: [SwiftUI Gauge — appcoda.com](https://www.appcoda.com/swiftui-gauge/)
