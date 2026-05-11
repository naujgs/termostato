# Domain Pitfalls

**Domain:** iOS internal temperature monitoring app (sideloaded, private APIs)
**Researched:** 2026-05-11
**Confidence:** MEDIUM — core findings verified across multiple sources; some private API behavior is empirically observed rather than officially documented

---

## Critical Pitfalls

### Pitfall 1: The Numeric Temperature Doesn't Come From Where You Think

**What goes wrong:** The project assumes IOKit will provide a numeric temperature reading (°C). In practice, the path from "sideloaded app" to "actual number" is far more constrained than it appears at first glance.

**Why it happens:** There are three separate barriers, each capable of blocking numeric readings on its own:

1. **IOKit on iOS is not the same as IOKit on macOS.** Prior to iOS 16, IOKit was not in the iOS SDK at all. Starting with iOS 16, the framework is present but was added solely to support DriverKit extensions — not arbitrary registry browsing. The registry traversal that works freely on macOS is not freely available to third-party apps on iOS, even sideloaded ones.

2. **The sandbox enforces IOKit access at the kernel level regardless of installation method.** Sideloading bypasses App Store review; it does not bypass the MACF (Mandatory Access Control Framework) sandbox. A sideloaded app runs in the same sandbox as an App Store app. IOKit `iokit-get-properties` denials have been observed even on sideloaded apps without special entitlements. See the Flutter issue `#60406` where the sandbox deny `iokit-get-properties IONameMatched` appears even outside App Store context.

3. **The one working approach requires a private entitlement.** The only confirmed method for reading a numeric battery/thermal temperature is via `IOServiceMatching("IOPMPowerSource")` + `IORegistryEntryCreateCFProperties()`, accessing the `Temperature` key and dividing by 100. This requires the `systemgroup.com.apple.powerlog` entitlement. That entitlement is a system group entitlement — it cannot be self-assigned in a free developer provisioning profile and may not be grantable even in paid developer profiles without Apple approval.

**Consequences:** Phase 1 could be built entirely around a numeric readout that silently returns zero, crashes with a sandbox violation at launch, or requires an entitlement the signing infrastructure cannot deliver.

**Prevention:**
- In Phase 1, validate numeric temperature access *before* building any UI around it. Write a minimal test target — a single button that calls `IOServiceGetMatchingService` and logs the result — and run it on device under the intended signing configuration (free Apple ID).
- Have a clear fallback plan. If IOKit returns nothing, the display degrades to `ProcessInfo.thermalState` (4 levels) with a note that numeric °C requires a paid developer account or entitlement.
- If the project later upgrades to a paid developer account, research whether `systemgroup.com.apple.powerlog` can be added to a standard development provisioning profile, or whether it requires a managed capability request to Apple.

**Detection (warning signs):**
- App launches but temperature always shows 0.0 or nil
- Console shows `Sandbox: deny(1) iokit-get-properties`
- `IOServiceGetMatchingService` returns `IO_OBJECT_NULL`
- Crash on launch with `EXC_BAD_ACCESS` when traversing IO registry

**Phase that must address this:** Phase 1 (foundation / private API integration) — this is the single highest-risk item in the project.

---

### Pitfall 2: Free Developer Cert Expiry Breaks the App Silently Mid-Session

**What goes wrong:** Apps signed with a free Apple ID expire after exactly 7 days. When the certificate expires, the app does not degrade gracefully — it simply refuses to launch with "App cannot be opened because the developer cannot be verified." The app icon remains on the home screen. Nothing in the running app warns the user that expiry is approaching.

**Why it happens:** The 7-day limit is a provisioning profile constraint, not a certificate expiry in the traditional sense. The profile expires and iOS enforces it at launch time, not at install time. Xcode must be connected over USB and the app re-installed to extend the window.

**Additional free account constraints relevant to this project:**
- Maximum 3 sideloaded apps on device at one time (across all Xcode-installed apps, not just this project)
- Cannot enable push notification entitlement (`aps-environment`) in a free developer provisioning profile. This means **APNs remote push cannot be used for temperature alerts.** Local notifications do work — they require no special entitlement.
- Background modes that require special entitlements (e.g., `audio`, `location`, `voip`) are likely unavailable. The `background-fetch` mode may function on a free account but is not guaranteed to be enrollable.

**Consequences:** The alert system must be designed around local notifications from the outset, not remote push. If the initial design assumes APNs, it must be rearchitected when signing realities become clear. The 7-day expiry also makes persistent history features (if added later) unreliable unless the user actively maintains their install.

