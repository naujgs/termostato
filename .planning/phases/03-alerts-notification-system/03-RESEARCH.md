# Phase 3: Alerts & Notification System - Research

**Researched:** 2026-05-12
**Domain:** iOS UserNotifications framework, Swift 6 concurrency, background thermalState observation
**Confidence:** HIGH (all core claims verified against official sources or Apple Developer Forums)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Notification title: `"iPhone Overheating"` — alert framing, not state name mirroring.
- **D-02:** Notification body: `"Thermal state: {level} — performance may be limited"` where `{level}` is Serious or Critical.
- **D-03:** Add a `"Dismiss"` action button via `UNNotificationCategory`. Tapping the notification body opens the app via standard iOS behavior.
- **D-04:** Cooldown is shared across foreground/background — one `lastAlertedState: ProcessInfo.ThermalState?` on `TemperatureViewModel`.
- **D-05:** Cooldown resets when thermal state drops below threshold (returns to Nominal or Fair). No time-based reset.
- **D-06:** Firing logic (both paths): `state >= Serious AND lastAlertedState == nil` → fire + set; `state >= Serious AND lastAlertedState != nil` → skip; `state < Serious` → clear `lastAlertedState`.
- **D-07:** Register `thermalStateDidChangeNotification` observer in `TemperatureViewModel.init()`, removed in `deinit`.
- **D-08:** Background path: observer fires → read `ProcessInfo.processInfo.thermalState` → apply D-06 gate → schedule `UNUserNotificationCenter` notification. Does NOT call `updateThermalState()`.
- **D-09:** Request notification permission in `TemperatureViewModel.startPolling()`.
- **D-10:** If permission denied, app continues to work; notification calls silently skipped.
- **D-11:** Show an inline banner below the thermal state badge when notification permission is denied. Contains a Settings deep-link.
- **D-12:** `notificationsAuthorized: Bool` property on `TemperatureViewModel` drives banner visibility.
- **D-13:** Banner persists until permission is granted (re-check in `startPolling()` each time the app foregrounds).

### Claude's Discretion

- Exact banner copy and visual styling — subtle, something like "Notifications disabled — tap to open Settings" with `.secondary` foreground and a chevron.
- `UNNotificationCategory` identifier string — pick a stable constant (e.g., `"thermalAlert"`).
- `UNUserNotificationCenter` delegate setup — if needed to handle foreground notification presentation, Claude decides.
- OSLog vs `print()` for background path logging — Claude picks based on Phase 2 pattern.

### Deferred Ideas (OUT OF SCOPE)

None.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ALRT-01 | App requests notification permission on first launch; graceful no-permission fallback | UNUserNotificationCenter.requestAuthorization async API; getNotificationSettings for re-check |
| ALRT-02 | Local notification fires when thermal state reaches Serious or Critical; cooldown prevents re-fire while elevated | UNMutableNotificationContent + UNNotificationRequest with nil trigger; state-based gate in updateThermalState() |
| ALRT-03 | Alerts fire via thermalStateDidChangeNotification so they work when app is backgrounded (not terminated) | NotificationCenter.default.addObserver in init(); @ObservationIgnored pattern for Swift 6 deinit safety |
</phase_requirements>

---

## Summary

Phase 3 wires the UserNotifications framework onto the existing `TemperatureViewModel` (`@Observable`, `@MainActor`). All three requirements are achievable with Apple's public `UserNotifications` framework — no private entitlements required. The stack is zero new dependencies.

The key technical complexity is Swift 6 strict concurrency with `@Observable @MainActor` classes. Two patterns require care: (1) registering a `NotificationCenter` observer in `init()` and removing it in `deinit` requires `@ObservationIgnored` on the stored token to suppress the concurrency checker [VERIFIED: Swift Forums thread 71225]; (2) conforming to `UNUserNotificationCenterDelegate` from a `@MainActor` class requires `nonisolated` on both delegate methods, with a `Task { @MainActor in }` wrapper when touching main-actor state [VERIFIED: Apple Developer Forums thread 762217].

