# Architecture Patterns

**Project:** Termostato
**Domain:** iOS device thermal monitoring (sideloaded)
**Researched:** 2026-05-13 (v1.1 update — supersedes 2026-05-11 pre-build version)

---

## Current Architecture (v1.0 Shipped)

The app is a single-file MVVM pipeline. No services layer, no dependency injection, no persistence.

```
TermostatoApp (@main)
  └── NotificationDelegate (@State, strong ref — prevents UNUserNotificationCenter weak-ref dealloc)
  └── ContentView
        └── TemperatureViewModel (@State, @Observable @MainActor)
              ├── thermalState: ProcessInfo.ThermalState          ← published read-only
              ├── history: [ThermalReading]                       ← 120-entry ring buffer
              ├── notificationsAuthorized: Bool                   ← drives permission banner
              ├── lastAlertedState: ProcessInfo.ThermalState?     ← cooldown gate
              ├── timerCancellable: AnyCancellable?               ← Timer.publish(every: 30)
              ├── thermalObserver: NSObjectProtocol?              ← background notification observer
              └── backgroundTaskID: UIBackgroundTaskIdentifier    ← ~30s background window
```

**Data flow (foreground):**
```
Timer.publish(every: 30) → updateThermalState()
  → ProcessInfo.processInfo.thermalState          (public API read)
  → ThermalReading(timestamp:, state:) appended to history[]
  → checkAndFireNotification()                    (cooldown gate → UNUserNotificationCenter)
  → @Observable mutation → SwiftUI auto-redraw
```

**Data flow (background):**
```
thermalStateDidChangeNotification → handleBackgroundThermalChange()
  → ProcessInfo.processInfo.thermalState          (fresh read, NOT self.thermalState)
  → checkAndFireNotification()                    (same cooldown gate)
  NOTE: does NOT append to history[] — deliberate; background changes corrupt session chart
```

---

## v1.1 Integration Points

### Feature 1: IOKit Numeric Temperature

**Where the call lives:** Inside `TemperatureViewModel.updateThermalState()`. No separate service layer is needed or beneficial at this app's scope. A service layer would add indirection without testability gain (IOKit requires physical device regardless).

**What changes in the ViewModel:**

1. Add `private(set) var numericTemperature: Double? = nil` — published property, `nil` when IOKit unavailable.
2. Inside `updateThermalState()`, after reading `thermalState`, call the IOKit C functions through the bridging header and assign the result to `numericTemperature`.
3. `ContentView` reads `viewModel.numericTemperature` and displays it alongside the badge. `nil` = show nothing or a dash.

**IOKit C API call from Swift under @MainActor / Swift 6 strict concurrency:**

The IOKit functions declared in `Termostato-Bridging-Header.h` are C functions. Calling C functions from Swift is always `nonisolated` from the Swift concurrency perspective — C has no actor concept. However, because `updateThermalState()` is already a `@MainActor` method on a `@MainActor`-isolated class, the C call executes on the main thread by inheritance. This is correct and safe:

- IOKit `IOServiceGetMatchingService` and `IORegistryEntryCreateCFProperties` are synchronous, blocking C calls. They complete in under 1ms on a physical device.
- Calling blocking C from `@MainActor` is acceptable for sub-millisecond calls (same pattern as `ProcessInfo.processInfo.thermalState` which is also synchronous).
- Do NOT wrap in `Task.detached` or `Task { @MainActor in }` — the C call is fast enough that offloading adds overhead with no benefit, and moving it off `@MainActor` would require a `Sendable` return type or `@unchecked Sendable` annotation.
- Swift 6 strict concurrency will not complain about the C call itself. The only concurrency boundary that matters is that `numericTemperature` (a `@Observable` stored property) is mutated on `@MainActor` — which is satisfied by the existing class annotation.

**IOKit property key for temperature:**

