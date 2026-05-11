# Project Research Summary

**Project:** Termostato
**Domain:** iOS device internal temperature / thermal monitoring (sideloaded personal tool)
**Researched:** 2026-05-11
**Confidence:** MEDIUM — public API paths are HIGH confidence; numeric temperature via IOKit is empirically constrained and must be validated on device

---

## Executive Summary

Termostato is a single-screen foreground dashboard app built with SwiftUI, Swift Charts, and `UserNotifications` — all built-in Apple frameworks. Zero external dependencies are required. The app reads thermal data from two sources: `ProcessInfo.thermalState` (public, always works, 4-level categorical) and `IOPMPowerSource` via IOKit (private, numeric °C, may be blocked). The architecture is MVVM with a single `@Observable @MainActor` ViewModel, an `AsyncStream`-based polling service, and an event-driven notification gate. The build order is deliberately bottom-up: foundation types, then private API bridge, then ViewModel, then UI — placing the highest-risk component (IOKit access) at the front of the queue.

The central risk is that the numeric temperature path is blocked under standard Xcode sideloading. The IOKit `IOPMPowerSource` `Temperature` key requires the private entitlement `systemgroup.com.apple.powerlog`, which AMFI enforces at the kernel level regardless of installation method. A free or paid $99/yr Apple Developer certificate cannot carry this entitlement. The IOKit call returns empty data silently — no crash, no error — meaning the failure is invisible unless tested explicitly on device before any UI is built. The project must treat Phase 1 as a device validation spike: confirm IOKit behavior under the actual signing configuration before investing time in the numeric display UI. If IOKit returns nothing, the primary data source falls back to `ProcessInfo.thermalState`, and the numeric display shows "–°C" with a note that TrollStore is required to unlock it.

Background alerting and foreground numeric display are architecturally separate paths and must be designed that way from the start. The polling timer (IOKit + `thermalState` reads every 2 seconds) only runs while the app is in the foreground. For background alerts, the only viable mechanism is `ProcessInfo.thermalStateDidChangeNotification`, which iOS delivers to backgrounded (not terminated) apps. This event-driven path eliminates any need for background fetch or polling in the background. The two alert triggers — numeric threshold crossing (foreground-only, polling-based) and thermal state escalation (background-capable, event-driven) — are complementary and should both be implemented.

---

## Key Findings

### Recommended Stack

The entire app is buildable with Apple's own SDK. Toolchain: Xcode 26.4.1 (latest stable as of 2026-05-11; Apple renamed from 16.x to 26.x at WWDC 2025), Swift 6.3, targeting iOS 18.x minimum deployment. SwiftUI is the right choice over UIKit for a single-screen dashboard. Swift Charts provides a `LineMark` history chart in ~20 lines of code. `UserNotifications` handles local threshold alerts with no special entitlement. IOKit is accessed via a C bridging header for the private battery temperature read.

**Core technologies:**
- **Xcode 26.4.1 + Swift 6.3**: toolchain — latest stable; Swift 6 strict concurrency enforced by default, use `@MainActor` on the ViewModel
- **SwiftUI (built-in)**: UI framework — declarative, correct fit for a single-screen live dashboard; UIKit adds zero value
- **Swift Charts (built-in, iOS 16+)**: session history chart — zero dependency, `LineMark` + `AreaMark` handles the time-series use case natively
- **`ProcessInfo.thermalState` (Foundation)**: primary data source — public, sandbox-safe, 4-level thermal classification, always works
- **IOKit via C bridging header**: numeric temperature source — private, best-effort; returns `nil` silently when blocked
- **`UserNotifications` (built-in)**: local alert delivery — no special entitlement required, works in sideloaded apps with free Apple ID

### Expected Features

The features table maps cleanly onto two buckets: what users will consider broken if absent (table stakes), and what makes the app stand out (differentiators). Persistent history, network monitoring, battery health, and APNs push are explicit anti-features.

