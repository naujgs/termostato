# Architecture Patterns

**Project:** Termostato
**Domain:** iOS device thermal monitoring (sideloaded)
**Researched:** 2026-05-11

---

## Recommended Architecture

A single-process, foreground-only app. No network layer, no persistence layer. All complexity lives in the sensor abstraction and the notification gate.

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                              │
│  DashboardView  ──►  SessionChartView  ──►  StatusBadgeView │
│        │                    │                               │
│        └────────────────────┘                               │
│                    reads via @Observable                     │
└───────────────────────────┬─────────────────────────────────┘
                            │ @State / binding
┌───────────────────────────▼─────────────────────────────────┐
│                   ThermalViewModel                           │
│  @Observable class — owns all mutable app state             │
│  • currentReading: ThermalReading                           │
│  • history: RingBuffer<ThermalReading>   (in-memory only)   │
│  • alertThreshold: Double (°C, user-configured)             │
│  • thermalState: ProcessInfo.ThermalState                   │
└─────────────┬────────────────────────┬──────────────────────┘
              │ async for await        │ calls
┌─────────────▼────────────┐  ┌────────▼───────────────────────┐
│   ThermalSensorService   │  │   NotificationGate             │
│   (polling layer)        │  │   (notification layer)         │
│                          │  │                                │
│  AsyncStream<ThermalReading> │  • fire(reading:threshold:)   │
│  • polls private API     │  │  • cooldown: 60 s min interval │
│    every N seconds       │  │  • lastFiredAt: Date?          │
│  • reads thermalState    │  │  UNUserNotificationCenter      │
│    via NotificationCenter│  └────────────────────────────────┘
│  • yields ThermalReading │
└──────────────────────────┘
              │ wraps
┌─────────────▼──────────────────────────────────────────────┐
│               Private API Bridge (C shim)                  │
│  ThermalBridge.h / ThermalBridge.m                         │
│  • IOServiceMatching("IOPMPowerSource")                     │
│  • IORegistryEntryCreateCFProperties → "Temperature" key   │
│  • divide raw value by 100 → °C Double                     │
│  • returns -1.0 on failure (graceful degradation)          │
└────────────────────────────────────────────────────────────┘
```

---

## Component Boundaries

| Component | Responsibility | Communicates With | Notes |
|-----------|---------------|-------------------|-------|
| `ThermalBridge` (C/ObjC) | Calls IOKit private API; returns raw battery temp | `ThermalSensorService` only | Isolated in its own file; single point of private API contact |
| `ThermalSensorService` | Wraps bridge in an `AsyncStream<ThermalReading>`; owns poll timer | `ThermalViewModel` | Pure Swift; bridge is injected so it can be mocked |
| `ThermalReading` | Value type — timestamp + temperature + thermalState | All layers | `struct`, `Sendable`; no logic |
| `RingBuffer<T>` | Fixed-capacity in-memory circular buffer; O(1) append | `ThermalViewModel` | Generic utility; history cap ~3 600 samples |
| `ThermalViewModel` | Single source of truth for UI state; drives notification gate | UI views, `NotificationGate` | `@Observable`; lives at app root |
| `NotificationGate` | Rate-limits and fires `UNUserNotificationCenter` alerts | `ThermalViewModel` | Stateful cooldown; no UI dependencies |
| `DashboardView` | Root view; large numeric readout + state badge | `ThermalViewModel` | SwiftUI; no business logic |
| `SessionChartView` | Scrolling history chart from `history` ring buffer | `ThermalViewModel` | Uses Swift Charts (iOS 16+) |
| `SettingsView` | Threshold picker, °C/°F toggle | `ThermalViewModel` | Sheet or navigation push from dashboard |

---

## Data Flow (temperature reading → UI → notification)

```
1. Poll tick (N-second interval, foreground only)
        │
        ▼
2. ThermalBridge.readTemperature()
   → IOKit call → raw Int ÷ 100 = Double °C
   → fallback: -1.0 if IOKit fails
        │
        ▼
3. ThermalSensorService.stream
   → packages into ThermalReading(date:, celsius:, thermalState:)
   → continuation.yield(reading)
        │
        ▼
4. ThermalViewModel (for await loop, @MainActor)
   → currentReading = reading
   → history.append(reading)       ← O(1) ring buffer write
   → NotificationGate.fire(reading, threshold: alertThreshold)
        │
        ▼ (SwiftUI observation, automatic)
5. DashboardView re-renders
   → SessionChartView re-renders (only history-dependent views)
        │
        ▼ (if threshold crossed AND cooldown elapsed)
6. NotificationGate schedules UNNotificationRequest
   → fires immediately (timeInterval: 1)
   → lastFiredAt = now