The background delivery claim (`thermalStateDidChangeNotification` fires for backgrounded-but-not-terminated apps) is architecturally sound — the OS posts NSNotifications to apps in the Background execution state before they transition to Suspended — but the exact moment iOS suspends the process is non-deterministic. Physical-device testing with the Xcode debugger detached is essential.

**Primary recommendation:** Implement notification scheduling as an `async` method on `TemperatureViewModel`, called inside a `Task` from both the foreground (`updateThermalState()`) and background (observer closure) paths. Set up a `UNUserNotificationCenterDelegate` (via a small `NotificationDelegate: NSObject` helper or `AppDelegate`) for foreground notification presentation.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| UserNotifications | Built-in (iOS 10+) | Permission requests, scheduling local notifications, category/action registration | Official Apple framework; no SPM dependency; confirmed working in sideloaded free-account apps [VERIFIED: REQUIREMENTS.md, CLAUDE.md] |
| Foundation | Built-in | `ProcessInfo.thermalStateDidChangeNotification`, `NotificationCenter` observer registration | Already imported in TemperatureViewModel [VERIFIED: existing codebase] |
| UIKit (minimal) | Built-in | `UIApplication.openSettingsURLString` for Settings deep-link; opened via SwiftUI `@Environment(\.openURL)` | Settings URL constant is still the correct mechanism as of iOS 18 [VERIFIED: Apple Developer Forums thread 759900] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftUI `@Environment(\.openURL)` | Built-in | Open Settings URL from ContentView without touching UIApplication directly | In the permission-denied banner Button action |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `UNTimeIntervalNotificationTrigger(timeInterval:1, repeats:false)` | `nil` trigger | Both schedule an "immediate" notification. `nil` is cleaner for an event-driven alert; the 1-second trigger adds no value |
| Separate `NotificationDelegate: NSObject` | `TermostatoApp` as delegate | Dedicated helper keeps TermostatoApp clean; either works. Delegate is needed only for foreground presentation |
| `print()` | `OSLog` | `print()` is established in Phase 2 code; consistent, sufficient for personal sideloaded app |

**Installation:** No installation required — all frameworks are built-in.

---

## Architecture Patterns

### Recommended Project Structure

No new files are required. All changes are additive to existing files:

```
Termostato/Termostato/
├── TemperatureViewModel.swift   # + lastAlertedState, notificationsAuthorized,
│                                #   thermalStateDidChangeNotification observer,
│                                #   scheduleNotification(), requestPermission()
├── ContentView.swift            # + permission-denied banner View
├── TermostatoApp.swift          # + UNUserNotificationCenterDelegate setup
└── NotificationDelegate.swift  # NEW (optional): NSObject UNUserNotificationCenterDelegate
```

### Pattern 1: Swift 6 NotificationCenter Observer in @Observable @MainActor Class

**What:** Register a block-based observer in `init()`, store the opaque token as `@ObservationIgnored`, remove it in `deinit`.

**When to use:** Any `@Observable @MainActor` class that needs to observe `NotificationCenter` events.

**Why `@ObservationIgnored` is required:** The `@Observable` macro converts stored properties into computed properties for observation tracking. Without `@ObservationIgnored`, the concurrency checker flags `deinit` access as unsafe because `deinit` is implicitly `nonisolated`. [VERIFIED: Swift Forums thread 71225]

```swift
// Source: Swift Forums thread 71225 (confirmed pattern)
@Observable
@MainActor
final class TemperatureViewModel {

    @ObservationIgnored
    private var thermalObserver: (any NSObjectProtocol)?

    init() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // .main queue ensures @MainActor safety
            self?.handleBackgroundThermalChange()
        }
    }

    deinit {
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
```

**Key detail:** Passing `queue: .main` to `addObserver(forName:object:queue:)` ensures the closure executes on the main queue, satisfying `@MainActor` isolation without a nested `Task`. [ASSUMED — consistent with standard pattern; verify compiler accepts this without Task wrapper]