**Must have (table stakes for v1):**
- Live numeric temperature display (°C / °F) with graceful "–°C" degradation — the core value prop
- Unit toggle (°C ↔ °F), persisted to `UserDefaults` — omitting it feels amateurish
- Thermal state badge with 4-level color coding (green / yellow / orange / red) — free confidence signal
- User-configurable alert threshold — without it, the alert fires at a hardcoded number
- Threshold-based local notification — the app's stated purpose
- `thermalStateDidChangeNotification` alert on `.serious` / `.critical` — zero extra cost, background-capable
- Session history line chart — makes the app feel complete

**Should have (polish / differentiators, defer to second milestone):**
- Thermal-state band overlay on chart (`RectangleMark` background bands)
- Threshold `RuleMark` on chart — visual reminder of where the alert fires
- Crosshair / scrub interaction (iOS 17+ `chartXSelection`)

**Defer to v2+:**
- WidgetKit widget — requires a separate extension target; `ProcessInfo.thermalState` access from extension unverified
- Cool-down timer estimate — requires trend analysis, speculative without usage data
- Apple Watch companion — separate WatchKit target, out of scope
- Export to CSV / JSON — requires persistent history, deferred per PROJECT.md

### Architecture Approach

Single-process, foreground-primary, no network or persistence layer. Shallow MVVM: a C bridging shim (`ThermalBridge`) wraps the IOKit call; `ThermalSensorService` wraps the bridge in an `AsyncStream<ThermalReading>`; `ThermalViewModel` (`@Observable`, `@MainActor`) consumes the stream, maintains a fixed-capacity `RingBuffer<ThermalReading>`, and calls `NotificationGate` on each reading. The `thermalStateDidChangeNotification` path is a parallel channel merged into the same `ThermalReading` type.

**Major components:**
1. `ThermalBridge` (C/ObjC shim) — single point of private IOKit contact; returns `-1.0` sentinel on failure; isolated for mockability
2. `ThermalSensorService` — wraps bridge in `AsyncStream`; owns 2-second foreground poll timer; merges `thermalStateDidChangeNotification` into stream
3. `ThermalReading` (value type) — `struct`, `Sendable`; timestamp + celsius + thermalState; shared type across all layers
4. `RingBuffer<ThermalReading>` — fixed-capacity (3,600 samples = 2 hrs at 2s interval) circular buffer; O(1) append; caps chart dataset size
5. `ThermalViewModel` (`@Observable`, `@MainActor`) — single source of truth; drives `NotificationGate`; wires `scenePhase` to start/stop polling
6. `NotificationGate` — rate-limits `UNUserNotificationCenter` calls; 60-second cooldown + hysteresis; no UI dependencies
7. `DashboardView` / `SessionChartView` / `SettingsView` — dumb SwiftUI views; read ViewModel, no business logic

### Critical Pitfalls

1. **IOKit numeric temperature blocked by AMFI on standard sideloads** — `IOPMPowerSource` `Temperature` key requires `systemgroup.com.apple.powerlog`, a private entitlement AMFI enforces at kernel level. The call returns empty data silently. Validate IOKit behavior on the actual device in Phase 1 as a spike before building any numeric display UI.

2. **Background timer death kills polling-based alerts** — iOS suspends the polling loop within seconds of backgrounding. Use `thermalStateDidChangeNotification` as the sole background alert trigger. Polling-based threshold alerts are foreground-only and must say so in the UI.

3. **Notification permission denied on first ask is permanent** — iOS will not re-show the system prompt. Gate `requestAuthorization` behind a user-initiated action (first threshold configuration). Handle `.denied` state explicitly with a Settings deep-link banner.

4. **Notification flood at threshold boundary** — the polling interval can trigger a notification every 2 seconds while temperature oscillates at the threshold. Implement the `NotificationGate` cooldown (60-second minimum + hysteresis) before shipping any alert functionality.

5. **Swift Charts renders unbounded data O(n) per frame** — no capacity cap degrades chart performance within 30 minutes on older devices. The `RingBuffer` with fixed capacity must be part of the initial data model design, not a retrofit.

---

## Implications for Roadmap

### Phase 1: Foundation and Device Validation Spike