**Prevention:**
- Design the notification system around `UNUserNotificationCenter` local notifications from day one. Never assume APNs is available.
- Add a visible "cert expires in N days" indicator to the app UI, computed from build date or a hardcoded constant. Proactively warn at day 5.
- Document the re-install procedure in a project note so it takes under 2 minutes.
- Track the 3-app limit: if other development apps are on the device, Termostato may fail to install without first removing another app.

**Detection (warning signs):**
- "App cannot be opened because the developer cannot be verified" on launch
- Xcode shows "Failed to register bundle identifier" during install
- `codesign -dv --verbose=4 <AppName.app>` shows expired profile date

**Phase that must address this:** Phase 1 (project setup / signing configuration) — establish the local notification path before building alert logic.

---

## Moderate Pitfalls

### Pitfall 3: Timers and Polling Stop When App Enters Background

**What goes wrong:** A `Timer` or `Task { while true { sleep(1) } }` that drives the temperature polling loop pauses or stops entirely when the user leaves the app. iOS suspends the app within seconds of backgrounding. The polling loop does not resume until the app returns to foreground. Any threshold-crossing that happens while suspended triggers no notification.

**Why it happens:** iOS freezes app execution on background entry. `Timer` callbacks are based on the run loop, which stops when the app suspends. Swift `Task` continuations behave similarly — a `try await Task.sleep(for:)` inside a background-moved task does not fire.

**What actually works for keeping a polling loop alive:**
- `UIApplication.beginBackgroundTask(expirationHandler:)` grants approximately 30 seconds of extra CPU time after backgrounding, with a watchdog kill at expiry (exception code `0x8badf00d`). This is enough to finish a current operation but not to run a continuous loop.
- `BGAppRefreshTask` (BGTaskScheduler) schedules opportunistic background wakeups — but iOS decides *when*, not the app. These fire at most a few times per day and have no sub-minute granularity. Useless for temperature threshold detection.
- `ProcessInfo.thermalState` observation via `NSNotification` (`thermalStateDidChangeNotification`) **does** fire in the background. This can trigger a local notification when thermal state crosses a threshold — without a polling loop. This is the correct architecture for background alerting.

**Consequences:** A polling-based alert design fails silently when backgrounded. The user sees no notification because the timer never fired. This is particularly deceptive in testing — Xcode attached to a device suppresses suspension, making background behavior seem to work fine.

**Prevention:**
- Separate concerns: the live numeric readout (foreground-only) and the threshold alert system (event-driven, background-capable).
- Use `thermalStateDidChangeNotification` as the trigger for local notifications. This eliminates background polling entirely.
- If numeric temperature (not just thermal state) must drive alerts, accept that alerts only fire while the app is in the foreground and communicate this constraint to the user clearly in UI copy.
- **Never test background behavior from Xcode.** Xcode's debugger disables the watchdog and prevents app suspension. Always test by launching from the home screen after install.

**Detection (warning signs):**
- Notifications fire correctly during testing but not in real use
- Profiling shows timer firing stops 5-10 seconds after home button press
- Background task expiration handler fires repeatedly (means polling loop leaked a task)

**Phase that must address this:** Phase 2 (alert/notification system) — the architecture decision between polling and event-driven notification must be made before writing alert logic.

---

### Pitfall 4: Swift Charts LineMark Degrades Under Rapid Unbounded Data Accumulation

**What goes wrong:** The session-length history chart accumulates one data point per polling interval. At 1 Hz, that is 3,600 points per hour, 86,400 in a day. Swift Charts' `LineMark` re-renders the entire dataset on each `@Published` update. Around 400-1,000 points, frame renders begin to take longer than 16ms. Past 3,600 points, the UI becomes measurably sluggish on an older device. Past 20,000 points, the chart becomes barely interactive.

**Why it happens:** Swift Charts does not virtualize or downsample data. Every `LineMark` call processes the full data array. When the array is mutated and the containing `@Observable` / `ObservableObject` publishes, SwiftUI redraws the entire chart view. Combining 1 Hz writes with a growing array means O(n) render time per second.

**Additional contributing factor:** `@Published` property updates must occur on the main thread. If the polling happens on a background actor (correctly) but the array update is dispatched to main with `DispatchQueue.main.async`, SwiftUI sees the update, diffs the view tree, and redraws the chart — all on the main thread, every second.

**Consequences:** The chart slows down over a long session. The numeric readout, which shares the main thread, may also stutter. On an older device (iPhone XS era), this could become noticeable within 30 minutes.

**Prevention:**
- Cap the chart data array at a fixed window (e.g., the last 300 or 600 points — 5 to 10 minutes). Older points are dropped. Total rendering cost stays constant over session length.
- If a longer history view is required, downsample: store full-resolution data in an array but pass a decimated copy to the chart (every Nth point, or a sliding average).
- Isolate the chart update from the numeric readout update. If the numeric display refreshes at 1 Hz but the chart only refreshes at 0.2 Hz (every 5 seconds), the main thread render load drops by 80%.
- Use `.animation(.none)` on the chart or its enclosing view during data appends to avoid the overhead of the default implicit animation recalculating on each update.