### Pattern 2: Async requestAuthorization in Swift 6

**What:** Use the `async throws` variant of `requestAuthorization`, not the completion-handler variant.

**Why:** The completion-handler variant crashes under Swift 6 strict concurrency. [VERIFIED: Apple Developer Forums thread 796407]

```swift
// Source: Apple Developer Forums thread 796407
func requestNotificationPermission() async {
    do {
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        notificationsAuthorized = granted
        if !granted {
            print("[Termostato] Notification permission denied.")
        }
    } catch {
        print("[Termostato] Notification auth error: \(error)")
        notificationsAuthorized = false
    }
}
```

Call site in `startPolling()`:
```swift
func startPolling() {
    timerCancellable?.cancel()
    timerCancellable = Timer.publish(every: 30, on: .main, in: .common)
        .autoconnect()
        .sink { [self] _ in self.updateThermalState() }
    updateThermalState()
    Task { await requestNotificationPermission() }
    Task { await refreshNotificationStatus() }
    print("[Termostato] Polling started.")
}
```

`refreshNotificationStatus()` calls `getNotificationSettings` to re-check authorization on each foreground (D-13):

```swift
func refreshNotificationStatus() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    notificationsAuthorized = (settings.authorizationStatus == .authorized)
}
```

### Pattern 3: Scheduling a Local Notification (Immediate, nil Trigger)

**What:** Schedule a fire-once local notification with `nil` trigger for immediate delivery.

```swift
// Source: Apple Developer Documentation (UNNotificationRequest)
func scheduleOverheatNotification(level: String) {
    let content = UNMutableNotificationContent()
    content.title = "iPhone Overheating"
    content.body = "Thermal state: \(level) — performance may be limited"
    content.sound = .default
    content.categoryIdentifier = "thermalAlert"

    let request = UNNotificationRequest(
        identifier: "thermalAlert",   // fixed ID so re-scheduling replaces the pending one
        content: content,
        trigger: nil                  // nil = deliver immediately
    )
    Task {
        try? await UNUserNotificationCenter.current().add(request)
    }
}
```

**Fixed identifier note:** Using a fixed identifier (`"thermalAlert"`) means that if the state escalates from Serious to Critical before the user dismisses the first notification, calling `.add(request)` with the same identifier replaces the pending notification rather than stacking a second one. This is useful behavior but the cooldown gate (D-06) already prevents re-firing while `lastAlertedState != nil`, so it is belt-and-suspenders rather than load-bearing.

### Pattern 4: UNNotificationCategory with Dismiss Action

**What:** Register a category with a destructive Dismiss action so iOS shows the button.

**When:** Must be registered before any notification is delivered — typically in `startPolling()` or `TemperatureViewModel.init()`.

```swift
// Source: [ASSUMED — standard UNNotificationCategory pattern]
func registerNotificationCategories() {
    let dismissAction = UNNotificationAction(
        identifier: "dismissAlert",
        title: "Dismiss",
        options: [.destructive]
    )
    let thermalCategory = UNNotificationCategory(
        identifier: "thermalAlert",
        actions: [dismissAction],
        intentIdentifiers: [],
        options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([thermalCategory])
}
```

### Pattern 5: UNUserNotificationCenterDelegate for Foreground Presentation

**What:** Without a delegate implementing `willPresent`, iOS silently drops notifications when the app is in the foreground.

**Swift 6 compliance:** Both delegate methods must be `nonisolated` when conforming from a `@MainActor`-isolated type. Use `Task { @MainActor in }` to hop back for state updates. [VERIFIED: Apple Developer Forums thread 762217]

```swift
// Source: Apple Developer Forums thread 762217
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + play sound even when app is foregrounded
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // "Dismiss" button: no action needed — system removes the notification
        completionHandler()
    }
}
```

Set `UNUserNotificationCenter.current().delegate = notificationDelegate` in `TermostatoApp` (stored as a `@State` to keep it alive) or in `TemperatureViewModel.init()`.

