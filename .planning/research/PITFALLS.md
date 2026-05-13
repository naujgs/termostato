# Domain Pitfalls — v1.1 Visual Improvements

**Domain:** iOS internal temperature monitoring app (sideloaded, private APIs)
**Researched:** 2026-05-13
**Milestone:** v1.1 — app icon, TrollStore IOKit numeric temperature, 10s polling
**Confidence:** HIGH for TrollStore version constraints (official repo confirms); HIGH for app icon behavior (official Apple docs + Xcode 14+ release notes); MEDIUM for polling / ring buffer impact (codebase analysis + Apple Energy Guide)

> This file extends the original PITFALLS.md written for v1.0. It focuses exclusively on pitfalls
> introduced by the three v1.1 features: TrollStore IOKit access, custom app icon, and 10s polling.
> v1.0 pitfalls (Pitfalls 1-9 in the original file) remain valid and are not repeated here.

---

## Critical Pitfalls

### Pitfall A: TrollStore Hard-Caps at iOS 17.0 — Target Device Running iOS 18 Cannot Use This Feature

**What goes wrong:** The plan adds IOKit numeric temperature via TrollStore. TrollStore supports iOS 14.0 beta 2 through 16.6.1, iOS 16.7 RC (20H18), and iOS 17.0. It does not support iOS 17.0.1 or any later version, including all of iOS 18. Apple patched the CoreTrust bug (CVE-2023-41991) in iOS 17.0.1, and the TrollStore project has officially stated that iOS 17.0.1+ will never be supported unless a new CoreTrust bug is discovered.

**Why it happens:** TrollStore works by exploiting a CoreTrust signature validation bug that allows apps with arbitrary entitlements to be installed permanently without App Store review. That bug was patched by Apple and the fix is present in every iOS version after 17.0.

**Consequences:** The project's current context states the target device runs iOS 18.x (PROJECT.md: "Target device: iPhone (any model running iOS 18+)"). TrollStore cannot be installed on iOS 18. The numeric temperature feature as planned is not achievable on the intended target device.

**Additional constraint:** Even on a device where TrollStore can be installed (iOS 17.0 or earlier), TrollStore must be installed on the device *before* the Termostato IPA is installed through it. TrollStore is a device-side tool — it cannot be applied from Xcode on the dev machine. The workflow is: install TrollStore on device → build a signed IPA with the required entitlement → install IPA via TrollStore on device. This is a different install flow than the current Xcode USB sideload path.

**Prevention:**

1. Verify the exact iOS version on the target device before planning any work around TrollStore. If it is iOS 17.0.1 or higher, TrollStore is unavailable and the numeric temperature feature must be deferred or redesigned.
2. If the device is on a compatible version (17.0 or lower), plan explicitly for the two-install-path problem: the development install path (Xcode USB) is incompatible with the TrollStore install path. Maintaining both paths simultaneously is complex.
3. Treat the numeric temperature feature as an optional enhancement guarded by a runtime check: if the IOKit call returns nil or fails, the UI falls back to the thermal state display already shipping in v1.0.

**Detection (warning signs):**
- TrollStore installation instructions fail with device iOS version
- TrollStore releases page shows your device iOS version is not listed
- App installed via TrollStore crashes at launch (entitlement banned on A12+ — see Pitfall B)

**Phase that must address this:** Whichever phase adds numeric temperature — this is the first thing to validate, before any IOKit code is written. Concrete check: confirm device iOS version, check TrollStore's supported list.

---

### Pitfall B: Entitlement Injection — `systemgroup.com.apple.powerlog` Must Be in the Entitlements File, Not Just the Info.plist

**What goes wrong:** The IOKit temperature path requires the `systemgroup.com.apple.powerlog` entitlement. Developers sometimes confuse entitlements with Info.plist entries or provisioning profile capabilities. The entitlement must be present in the app's `.entitlements` file at build time and must be preserved by TrollStore during installation.

**Why it happens:** TrollStore preserves entitlements that are embedded in the IPA at build time. But if the entitlement is not in the Xcode `.entitlements` file, it will not be embedded in the binary, and TrollStore cannot inject it after the fact. The build must include it explicitly.