```

The `thermalState` is a secondary channel: iOS fires `ProcessInfo.thermalStateDidChangeNotification` asynchronously. `ThermalSensorService` observes this notification and merges updates into the same `ThermalReading` struct so the ViewModel has one unified type.

---

## Polling Strategy

**Decision: foreground timer via `AsyncStream` + `Task.sleep`. No background fetch.**

Rationale:

- This is a foreground dashboard app. The use case is "screen on, watching temperature." Background polling on iOS requires `BGProcessingTask` or `BGAppRefreshTask`, which iOS schedules at its discretion and provides at most ~30 seconds of runtime — unsuitable for continuous monitoring.
- `ProcessInfo.thermalStateDidChangeNotification` is reactive and free — it handles state-transition events without polling.
- The numeric temperature value requires polling because IOKit has no change-notification mechanism.
- `Timer.publish` (Combine) works but `Task.sleep` inside `AsyncStream` is the modern Swift Concurrency equivalent with cleaner cancellation.

**Recommended interval:** 2 seconds when app is active. No polling when app is backgrounded.

```swift
// ThermalSensorService (sketch)
func makeStream(interval: Duration = .seconds(2)) -> AsyncStream<ThermalReading> {
    AsyncStream { continuation in
        let task = Task {
            while !Task.isCancelled {
                let celsius = ThermalBridge.readTemperature()   // C shim call
                let state   = ProcessInfo.processInfo.thermalState
                continuation.yield(ThermalReading(celsius: celsius, thermalState: state))
                try? await Task.sleep(for: interval)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

**Background behavior:** When the app enters the background (`scenePhase == .background`), cancel the polling task. Resume when returning to foreground. This avoids using restricted background execution time and conserves battery.

```swift
// ThermalViewModel (sketch)
.onChange(of: scenePhase) { _, phase in
    if phase == .active  { startPolling() }
    if phase == .background { stopPolling() }
}
```

---

## State Management

**Decision: `@Observable` macro (iOS 17+), not `ObservableObject`.**

Rationale:

- `@Observable` (Swift Observation framework, iOS 17+) gives property-level granularity: only views reading `currentReading` re-render on each tick; `SessionChartView` only re-renders when `history` changes. With `ObservableObject` + `@Published`, every `@Published` change triggers a full object re-render.
- The project targets a personal device running current iOS — iOS 17 minimum is acceptable and avoids Combine boilerplate.
- No `@StateObject` / `@ObservedObject` split needed: pass the model as a plain parameter or via the environment.
- Swift Concurrency (`async/await`, `Task`, `AsyncStream`) integrates naturally without Combine pipelines.

**Ownership tree:**

```
@main App
  └── @State var thermalViewModel = ThermalViewModel()  ← owns the model
        └── passed via .environment(thermalViewModel)
              └── DashboardView reads currentReading, thermalState
              └── SessionChartView reads history
              └── SettingsView writes alertThreshold
```

---

## Local Notification Architecture

**Stack:** `UNUserNotificationCenter` only. No push/APNs. No background fetch.

**Threshold crossing:** On each reading, `ThermalViewModel` checks `reading.celsius >= alertThreshold`. This is a simple scalar comparison — no external framework needed.

**Debounce / cooldown strategy:**

The naive implementation fires a notification every 2 seconds once the threshold is crossed, spamming the user. The `NotificationGate` component prevents this:

```
NotificationGate state machine:
  IDLE  ──(threshold crossed)──►  FIRED
    ▲                                │
    └──(60 s elapsed OR drops below threshold)──┘

FIRED state: suppress all new notifications for 60 seconds minimum.
After 60 s: if still above threshold → re-fire once, stay FIRED.
            if below threshold → transition to IDLE.
```

Implementation: track `lastFiredAt: Date?`. Before firing, check `Date.now.timeIntervalSince(lastFiredAt) >= cooldownInterval` (default 60 s).

**Permission request:** Request notification permission on first launch (not on app start, which feels aggressive — defer to when the user first sets a threshold or explicitly taps an "Enable alerts" button).

---

## In-Memory Session History

**Decision: fixed-capacity ring buffer, no persistence.**

- Struct: `RingBuffer<ThermalReading>` with a capacity of 3 600 (2 s polling × 3 600 = 2 hours of data before oldest readings are overwritten).
- Storage: plain Swift array with a write cursor; O(1) appends.
- At 2 s intervals, 1 hour of readings ≈ 1 800 items × ~40 bytes per `ThermalReading` ≈ 72 KB. Negligible memory footprint.
- `SessionChartView` reads the buffer as an array slice for Swift Charts rendering. No additional data transformation layer needed.
- On app termination / background eviction, history is lost. This is intentional per project scope.

---

## Build Order

Build in this sequence. Each layer depends on the one below it.

```
1. ThermalReading (struct)
   Foundation: everything else uses this type.
   Build this first — it has zero dependencies.

2. RingBuffer<T> (generic struct)
   Zero dependencies; testable in isolation.

3. ThermalBridge (C/ObjC shim)
   The private API wrapper. Validate that IOKit calls return real
   data on the target device before building anything on top.
   This is the highest-risk component — surface failure early.

4. ThermalSensorService
   Wraps ThermalBridge in AsyncStream. Unit-testable by injecting
   a mock bridge that returns canned values.

5. NotificationGate
   Stateful cooldown + UNUserNotificationCenter wrapper.
   No UI dependencies; testable standalone.

6. ThermalViewModel (@Observable)
   Wires ThermalSensorService → RingBuffer + NotificationGate.
   SwiftUI previews become possible here.

7. DashboardView (numeric readout + state badge)
   First visual milestone. Proves the full data pipeline.

8. SessionChartView (Swift Charts history)
   Reads from ring buffer. Build after dashboard proves data flows.

9. SettingsView (threshold + unit toggle)
   Writes back to ViewModel. Last because it has no new dependencies.
```

**Rationale for this order:** Step 3 (ThermalBridge) is the only component that cannot be unit-tested without the physical device running the private API. Placing it at step 3 — before any UI work — ensures the app's core value (numeric temperature) is validated early. If IOKit returns no useful data on a given iOS version, the failure is discovered before investing time in UI polish.

---

## Critical Architecture Constraint: Private API Risk

**The IOKit "Temperature" key from `IOPMPowerSource` is the only known path to a numeric reading on non-jailbroken iOS.** Research found:

- The `IOPMCopyBatteryInfo` / `IORegistryEntryCreateCFProperties` + `"Temperature"` key approach is used in multiple open-source battery apps (BatteryStatusShow, ios-battery-stat, leminlimez gist).
- It requires no special entitlements for sideloaded apps (entitlements only matter for App Store submission review).
- The raw value is an integer that must be divided by 100 to get Celsius.
- Apple curtailed the detail in the `IOPMPowerSource` dictionary starting around iOS 10. The `Temperature` key may not be present on all devices/iOS versions.
- **Mitigation:** `ThermalBridge` must return a sentinel value (-1.0) and the UI must handle "temperature unavailable" gracefully. Fall back to displaying `ProcessInfo.thermalState` (4-level enum) which is always available.

`ProcessInfo.thermalState` + `thermalStateDidChangeNotification` (public API, iOS 11+) is the reliable fallback and should be treated as the primary data source for state-based alerting even if numeric readings work.

---

## Scalability Considerations

This app intentionally has no scalability requirements — it is a personal sideloaded tool. The following table exists only to confirm the architecture does not accidentally create constraints.

| Concern | At current scope | Notes |
|---------|-----------------|-------|
| Memory | ~72 KB for 2 hr history | Negligible; ring buffer caps growth |
| CPU | ~0.1% per 2 s poll | IOKit call is fast; no network |
| Battery | Moderate (polling + screen on) | App is only useful with screen on; accepted |
| Multiple devices | N/A (personal tool) | Not a concern |
| Persistence | None required | Intentional v1 scope decision |

---

## Sources

- [ProcessInfo.ThermalState — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum) — HIGH confidence
- [thermalStateDidChangeNotification — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification) — HIGH confidence
- [UNUserNotificationCenter — Apple Developer Documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) — HIGH confidence
- [Migrating from ObservableObject to @Observable — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro) — HIGH confidence
- [AsyncSequence for Real-Time APIs — Wesley Matlock, Medium](https://medium.com/@wesleymatlock/asyncsequence-for-real-time-apis-from-legacy-polling-to-swift-6-elegance-c2b8139c21e0) — MEDIUM confidence
- [iOS Background Execution Limits — AppsonAir](https://www.appsonair.com/blogs/background-execution-limits-in-ios-what-every-developer-must-know) — MEDIUM confidence
- [Get iOS Battery Info and Temperature gist — leminlimez](https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc) — LOW confidence (community gist, unverified against current iOS)
- [Battery/device temperature no longer available to apps — MacRumors Forums](https://forums.macrumors.com/threads/battery-device-temperature-no-longer-available-to-apps.2399209/) — LOW confidence (community discussion)
- [iOS cpu/gpu/battery temperature — Apple Developer Forums](https://developer.apple.com/forums/thread/696700) — MEDIUM confidence