**Detection (warning signs):**
- Instruments "Core Animation" template shows frame time > 16ms during chart updates
- CPU usage climbs steadily over session length
- Scrolling the chart view becomes noticeably less smooth after 10+ minutes

**Phase that must address this:** Phase 1 (dashboard UI implementation) — the data model must be designed with a capacity cap before the chart is wired up.

---

### Pitfall 5: Local Notification Permission Denial is Permanent From the App's Perspective

**What goes wrong:** The first time the app calls `requestAuthorization(options:)`, iOS shows the system permission dialog. If the user taps "Don't Allow," the app is permanently denied — calling `requestAuthorization` again returns `.denied` instantly without showing the dialog again. The only recovery path is the user manually going to Settings > Notifications > Termostato.

**Why it happens:** iOS deliberately prevents apps from pestering users with repeated permission prompts. Once denied, the OS caches the decision.

**Consequences:** If the permission prompt appears at the wrong moment (immediately on first launch, before the user understands why the app wants notifications), denial rates are high. A denied user gets no overheating alerts and may not realize why.

**Prevention:**
- Gate the permission request behind a user action. Show an in-app explanation screen first: "Termostato will notify you when the device exceeds your threshold. Allow notifications?" Then request permission only after the user taps "Enable Alerts."
- Handle the `.denied` case explicitly: show an inline banner in the UI that says "Notifications are disabled — tap to open Settings" and link to `UIApplication.openSettingsURLString`.
- Do not request notification permission at app launch. Defer it until the user first configures a threshold.

**Detection (warning signs):**
- Alerts never fire even when threshold is crossed in foreground
- `UNUserNotificationCenter.current().getNotificationSettings()` returns `.denied`
- No entry for app in Settings > Notifications

**Phase that must address this:** Phase 2 (notification / alert setup) — permission flow must be designed before the alert UI is built.

---

### Pitfall 6: `@Published` Updates From Background Thread Cause Runtime Crashes

**What goes wrong:** The temperature polling runs on a background thread or actor for correctness. When the poll result updates an `@Published` or `@Observable` property, SwiftUI requires that update to happen on the main thread. Updating from a background context triggers a purple runtime warning in debug builds and can cause subtle rendering corruption or crashes in release builds.

**Why it happens:** SwiftUI's rendering pipeline is not thread-safe. `ObservableObject` sends `objectWillChange` from whichever thread the mutation occurs on. If that is not the main thread, the view update is queued on the wrong thread.

**Consequences:** App appears to work correctly in Xcode debug (debugger suppresses some thread violations) but intermittently corrupts state or crashes in regular use.

**Prevention:**
- Annotate the view model with `@MainActor`. This makes all property mutations automatically dispatch to the main thread.
- If using Swift Concurrency, structure the polling as a `Task` that does work on a background executor, then uses `await MainActor.run { }` for the UI update.
- Add a `dispatchPrecondition(condition: .onQueue(.main))` assertion in the property setter during development to catch violations early.

**Detection (warning signs):**
- Purple "Publishing changes from background threads is not allowed" runtime warnings in Xcode console
- Intermittent UI freezes or inconsistent state
- Instruments Thread Sanitizer reports races on the view model properties

**Phase that must address this:** Phase 1 (data model and polling architecture).

---

## Minor Pitfalls

### Pitfall 7: Notification Flood When Threshold Is Crossed Repeatedly

**What goes wrong:** The threshold check fires every polling interval. If the device temperature oscillates around the threshold (crosses it, drops below, crosses again), the app fires a notification on every positive crossing. Within a few minutes, the user's notification center is filled with "Device overheating" alerts. iOS does not rate-limit local notifications from a single app — it will deliver all of them.

**Prevention:**
- Implement a cooldown: once a notification fires, suppress further notifications for at least 60 seconds (or until temperature drops below threshold by a hysteresis margin, e.g., 3°C below the trigger point).
- Use a single persistent `UNNotificationRequest` with a fixed identifier and call `add()` again — iOS will replace the existing pending notification rather than adding a second one.

**Phase that must address this:** Phase 2 (alert logic).

---

### Pitfall 8: dyld Shared Cache Extraction Produces Stale Headers

**What goes wrong:** When using `class-dump` or `ipsw` to extract private framework headers from the dyld shared cache, the extracted headers reflect the iOS version of the firmware image used — not the iOS version on the target device. Symbols and class interfaces may differ between iOS 16, 17, and 18 builds of the same framework.