The bridging header already declares `IORegistryEntryCreateCFProperties`. The service to match is `"IOPMPowerSource"`. After obtaining the service and calling `IORegistryEntryCreateCFProperties`, cast the `CFMutableDictionaryRef` to `[String: Any]` and read the `"Temperature"` key. The raw value is an `Int` (or `CFNumber`); divide by 100 to get Celsius as a `Double`.

```swift
// Inside TemperatureViewModel.updateThermalState() — after the thermalState read
numericTemperature = readIOKitTemperature()

// New private helper — stays in TemperatureViewModel, no separate file needed
private func readIOKitTemperature() -> Double? {
    let service = IOServiceGetMatchingService(
        mach_port_t(0),                         // kIOMasterPortDefault = 0 on iOS
        IOServiceMatching("IOPMPowerSource")
    )
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    var props: Unmanaged<CFMutableDictionary>? = nil
    let kr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
    guard kr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
        return nil
    }

    // "Temperature" key — raw value is Int, unit is centidegrees Celsius (divide by 100)
    if let raw = dict["Temperature"] as? Int {
        return Double(raw) / 100.0
    }
    // Some iOS versions expose it as CFNumber directly
    if let raw = dict["Temperature"] as? Double {
        return raw / 100.0
    }
    return nil
}
```

**CFMutableDictionaryRef / Unmanaged memory management:** Use `takeRetainedValue()` (not `takeUnretainedValue()`) because `IORegistryEntryCreateCFProperties` transfers ownership to the caller (documented as "Create Rule"). Swift ARC then manages the lifetime. `defer { IOObjectRelease(service) }` handles the io_object_t release.

**Entitlement requirement:** TrollStore injects `com.apple.private.iokit.user-client-cross-endian` or the `systemgroup.com.apple.powerlog` entitlement at install time. The Swift/Objective-C code requires no explicit entitlement declaration in the Xcode project — TrollStore handles this at the IPA-signing layer. Standard Xcode sideloads will hit the AMFI block and `IOServiceGetMatchingService` will return 0 (the "null" io_object_t). The `guard service != 0` check handles this gracefully — `numericTemperature` stays `nil` and the UI shows nothing.

**Graceful degradation in ContentView:** The `numericTemperature: Double?` optional is the correct type. Display pattern:

```swift
if let celsius = viewModel.numericTemperature {
    Text(String(format: "%.1f°C", celsius))
} // else show nothing — no placeholder text needed; badge already conveys state
```

**New vs modified components:**

| Component | Change Type | What Changes |
|-----------|------------|--------------|
| `Termostato-Bridging-Header.h` | No change needed | All required C functions already declared |
| `TemperatureViewModel.swift` | Modified | Add `numericTemperature: Double?` property + `readIOKitTemperature()` helper + call in `updateThermalState()` |
| `ContentView.swift` | Modified | Add numeric temperature display (Text or label) below or inside the badge area |
| New service file | Not needed | ViewModel directly calls the C shim; no indirection layer warranted |

---

### Feature 2: App Icon

**Xcode asset catalog structure needed:**

The existing `Assets.xcassets/AppIcon.appiconset/Contents.json` uses the modern single-entry format (Xcode 14+):