### Pattern 6: Settings Deep-Link Banner in SwiftUI

**What:** Show a tappable banner when `notificationsAuthorized == false`.

**Why `@Environment(\.openURL)` over `UIApplication.shared.open`:** Idiomatic SwiftUI, no UIKit import needed in a View.

```swift
// Source: [ASSUMED — standard SwiftUI openURL pattern]
// In ContentView.body, between badge and chart:
if !viewModel.notificationsAuthorized {
    @Environment(\.openURL) var openURL  // declared at View property level, not inline

    HStack {
        Image(systemName: "bell.slash")
        Text("Notifications disabled — tap to open Settings")
            .font(.footnote)
        Spacer()
        Image(systemName: "chevron.right")
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .onTapGesture {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
```

**Note:** `@Environment` properties must be declared at the View struct property level, not inside `body`. The snippet above is illustrative — the actual declaration lives outside `body`.

### Anti-Patterns to Avoid

- **completion-handler `requestAuthorization`:** Crashes under Swift 6 strict concurrency. Use the `async throws` variant.
- **Calling `updateThermalState()` from the background observer:** This appends to the ring buffer, corrupting session history with background-only events. The background path (D-08) only schedules a notification.
- **Storing observer token without `@ObservationIgnored`:** Triggers concurrency warnings in `deinit` under Swift 6 with `@Observable`. Use `@ObservationIgnored`.
- **No `UNUserNotificationCenterDelegate`:** Without a delegate, foreground notifications are silently swallowed. Set the delegate before the first notification fires.
- **`UIApplication.openURL(_:)` (deprecated):** Produces a console error on iOS 18. Use `UIApplication.shared.open(_:)` or SwiftUI `openURL` environment action.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Notification scheduling | Custom timer-based reminder system | `UNUserNotificationCenter` | OS delivers notifications even when app is backgrounded (background state); handles do-not-disturb, Focus modes, lock screen |
| Permission UI | Custom permission pre-prompt screen | Direct `requestAuthorization` call (D-09 decision) | Single-screen personal app; pre-prompt adds friction with no conversion benefit |
| Cooldown timer | `DispatchQueue.asyncAfter` or `Timer` | State-level gate (`lastAlertedState`) | Time-based cooldowns create edge cases on timer-cancel under suspension; state-based is more robust |
| Settings URL | Hard-coded string `"app-settings://"` | `UIApplication.openSettingsURLString` | System constant guaranteed by Apple; hard-coded scheme may change |

---

## Runtime State Inventory

> Phase 3 is additive only (no rename/refactor/migration). This section is included to confirm no runtime state migration is required.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — no CoreData, no UserDefaults, no persistent store | None |
| Live service config | None — sideloaded app, no APNs server, no external service | None |
| OS-registered state | None — no scheduled notifications exist yet (first launch of notifications feature) | None |
| Secrets/env vars | None | None |
| Build artifacts | None new | None |

---

## Common Pitfalls

### Pitfall 1: completion-handler requestAuthorization Crashes in Swift 6

**What goes wrong:** App crashes at runtime when `requestAuthorization(options:completionHandler:)` is called from a `@MainActor` context under Swift 6 strict concurrency.
**Why it happens:** The completion handler crosses actor isolation boundaries in a way Swift 6's concurrency checker rejects at runtime (not just compile time in some configurations).
**How to avoid:** Always use `try await UNUserNotificationCenter.current().requestAuthorization(options:)`.
**Warning signs:** Crash log referencing `_Concurrency` or `UNUserNotificationCenter`; only reproducible under Swift 6 language mode.
[VERIFIED: Apple Developer Forums thread 796407]

### Pitfall 2: Foreground Notifications Silently Dropped