**Rationale:** The IOKit numeric temperature path is the single highest-risk item. It must be validated under the actual signing configuration on the target device before any UI work begins. If it fails silently, every numeric display feature needs to be reframed as TrollStore-gated. Discovering this in Phase 3 wastes all UI work built on a false assumption.

**Delivers:**
- `ThermalReading` struct (shared data contract)
- `RingBuffer<T>` with fixed capacity (prevents chart performance regression)
- `ThermalBridge` C shim with confirmed IOKit behavior on target device
- `ThermalSensorService` with `AsyncStream` + 2-second poll loop
- `ThermalViewModel` (`@Observable`, `@MainActor`) wired to sensor service
- `scenePhase` observer to start/stop polling
- Console-level proof of temperature readings (data flow confirmed, not UI)
- Written decision record: "IOKit returns data / IOKit blocked — numeric display requires TrollStore"

**Addresses:** Live temperature data pipeline (prerequisite for every other feature)
**Avoids:** Building UI on an unvalidated private API; unbounded array growth; background thread ViewModel mutations
**Research flag:** Needs on-device validation; cannot be unit-tested under the actual provisioning profile without a physical device

---

### Phase 2: Dashboard UI

**Rationale:** Once the data pipeline is proven, the foreground display is straightforward SwiftUI. No architectural unknowns — connecting the ViewModel to views.

**Delivers:**
- `DashboardView` with large numeric readout (or "–°C" graceful degradation)
- Thermal state badge with 4-level color coding
- Unit toggle (°C / °F) with `UserDefaults` persistence
- `SessionChartView` using Swift Charts `LineMark` + `AreaMark` reading from `RingBuffer`
- Threshold `RuleMark` on chart
- "Cert expires in N days" indicator

**Addresses:** Live numeric display, thermal state badge, session history chart, unit toggle (all table-stakes features)
**Avoids:** Connecting chart to unbounded array (already handled by `RingBuffer` from Phase 1)
**Research flag:** None — all patterns are well-documented SwiftUI + Swift Charts

---

### Phase 3: Alerts and Notification System

**Rationale:** Alerts depend on the data pipeline (Phase 1) and the settings UI needs a dashboard to attach to (Phase 2). The two alert channels — polling-based numeric (foreground-only) and event-driven state-change (background-capable) — must be built together here to make their architectural separation explicit.

**Delivers:**
- `NotificationGate` with 60-second cooldown + hysteresis
- `SettingsView` with user-configurable threshold picker
- Foreground threshold-based local notification (fires when `celsius >= threshold`)
- Background `thermalStateDidChangeNotification` alert (fires on `.serious` / `.critical`)
- `requestAuthorization` gated behind first threshold configuration (not app launch)
- `.denied` state handler with Settings deep-link banner
- UI copy distinguishing foreground-only numeric alerts from background state-change alerts

**Addresses:** User-configurable threshold, threshold alert, state-change alert
**Avoids:** Notification flood; background polling assumption; permission denial silent failure
**Research flag:** Background notification delivery under free Apple ID must be tested on device — not in Xcode with debugger attached (debugger suppresses app suspension)

---

### Phase 4: Polish (optional second milestone)

**Rationale:** Differentiator features add visual richness but have no bearing on core value. Defer until the core three phases are stable.

**Delivers:**
- Thermal-state `RectangleMark` background bands on the history chart
- iOS 17+ `chartXSelection` drag-to-scrub interaction
- UX refinements from device testing

**Addresses:** Chart differentiators from FEATURES.md
**Research flag:** None — documented Swift Charts patterns

---

### Phase Ordering Rationale

- Phase 1 first because IOKit validation is the highest-risk unknown; failure changes the scope of every subsequent phase
- Phase 2 before Phase 3 because settings/threshold UI must attach to a visible dashboard; notification logic without a UI to configure it creates untestable code
- The two alert channels (polling-based numeric, event-driven state-change) built together in Phase 3 to force the architectural separation to be explicit
- Phase 4 last because it adds no new dependencies and can be dropped without affecting core value

### Research Flags

Phases needing device validation:
- **Phase 1:** IOKit private API — must be validated on the target physical device under the actual free Apple ID signing configuration; simulator and unit tests cannot substitute
- **Phase 3:** Background notification delivery — must be tested by launching from home screen, backgrounding, and inducing a thermal state change; Xcode debugger suppresses app suspension