**Mechanics:**
- In Xcode: add an `.entitlements` file to the target (Signing & Capabilities → All → + Capability is not enough for private entitlements; you must manually edit the `.entitlements` plist).
- Set the key `systemgroup.com.apple.powerlog` with value `true` (Boolean).
- When building for TrollStore distribution, build as unsigned or with a development cert; TrollStore replaces the signature during install and preserves the entitlement.
- Note: if using standard Xcode code signing, Xcode may strip or reject unrecognized entitlements during signing. Building an unsigned IPA (or using the `ldid` tool to sign with entitlements directly) is the standard TrollStore developer workflow.

**Additional banned entitlements on A12+ (iOS 15+):** Three entitlements are completely banned and cause crash on launch:
- `com.apple.private.cs.debugger`
- `dynamic-codesigning`
- `com.apple.private.skip-library-validation`

These are not needed for temperature access, but adding them accidentally (e.g., copying an entitlements file from another project) causes an immediate crash on A12+ devices.

**Prevention:**
- Keep the entitlements file minimal: only `systemgroup.com.apple.powerlog`. Do not add speculative entitlements.
- Build the IPA through the TrollStore-compatible workflow (unsigned or ldid-signed with entitlements) rather than a standard Xcode archive, which will sign out the private entitlement.
- Test on device immediately after TrollStore install with a minimal IOKit probe before adding any UI.

**Detection (warning signs):**
- `IOServiceGetMatchingService` returns `IO_OBJECT_NULL` (entitlement missing or not preserved)
- App crashes on launch with no console output (banned entitlement present)
- Console shows `AMFI: Entitlement com.apple.private.powerlog.battery is not allowed`
- Xcode archive warns or strips the entitlement during signing

**Phase that must address this:** Numeric temperature phase, step 1 — before any other code is written.

---

### Pitfall C: IOKit Call Returns Nil or Zero Without Error — Silent Failure Path Must Be Handled

**What goes wrong:** When the `systemgroup.com.apple.powerlog` entitlement is missing or the service is unavailable, `IOServiceGetMatchingService("IOPMPowerSource")` returns `IO_OBJECT_NULL` (a C constant representing 0). Code that does not check for this will either crash when passing `IO_OBJECT_NULL` to subsequent IOKit calls, or return a dictionary with no `Temperature` key, producing a silent zero value displayed as "0.0°C" in the UI.

**The specific failure chain:**
1. `IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPMPowerSource"))` → returns 0 if sandbox denies or entitlement absent
2. Passing 0 to `IORegistryEntryCreateCFProperties` → undefined behavior; may crash, may return empty dict
3. If dict is returned, `dict["Temperature"]` → nil
4. Dividing nil by 100 → crash in non-optional Swift, or silent zero in optional Swift
5. UI displays "0.0°C" with no indication that the reading is invalid

**Why it happens:** IOKit is a C framework. Its error returns are C conventions (IO_OBJECT_NULL, kern_return_t codes). Swift does not automatically bridge these to thrown errors or optionals. Callers must implement the checks explicitly.

**Prevention:**

```swift
// Correct defensive pattern
func readBatteryTemperature() -> Double? {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPMPowerSource")
    )
    guard service != IO_OBJECT_NULL else {
        // Entitlement missing or service unavailable — expected on iOS 18 / non-TrollStore path
        return nil
    }
    defer { IOObjectRelease(service) }

    var props: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
    guard result == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
        return nil
    }
    guard let rawTemp = dict["Temperature"] as? Int else {
        // Key absent — entitlement present but key not available on this device/iOS version
        return nil
    }
    return Double(rawTemp) / 100.0
}
```

- Always `IOObjectRelease` the service handle. Leaking it causes resource exhaustion over repeated calls.
- Display nil as "--" or "N/A" in the UI, never as "0.0°C".
- Log the failure reason so it is diagnosable without Xcode attached.

**Detection (warning signs):**
- Temperature always reads 0.0°C despite device being warm
- No console error from the IOKit call (silent C return code failure)
- `IOObjectRelease` is missing → memory/handle leak visible in Instruments Allocations

**Phase that must address this:** Numeric temperature phase — the nil handling and fallback display must be designed at the data model level, not patched in the view layer.

---