**What goes wrong:** Notification fires (confirmed by `add(request)` succeeding) but the user sees nothing when the app is foregrounded.
**Why it happens:** iOS default behavior is to suppress notification UI when the app is in the foreground. A `UNUserNotificationCenterDelegate` must be set and `willPresent` must return presentation options.
**How to avoid:** Register the delegate before the first notification is scheduled. In `willPresent`, call `completionHandler([.banner, .sound])`.
**Warning signs:** No banner appears on device even though `add(request)` does not throw.
[VERIFIED: Apple Developer Documentation — UNUserNotificationCenterDelegate.willPresent]

### Pitfall 3: @Observable deinit Concurrency Error

**What goes wrong:** Swift 6 compiler flags `NotificationCenter.default.removeObserver(observer)` in `deinit` with a concurrency error, because `deinit` is `nonisolated` and the token property is a `@MainActor`-isolated computed property (due to the `@Observable` macro).
**How to avoid:** Mark the observer token property `@ObservationIgnored` to opt it out of observation tracking, restoring it to a plain stored property accessible in `deinit`.
**Warning signs:** Compile error: "Main actor-isolated property can not be referenced from a non-isolated synchronous context."
[VERIFIED: Swift Forums thread 71225]

### Pitfall 4: Background Notification Not Delivered — Debugger Attached

**What goes wrong:** `thermalStateDidChangeNotification` does not appear to fire when the app is backgrounded during testing.
**Why it happens:** When Xcode's debugger is attached, iOS does not suspend the app in the normal way — the app remains in an elevated execution state that can mask backgrounding behavior. The state-change notification may not be representative of real-world backgrounded behavior.
**How to avoid:** Test background notification delivery by disconnecting the USB cable (or using wireless debugging) and manually backgrounding the app. Only then trigger a thermal state change test (e.g., running a CPU-intensive task).
**Warning signs:** Background path "works" under debugger but fails in the field.
[ASSUMED — well-documented iOS developer knowledge; confirmed by STATE.md concern: "background notification delivery under free Apple ID must be tested by backgrounding the app with Xcode debugger detached"]

### Pitfall 5: thermalStateDidChangeNotification Does Not Fire for Terminated Apps

**What goes wrong:** Developer expects background alerting to work after the user force-quits the app.
**Why it happens:** `thermalStateDidChangeNotification` is delivered to apps in the Background execution state (process exists, not executing). A terminated process has no observer registered — it cannot receive any notification.
**How to avoid:** This is expected and acceptable per phase scope. ALRT-03 explicitly scopes to "not terminated." No mitigation needed; document in success criteria verification.
**Warning signs:** None — this is defined behavior, not a bug.
[VERIFIED: ALRT-03 requirement wording; Apple iOS lifecycle documentation]

### Pitfall 6: `UNUserNotificationCenter.delegate` Not Retained

**What goes wrong:** Delegate is set to a local variable that goes out of scope; subsequent notifications are not presented in the foreground.
**Why it happens:** `UNUserNotificationCenter.delegate` is a weak property. If the delegate object is not strongly retained elsewhere, it is deallocated.
**How to avoid:** Store the `NotificationDelegate` instance on a long-lived object (e.g., as a `@State` in `TermostatoApp`, or as a stored property on `TemperatureViewModel`).
**Warning signs:** `willPresent` called once, then never again.
[ASSUMED — standard UIKit/UserNotifications pattern; weak delegate is documented]

---

## Code Examples

### Full notification scheduling flow (combining patterns)

```swift
// In TemperatureViewModel — foreground path (called from updateThermalState)
private func checkAndFireNotification() {
    let state = thermalState
    let isElevated = (state == .serious || state == .critical)

    if isElevated {
        guard lastAlertedState == nil else { return }  // cooldown gate (D-06)
        lastAlertedState = state
        guard notificationsAuthorized else { return }
        let levelName = (state == .serious) ? "Serious" : "Critical"
        scheduleOverheatNotification(level: levelName)
    } else {
        lastAlertedState = nil  // cooldown reset (D-05)
    }
}

// Background path (called from thermalStateDidChangeNotification observer)
private func handleBackgroundThermalChange() {
    // Do NOT call updateThermalState() here (D-08)
    let state = ProcessInfo.processInfo.thermalState
    let isElevated = (state == .serious || state == .critical)

    if isElevated {
        guard lastAlertedState == nil else { return }
        lastAlertedState = state
        guard notificationsAuthorized else { return }
        let levelName = (state == .serious) ? "Serious" : "Critical"
        scheduleOverheatNotification(level: levelName)
    } else {
        lastAlertedState = nil
    }
}
```