Phases with standard patterns (skip dedicated research):
- **Phase 2:** SwiftUI dashboard + Swift Charts — well-documented, established patterns, no unknowns
- **Phase 4:** Swift Charts advanced features — documented Apple APIs

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Xcode 26.4.1 verified via xcodereleases.com; all frameworks are first-party Apple; zero external dependencies eliminate version-conflict risk |
| Features | MEDIUM | Table stakes from App Store competitor survey; UX conventions from Swift Charts docs + HIG; private API feature set is LOW confidence until device-validated |
| Architecture | HIGH | `@Observable`, `AsyncStream`, `UNUserNotificationCenter`, and `scenePhase` patterns are documented Apple APIs; only `ThermalBridge` is speculative |
| Pitfalls | HIGH | IOKit entitlement constraint corroborated across Apple Developer Forums, leminlimez gist, Battman docs, George Garside blog, and Flutter issue #60406; background suspension behavior is well-documented iOS behavior |

**Overall confidence:** MEDIUM-HIGH — the architecture and stack are solid; the numeric temperature path has a known feasibility gate that must be resolved in Phase 1 before any commitments about the feature set can be confirmed.

### Gaps to Address

- **IOKit on the specific target device and iOS version:** The `Temperature` key in `IOPMPowerSource` may not be present on all device/iOS combinations even when the entitlement is available. Phase 1 spike must test on the actual device. Resolution: device validation spike in Phase 1.

- **`thermalStateDidChangeNotification` delivery when backgrounded on free Apple ID:** Community sources confirm it fires in the background, but behavior under a free developer profile has not been independently verified for this entitlement combination. Resolution: test in Phase 3 by backgrounding the app under real conditions (charging + CPU load to induce a state change).

- **dyld cache iOS version alignment:** If private API headers are extracted from the dyld cache for development reference, they must come from firmware matching the exact iOS version on the target device. Mismatched headers risk silent runtime failures. Resolution: use `ipsw` to extract headers from matching firmware; pin test device iOS version during active development.

---

## Sources

### Primary (HIGH confidence)
- [Apple Developer Docs — ProcessInfo.ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)
- [Apple Developer Docs — thermalStateDidChangeNotification](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification)
- [Apple Developer Docs — UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [Apple Developer Docs — Swift Charts](https://developer.apple.com/documentation/charts)
- [Apple Developer Docs — Migrating to @Observable](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [xcodereleases.com](https://xcodereleases.com/) — Xcode 26.4.1 confirmed latest stable, 2026-04-16

### Secondary (MEDIUM confidence)
- [Apple Developer Forums — iOS CPU/GPU/battery temperature](https://developer.apple.com/forums/thread/696700)
- [Apple Developer Forums — Swift Charts large dataset performance](https://developer.apple.com/forums/thread/740314)
- [Apple Developer Forums — iOS background execution limits](https://developer.apple.com/forums/thread/685525)
- [Dev.to — iOS sideloading mechanics 2025](https://dev.to/1_king_0b1e1f8bfe6d1/how-ios-sideloading-actually-works-in-2025-dev-certs-altstore-and-the-eu-exception-1m2h)
- [George Garside — Custom entitlements on sideloaded iOS apps](https://georgegarside.com/blog/ios/custom-entitlement-ios-app-ipa/)

### Tertiary (LOW confidence — needs device validation)
- [leminlimez GitHub gist — IOPMPowerSource battery temperature](https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc) — `Temperature` key and `systemgroup.com.apple.powerlog`; community, unverified against current iOS
- [MacRumors Forums — battery/device temperature no longer available](https://forums.macrumors.com/threads/battery-device-temperature-no-longer-available-to-apps.2399209/) — API availability changes discussion
- [Flutter issue #60406 — Sandbox deny iokit-get-properties](https://github.com/flutter/flutter/issues/60406) — MACF sandbox enforcement evidence

---
*Research completed: 2026-05-11*
*Ready for roadmap: yes*