## Moderate Pitfalls

### Pitfall D: App Icon — Xcode Single-Image Mode vs. All-Sizes Mode Mismatch

**What goes wrong:** Xcode 14+ introduced a "Single Size" app icon mode where one 1024x1024 image auto-generates all required sizes. However, if an existing project was created before Xcode 14, or was manually configured with "All Sizes" mode, switching to a new icon requires either replacing files in the correct mode or the asset catalog ends up with mixed content — some slots filled from the old icon, some from the new — producing the old icon on certain screen sizes and the new icon on others.

**Why it happens:** The `AppIcon.appiconset/Contents.json` file maps each size slot to a filename. If you drag a new image into the catalog root without understanding the current mode, Xcode may: (a) ignore it, (b) place it in only one slot, or (c) create a new unnamed icon set that the build target does not reference.

**The correct approach for Xcode 14+ (Single-Image mode):**
1. In the asset catalog, select the AppIcon set.
2. In the Attributes Inspector (right panel), confirm "iOS" is the platform and the single-image slot is shown.
3. Drag a 1024x1024 PNG into the single slot. No transparency. No rounded corners. PNG format.
4. Xcode generates all sizes at build time.

**Common mistakes:**
- Dragging the icon file into the Finder folder for the asset catalog instead of into Xcode's asset catalog editor — the `Contents.json` is not updated, so the image is never referenced.
- Using a JPEG or HEIC instead of PNG — Xcode may accept it but produce incorrect output on older iOS.
- Including an alpha channel in the iOS icon — iOS rejects icons with transparency. The simulator may show them; device install may fail or show a black box.
- Designing with pre-applied rounded corners — iOS applies a squircle mask at the OS level; a manually rounded icon will appear double-rounded.
- Using a 1024x1024 image that is not exactly 1024x1024 pixels (e.g., 1023x1024 from an export rounding error) — causes a validation error or a blurry icon.

**Prevention:**
- Start from a 1024x1024 pixel, RGB (no alpha), PNG master image.
- Use "Single Size" mode in Xcode 14+. Do not manually populate size slots unless supporting iOS 11 or earlier (not relevant here — deployment target is iOS 18).
- After install on device, verify the icon appears on the home screen in the correct size and aspect ratio. The simulator icon and the device icon can differ.
- Clean build (`Product → Clean Build Folder`) after replacing an icon. Xcode caches asset catalog output and an old icon can persist through incremental builds.

**Detection (warning signs):**
- Icon looks correct in Xcode preview but shows placeholder on device home screen
- Clean build solves an icon display problem (confirms caching issue)
- Icon appears rounded twice (pre-rounded source + OS mask applied again)
- Build log shows "App Icon not found" or "Icon file not listed in CFBundleIconFiles"

**Phase that must address this:** App icon phase — the issue is entirely in asset catalog configuration, no code changes required. Takes minutes to fix if caught early; easy to miss until final device install.

---

### Pitfall E: App Icon Not Referenced by Build Target After Asset Catalog Changes

**What goes wrong:** Termostato's `Info.plist` or build settings must reference the asset catalog icon set by name. If the icon set in the asset catalog is renamed (e.g., from `AppIcon` to `AppIcon-v2`), the build target continues to look for `AppIcon` and silently falls back to no icon (blank placeholder on home screen).

**Why it happens:** The build setting `ASSETCATALOG_COMPILER_APPICON_NAME` specifies which icon set name to compile. Xcode sets this to `AppIcon` by default. If the asset catalog's icon set has a different name, the setting must be updated or the icons will not be embedded.

**Prevention:**
- Keep the icon set named `AppIcon` (the default). Do not rename it.
- If a rename is necessary, update the target's build setting `ASSETCATALOG_COMPILER_APPICON_NAME` to match.
- After any icon change, verify by archiving and inspecting the `.app` bundle: `Payload/Termostato.app/` should contain `AppIcon60x60@2x.png` (or equivalent generated files).

**Detection (warning signs):**
- Home screen shows blank/placeholder icon after a Xcode rebuild
- `find Termostato.app -name "AppIcon*"` finds no files in the built product
- Build log shows `actool: warning: No app icon set named 'AppIcon'`

---