### getNotificationSettings call (for refreshNotificationStatus)

```swift
// Source: [ASSUMED — standard UNUserNotificationCenter pattern]
func refreshNotificationStatus() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    notificationsAuthorized = (settings.authorizationStatus == .authorized)
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `requestAuthorization(options:completionHandler:)` | `try await requestAuthorization(options:)` | Swift 5.5 (async/await) | Completion-handler version crashes under Swift 6; always use async |
| `UIApplication.openURL(_:)` | `UIApplication.shared.open(_:)` or SwiftUI `openURL` | iOS 10 | deprecated; `open(_:)` is the correct API; on iOS 18, the old form logs an error |
| Manual `removeObserver` always required | Block-based observer tokens auto-removed when token is deallocated | iOS 9 | Still best practice to explicitly remove for clarity; `@ObservationIgnored` token in `deinit` is correct |
| `UNNotificationPresentationOptions.alert` | `.banner` | iOS 14 | `.alert` is deprecated; use `.banner` for visual presentation |

**Deprecated/outdated:**
- `.alert` presentation option: use `.banner` + `.list` (or just `.banner` for in-app banner only).
- Completion-handler `requestAuthorization`: never use under Swift 6.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `queue: .main` on `addObserver(forName:object:queue:)` satisfies `@MainActor` isolation without a Task wrapper | Pattern 1 | Compiler may reject or warn; fix: wrap closure body in `Task { @MainActor in }` |
| A2 | `NotificationDelegate` as `@State` in `TermostatoApp` keeps it alive (strong reference) | Pattern 5 | Delegate deallocated; foreground notification presentation stops. Fix: store on TemperatureViewModel instead |
| A3 | `UNNotificationAction` with `.destructive` option shows "Dismiss" button on lock screen and banner | Pattern 4 | Button may not appear on all iOS notification styles; non-blocking for MVP |
| A4 | `thermalStateDidChangeNotification` fires while app is in Background execution state (not terminated, not suspended yet) | Common Pitfalls / ALRT-03 | If iOS suspends the app before the thermal event fires, background alerting fails silently. Must verify on physical device with debugger detached |

---

## Open Questions

1. **Will thermalStateDidChangeNotification fire before iOS suspends the process?**
   - What we know: The notification is posted by the OS when thermal state changes. Background apps are in "Background execution state" for a finite time before suspension. The exact window is non-deterministic.
   - What's unclear: Whether the OS guarantees notification delivery during the background execution window, or whether the process may already be suspended when the thermal event fires.
   - Recommendation: Physical-device test is mandatory (STATE.md explicitly flags this). Success criterion 3 is the acceptance gate.

2. **Does Swift 6.3 compiler accept `queue: .main` as `@MainActor`-safe in the observer closure without an explicit Task?**
   - What we know: `queue: .main` routes the closure to the main queue. `@MainActor` operations are confined to the main actor, which runs on the main queue.
   - What's unclear: Whether the Swift 6.3 concurrency checker treats `queue: .main` as equivalent to `@MainActor` isolation for the purposes of accessing actor-isolated properties inside the closure.
   - Recommendation: If the compiler warns, add `Task { @MainActor in self?.handleBackgroundThermalChange() }` inside the closure. Both are valid; the Task form is always safe.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| UserNotifications framework | ALRT-01, ALRT-02, ALRT-03 | Built-in (iOS 10+) | iOS 18 target | No fallback needed |
| UNUserNotificationCenterDelegate | Foreground presentation | Built-in | iOS 10+ | Without it, foreground notifications are silently dropped |
| UIApplication.openSettingsURLString | D-11 banner | Built-in | iOS 8+ | No fallback needed |
| Swift async/await | requestAuthorization async | Swift 5.5+ | Swift 6.3 (Xcode 26.4.1) | No fallback — required by Swift 6 |

No missing dependencies. No blockers.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None detected (no test target in existing codebase) |
| Config file | None |
| Quick run command | Physical device install + manual verification |
| Full suite command | Physical device install + full success criteria walkthrough |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ALRT-01 | App requests permission on first launch; graceful denial | Manual (device) | — simulator cannot replicate permission state accurately | No test file |
| ALRT-02 | Notification fires at Serious/Critical; cooldown prevents re-fire | Manual (device) | — thermal state cannot be spoofed in simulator | No test file |
| ALRT-03 | Background thermalStateDidChangeNotification triggers notification | Manual (device, debugger detached) | — background execution cannot be reliably tested in simulator | No test file |

**Justification for manual-only:** All three requirements depend on physical device thermal state behavior and OS notification delivery timing that cannot be reproduced in the Xcode simulator. No simulator API exists to trigger `ProcessInfo.ThermalState.serious` or invoke `thermalStateDidChangeNotification`.

### Sampling Rate
- **Per task:** Build succeeds, no compiler errors or warnings, app launches on device.
- **Per wave merge:** Full ALRT-01/02/03 manual walkthrough on physical device.
- **Phase gate:** All four success criteria TRUE on physical device before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] No unit test infrastructure exists — manual device testing is the only validation path for this phase's requirements.

*(No automated test infrastructure is feasible for thermal state behavior. Manual device testing is the acceptance gate.)*

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | No | Notification content is constructed from `ProcessInfo.ThermalState` enum values only — no user input |
| V6 Cryptography | No | No secrets, no crypto |

**Assessment:** Phase 3 has no security surface. Notification content is derived from an OS enum, not from user input or external data. No network calls. No persistent storage. No authentication. ASVS categories are uniformly not applicable.

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Forums thread 796407 — Swift 6 `requestAuthorization` completion-handler crash; async alternative required
- Apple Developer Forums thread 762217 — `UNUserNotificationCenterDelegate` in `@MainActor` class; `nonisolated` delegate methods
- Swift Forums thread 71225 — `@Observable @MainActor` class + `NotificationCenter` observer; `@ObservationIgnored` pattern for `deinit`
- Apple Developer Documentation: `UNUserNotificationCenter` — `requestAuthorization(options:)`, `add(_:)`, `getNotificationSettings()`
- Apple Developer Documentation: `ProcessInfo.thermalStateDidChangeNotification` — notification name, posting conditions
- Apple Developer Forums thread 759900 — `UIApplication.openSettingsURLString` status in iOS 18 (still valid)
- `CLAUDE.md` (project) — UserNotifications as zero-dependency; BGAppRefreshTask exclusion; local notifications confirmed
- `03-CONTEXT.md` — all locked decisions D-01 through D-13
- Existing codebase (`TemperatureViewModel.swift`, `ContentView.swift`) — confirmed Phase 2 patterns

### Secondary (MEDIUM confidence)
- sarunw.com "Notification in foreground" — `willPresent` with `[.banner, .sound]` completion handler
- tanaschita.com "Quick guide on local notifications for iOS" — `UNTimeIntervalNotificationTrigger` nil trigger for immediate delivery

### Tertiary (LOW confidence)
- General iOS background execution documentation — behavior of `thermalStateDidChangeNotification` in Background vs. Suspended state (A4 assumption)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — UserNotifications is well-documented; no new dependencies
- Architecture patterns: HIGH — Swift 6 patterns verified against Apple Developer Forums threads
- Pitfalls: HIGH for Swift 6 concurrency issues (verified); MEDIUM for background delivery timing (device-dependent)

**Research date:** 2026-05-12
**Valid until:** 2026-06-12 (stable Apple APIs; Swift 6.3 concurrency model is settled)