```json
{
  "images": [
    {
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

This is correct and complete for iOS 16+. Xcode 26 generates all required sizes at build time from the single 1024x1024 source. No additional `Contents.json` entries are needed — the old approach of listing every `@1x`/`@2x`/`@3x` at every size (20pt, 29pt, 40pt, 60pt, 76pt, 83.5pt, 1024pt) is deprecated since Xcode 14.

**What is needed:** One 1024x1024 PNG (or SVG) placed in `AppIcon.appiconset/` and the filename registered in `Contents.json` under `"filename"`. Xcode will render all device sizes automatically.

**Swift code changes required:** None. App icon is purely an asset catalog configuration. No Swift file is touched.

**New vs modified components:**

| Component | Change Type | What Changes |
|-----------|------------|--------------|
| `Assets.xcassets/AppIcon.appiconset/` | Modified | Add icon image file; update `Contents.json` with `"filename"` key |
| All Swift files | No change | Zero Swift code involvement |

---

### Feature 3: 10-Second Polling Interval

**The one-line change:**

```swift
// TemperatureViewModel.swift, startPolling()
// Before:
timerCancellable = Timer.publish(every: 30, on: .main, in: .common)
// After:
timerCancellable = Timer.publish(every: 10, on: .main, in: .common)
```

**Ring buffer implications:**

The current ring buffer is `maxHistory = 120` entries. At 30s intervals: 120 × 30s = 3,600s = 60 minutes of history. At 10s intervals: 120 × 10s = 1,200s = 20 minutes of history.

The chart sub-label in `ContentView.swift` currently reads `"Session history (last 60 min)"` — this becomes inaccurate. Options:

**Option A (recommended):** Keep `maxHistory = 120`, update the label to `"Session history (last 20 min)"`. Simplest; no behavior change.

**Option B:** Increase `maxHistory` to 360 to preserve 60 minutes at 10s polling. Memory impact: 360 × ~64 bytes per `ThermalReading` ≈ 23 KB. Negligible. But the chart becomes denser (360 points vs 120). Swift Charts renders this fine — it is a line chart, not a scatter plot.

**Option C:** Make `maxHistory` computed from a target duration: `maxHistory = Int(targetDuration / pollingInterval)`. Cleaner but adds indirection for a personal tool.

Recommendation: Option A for v1.1 (minimal change surface). Option B is a one-line follow-up if 20 minutes of history feels too short in practice.

**Chart label location:** `ContentView.swift` line 113 — `Text("Session history (last 60 min)")`. Update to match actual window.

**No Swift 6 concurrency implications:** The polling interval change is a scalar literal. Timer.publish runs on `.main`, which satisfies `@MainActor`. No new actors, tasks, or async calls introduced.

**New vs modified components:**

| Component | Change Type | What Changes |
|-----------|------------|--------------|
| `TemperatureViewModel.swift` | Modified | `Timer.publish(every: 30)` → `Timer.publish(every: 10)` |
| `ContentView.swift` | Modified | Chart sub-label string update (Option A) |
| `TemperatureViewModel.swift` | Optionally modified | `maxHistory` increase (Option B only) |

---

## Swift 6 Concurrency Safety: IOKit C API Calls

This section directly addresses the concurrency concerns for IOKit.

**Summary: No Swift 6 concurrency issues arise from the IOKit call pattern described above.**

Detailed analysis:

1. **C functions have no actor affiliation.** `IOServiceGetMatchingService`, `IOServiceMatching`, `IORegistryEntryCreateCFProperties`, and `IOObjectRelease` are imported as global C functions. Swift treats them as `nonisolated` — they can be called from any isolation context without a `Sendable` requirement on their arguments.

2. **`CFMutableDictionaryRef` and `io_object_t` are not Swift types.** They do not participate in the Swift concurrency type-safety system. They are C/CoreFoundation opaque pointers. No `Sendable` conformance is required.

3. **The call site is `@MainActor`.** `readIOKitTemperature()` is called from `updateThermalState()`, which is called from the `Timer.publish` sink, which runs on `.main`. The method is on a `@MainActor`-isolated class. The C call inherits main actor isolation — it runs on the main thread. Swift 6 is satisfied: the mutation of `numericTemperature` (an `@Observable` stored property) happens on the actor that owns it.

4. **`Unmanaged<CFMutableDictionary>` does not escape.** `props` is a local variable consumed immediately with `takeRetainedValue()`. No cross-actor transfer occurs.

5. **`kCFAllocatorDefault` global constant.** This is a CoreFoundation global exported as a C `extern`. Swift 6 treats C globals as `nonisolated(unsafe)` when imported without `Sendable` annotations, but reading a well-known constant (not mutating) is safe in practice. The compiler may emit a warning; suppress with `nonisolated(unsafe) let alloc = kCFAllocatorDefault` if needed.

**Potential compiler warning (not an error):** Swift 6 may warn about passing `CFMutableDictionary` across isolation boundaries if the result is stored in a property that the compiler cannot prove is accessed only on `@MainActor`. Because `numericTemperature` is a property of the `@MainActor`-isolated `TemperatureViewModel`, and `readIOKitTemperature()` is called from a `@MainActor` method, no such crossing occurs. No `@unchecked Sendable` annotations should be needed.

---

## Build Order for v1.1

Features are independent — no dependency between them. Recommended order based on risk and effort:

```
1. 10s polling (TemperatureViewModel.swift — one line)
   → Lowest risk, proves the timer change does not break existing behavior.
   → Update chart label in ContentView.swift.
   → Can be verified in the simulator immediately.