### Pitfall F: Polling Interval Change From 30s to 10s Shrinks History Window by 3x

**What goes wrong:** The existing ViewModel uses a ring buffer with `maxHistory = 120` entries. At 30s polling, 120 entries cover 60 minutes of session history. At 10s polling, the same 120 entries cover only 20 minutes. The history chart silently becomes a 20-minute window instead of a 60-minute window. No code change triggers this — it is a pure behavioral consequence of the interval change.

**Why it matters:** If the user interprets the chart as showing "the session so far" (as originally designed), they will now see only the last 20 minutes. For a thermal monitor, losing 40 minutes of history could obscure the onset of a heating event.

**The math:**
- 30s × 120 entries = 3,600s = 60 minutes
- 10s × 120 entries = 1,200s = 20 minutes

**Prevention options (choose one):**

1. **Increase `maxHistory` to 360** to preserve 60 minutes of history at 10s polling.
   - 360 `ThermalReading` structs × ~64 bytes each ≈ 23 KB. Negligible memory cost.
   - No other code changes required; ring buffer behavior is unchanged.

2. **Decide 20 minutes is sufficient** and document the intent explicitly in a comment. Update any UI copy that implies "session-length" history.

3. **Make history duration fixed (e.g., always 60 minutes) regardless of polling interval** by computing `maxHistory = Int(3600 / pollingInterval)` dynamically. This is clean but adds complexity.

**Recommended:** Option 1 — increase `maxHistory` to 360. It is one line change, preserves the original behavior, and has zero performance cost at this scale (see below).

**Performance note:** At 10s polling, the chart receives one new data point every 10 seconds — not every tick. This is 6 per minute, 360 per hour. Swift Charts handles 360 `LineMark` data points comfortably with no perceptible lag. The existing Pitfall 4 (from v1.0 PITFALLS.md) about unbounded array growth does not apply as long as the cap is maintained.

**Phase that must address this:** Polling interval phase — the `maxHistory` constant must be updated in the same commit as the timer interval change.

---

### Pitfall G: Combine Timer RunLoop Mode — Interaction Pauses Timer at 30s, Surfaces at 10s

**What goes wrong:** `Timer.publish(every: 30, on: .main, in: .common)` uses `.common` RunLoop mode, which fires timers even during scroll interactions. However, if this were `.default` mode, touch events (scrolling the chart, tapping UI elements) would pause timer delivery. At 30s intervals, a missed tick is barely noticeable. At 10s intervals, a single missed tick produces a visible gap in the chart and a stale display for 10+ seconds during interaction.

**Current code check:** The existing `TemperatureViewModel` uses `.common` (confirmed in line 111 of `TemperatureViewModel.swift`). This is the correct choice and must not be changed to `.default` during the interval update.

**Why this matters at 10s:** The risk is that a developer modifying the Timer line to change `every: 30` to `every: 10` accidentally changes the RunLoop mode at the same time (e.g., copying from a different code sample that uses `.default`). The regression is subtle: timers appear to fire correctly until the user interacts with the chart, at which point readings stop updating for the duration of the touch.

**Prevention:**
- When changing the interval, change only the `every:` argument. Leave `on: .main, in: .common` unchanged.
- Code review the Timer line specifically after the interval change.

**Detection (warning signs):**
- Chart stops updating when user scrolls or taps
- Readings resume immediately after touch ends
- Changing `in: .common` to `in: .default` in the Timer call reproduces the behavior exactly

---

## Minor Pitfalls

### Pitfall H: TrollStore Install Path Conflicts With Xcode USB Install Path

**What goes wrong:** Apps installed via TrollStore and apps installed via Xcode (USB sideload) are treated as different installs by iOS, even if they share the same bundle identifier. Installing the TrollStore version of Termostato will not update the Xcode-installed version — it installs a second copy under the same bundle ID. iOS may show one app on the home screen while the other's data container persists. Switching back to Xcode install will not automatically remove the TrollStore install.

**Prevention:**
- When testing the TrollStore path, remove the Xcode-installed version first (`Hold icon → Remove App` on device).
- After TrollStore testing, to return to Xcode development builds, the TrollStore version must be removed explicitly through TrollStore's own uninstall UI.
- The app's data container is deleted when the app is removed, so any session state is lost on every path switch.