**Why it happens:** Apple ships a new dyld shared cache with each iOS release. Private API signatures, class hierarchies, and selector names change silently between OS versions. There is no documentation of these changes.

**Consequences:** Code that compiles cleanly against headers from an iOS 16 cache may crash at runtime on iOS 17 if a method signature changed or a class was removed.

**Prevention:**
- Extract headers from firmware matching the exact iOS version on the target device. Use `ipsw` (github.com/blacktop/ipsw) to download and extract OTA images for the specific device/iOS combination.
- Pin the target device to a specific iOS version for development. Do not upgrade the test device OS mid-development without re-validating the private API surface.
- Wrap all private API calls in `responds(to:)` checks and provide graceful fallbacks. If the selector does not exist at runtime, fall back to `ProcessInfo.thermalState`.

**Phase that must address this:** Phase 1 (private API research / integration).

---

### Pitfall 9: `ProcessInfo.thermalState` Notification Is Coarse and Delayed

**What goes wrong:** `thermalStateDidChangeNotification` fires when iOS internally transitions the device between thermal states (nominal → fair → serious → critical). These transitions are not instantaneous — iOS applies hysteresis and debouncing before changing state. A device can be at an actual high temperature for several minutes before the state transitions to `.serious`. If the alert strategy relies on this notification, users may not be warned until the device is already very hot.

**Prevention:**
- If numeric temperature is available (IOKit path succeeds), use it for threshold alerts for responsiveness.
- If only `thermalState` is available, set the alert threshold to `.fair` (not `.serious` or `.critical`) to fire earlier in the thermal escalation curve.
- Communicate to the user that the notification represents "thermal state escalated," not "temperature just crossed X°C."

**Phase that must address this:** Phase 2 (alert configuration UI).

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|---|---|---|
| Phase 1: Private API numeric temperature | IOKit sandbox denial; entitlement blocker | Validate on device with actual signing config before building UI |
| Phase 1: Data model architecture | Unbounded array growth kills chart perf | Design with fixed-capacity circular buffer from day one |
| Phase 1: Polling loop | Background suspension stops timer | Use foreground-only timer; separate event-driven notification path |
| Phase 1: Thread model | `@Published` from background thread crashes | Annotate view model `@MainActor` before wiring up polling |
| Phase 2: Notification permission | Permanent denial on first ask | Gate request behind user intent; handle denied state in UI |
| Phase 2: Alert logic | Notification flood at threshold boundary | Implement cooldown + hysteresis before shipping |
| Phase 2: Background alerting | Polling-based alerts don't fire when backgrounded | Use `thermalStateDidChangeNotification` for background path |
| Any phase: OS version mismatch | Private API headers from wrong iOS version | Extract dyld cache from exact device firmware |

---

## Sources

- Apple Developer Forums — IOKit on iOS: https://developer.apple.com/forums/thread/734866
- Apple Developer Forums — Battery temperature / IOPMPowerSource: https://developer.apple.com/forums/thread/696700
- GitHub gist — IOPMPowerSource battery temperature + `systemgroup.com.apple.powerlog` entitlement: https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc
- MacRumors — battery/device temperature no longer available: https://forums.macrumors.com/threads/battery-device-temperature-no-longer-available-to-apps.2399209/
- Flutter issue #60406 — Sandbox deny iokit-get-properties: https://github.com/flutter/flutter/issues/60406
- Apple Developer Forums — iOS background execution limits: https://developer.apple.com/forums/thread/685525
- Embrace.io — iOS Watchdog Terminations from Background Tasks: https://embrace.io/blog/ios-watchdog-terminations/
- Apple Developer Forums — Swift Charts real-time LineMark performance: https://developer.apple.com/forums/thread/728636
- Apple Developer Forums — Swift Charts large dataset performance: https://developer.apple.com/forums/thread/740314
- Swift Forums — Updating SwiftUI many times per second: https://forums.swift.org/t/how-to-update-swiftui-many-times-a-second-while-being-performant/71249
- George Garside — Custom entitlements on sideloaded iOS apps: https://georgegarside.com/blog/ios/custom-entitlement-ios-app-ipa/
- Dev.to — iOS sideloading mechanics 2025: https://dev.to/1_king_0b1e1f8bfe6d1/how-ios-sideloading-actually-works-in-2025-dev-certs-altstore-and-the-eu-exception-1m2h
- Apple Developer Documentation — UNUserNotificationCenter requestAuthorization: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)
- blacktop/ipsw — iOS firmware research toolkit: https://github.com/blacktop/ipsw
- NowSecure — Reversing iOS System Libraries via dyld cache: https://www.nowsecure.com/blog/2024/09/11/reversing-ios-system-libraries-using-radare2-a-deep-dive-into-dyld-cache-part-1/