2. App icon (Assets.xcassets only)
   → Zero code risk. Visual verification only.
   → Drop in 1024x1024 PNG, update Contents.json, build.

3. IOKit numeric temperature (TemperatureViewModel.swift + ContentView.swift)
   → Highest risk — requires physical device running TrollStore.
   → Implement readIOKitTemperature() with full nil-path handling first.
   → Test on standard sideload (will return nil — that is correct behavior).
   → Install via TrollStore to validate the non-nil path.
   → Add ContentView display only after ViewModel returns real data on device.
```

**Rationale:** IOKit is the only component that cannot be validated in the simulator or via standard sideload. Isolating it last means the other two changes are merged and working before introducing the device-specific dependency. If TrollStore access is unavailable, features 1 and 2 ship independently.

---

## Modified Component Summary

| File | Feature | Change Type | Lines Affected |
|------|---------|------------|---------------|
| `TemperatureViewModel.swift` | 10s polling | 1-line edit | `startPolling()` timer interval |
| `TemperatureViewModel.swift` | IOKit temp | Addition | New property + new private method (~25 lines) |
| `ContentView.swift` | 10s polling | 1-line edit | Chart sub-label string |
| `ContentView.swift` | IOKit temp | Addition | ~5–8 lines in badge area |
| `Assets.xcassets/AppIcon.appiconset/` | App icon | Asset + JSON edit | PNG + Contents.json filename key |
| `Termostato-Bridging-Header.h` | IOKit temp | No change | All needed declarations already present |
| `TermostatoApp.swift` | All features | No change | — |
| `NotificationDelegate.swift` | All features | No change | — |

No new files required for any of the three features.

---

## Sources

- `Termostato-Bridging-Header.h` (existing) — IOKit C declarations already in project; confirmed via file read 2026-05-13
- `TemperatureViewModel.swift` (existing) — full source read 2026-05-13; `Timer.publish(every: 30)` at line 111, `maxHistory = 120` at line 49
- `ContentView.swift` (existing) — chart sub-label at line 113
- `Assets.xcassets/AppIcon.appiconset/Contents.json` (existing) — single-entry modern format confirmed
- [IORegistryEntryCreateCFProperties — Apple Developer Documentation](https://developer.apple.com/documentation/kernel/1514293-ioregistryentrycreateproperties) — Create Rule (caller owns result), HIGH confidence
- [IOObjectRelease — Apple Developer Documentation](https://developer.apple.com/documentation/kernel/1514627-ioobjectrelease) — required after IOServiceGetMatchingService, HIGH confidence
- [Get iOS Battery Info and Temperature gist — leminlimez](https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc) — "Temperature" key, divide-by-100, `systemgroup.com.apple.powerlog` entitlement; MEDIUM confidence (community gist)
- [Configuring your app icon — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) — single 1024x1024 source in Xcode 14+; HIGH confidence
- Swift 6 Migration Guide (swift.org) — C function actor isolation rules; HIGH confidence