**Phase that must address this:** Numeric temperature phase — document the install path clearly in the phase plan so context is not lost mid-session.

---

### Pitfall I: Battery Impact at 10s Is Manageable but Not Zero — Do Not Increase Further Without Profiling

**What goes wrong:** Apple's Energy Efficiency Guide for iOS Apps states explicitly that timers prevent the CPU from returning to idle. At 10s intervals, the CPU wakes 6 times per minute instead of 2. For a thermal monitoring app that is useful precisely when the device is under load, this additional wakeup frequency is acceptable. However, if the interval is further reduced (to 5s or 1s) without profiling, the timer itself becomes a meaningful battery drain contributor — paradoxical for a tool that monitors device temperature.

**Context for 10s specifically:** `ProcessInfo.thermalState` is a property read — no network, no disk I/O, minimal CPU. The additional cost of reading it every 10s vs. every 30s is negligible. The timer overhead itself (wakeup from idle) is the dominant cost, and at 10s intervals it remains within acceptable range for a foreground app. This is not a blocking concern for v1.1 but is a ceiling to be aware of for v1.2.

**Prevention:**
- Do not reduce below 10s without running Instruments Energy Log on a physical device.
- Adding a timer tolerance of 1-2s (`Timer.publish` does not directly expose tolerance; use `Timer.scheduledTimer(withTimeInterval:repeats:block:).tolerance = 1.0` if lower-level control is needed) allows the system to coalesce wakeups and reduces battery impact at the cost of slightly variable polling precision.

**Phase that must address this:** Polling interval phase — this is informational, not a blocking concern at 10s.

---

## Phase-Specific Warnings — v1.1

| Phase Topic | Likely Pitfall | Mitigation |
|---|---|---|
| Numeric temperature (TrollStore) | Target device on iOS 18 — TrollStore incompatible | Verify device iOS version before writing any IOKit code |
| Numeric temperature (TrollStore) | Entitlement not embedded in built IPA | Add `systemgroup.com.apple.powerlog` to `.entitlements` file; build via TrollStore workflow, not standard Xcode archive |
| Numeric temperature (IOKit) | `IO_OBJECT_NULL` returned silently, displayed as 0.0°C | Guard on `IO_OBJECT_NULL`; display nil as "--"; release service handle in defer block |
| App icon | Icon not showing on device after replacing asset | Clean build after every icon change; verify asset catalog slot is filled, not just file on disk |
| App icon | Icon set name mismatch vs. build setting | Keep icon set named `AppIcon`; do not rename |
| App icon | Source image has alpha channel or wrong size | Use 1024x1024 RGB PNG, no transparency |
| 10s polling | History window shrinks from 60 min to 20 min | Update `maxHistory` from 120 to 360 in same commit |
| 10s polling | Timer RunLoop mode accidentally changed to `.default` | Only change `every:` argument; leave `on: .main, in: .common` |

---

## Sources

- TrollStore GitHub (opa334): https://github.com/opa334/TrollStore — supported iOS versions, entitlement behavior, banned entitlements on A12+
- TrollStore iOS 17.0.1+ compatibility statement: https://idevicecentral.com/tweaks/can-you-install-trollstore-on-ios-17-0-1-ios-18-3/
- leminlimez IOPMPowerSource gist (entitlement + Temperature key): https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc
- Xcode 14 Single Size App Icon — Use Your Loaf: https://useyourloaf.com/blog/xcode-14-single-size-app-icon/
- Apple — Configuring your app icon using an asset catalog: https://developer.apple.com/documentation/xcode/configuring-your-app-icon
- Apple Energy Efficiency Guide for iOS Apps — Minimize Timer Use: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeTimerUse.html
- Combine Timer RunLoop mode pitfall: https://www.kodeco.com/books/combine-asynchronous-programming-with-swift/v2.0/chapters/11-timers
- IOKit error handling — Apple Developer Documentation: https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/AccessingHardware/AH_Handling_Errors/AH_Handling_Errors.html
- IOPMPowerSource header (darwin-xnu): https://github.com/apple/darwin-xnu/blob/main/iokit/IOKit/pwr_mgt/IOPMPowerSource.h
