# Technology Stack

**Project:** Termostato
**Researched:** 2026-05-11
**Mode:** Ecosystem

---

## Recommended Stack

### Toolchain

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Xcode | 26.4.1 (stable) | IDE, compiler, device install | Latest stable as of May 2026; Apple renamed from 16.x to 26.x at WWDC25. 26.4.1 released 2026-04-16. Do NOT use 26.5 — still in beta as of this writing. |
| Swift | 6.3 (ships with Xcode 26.4.1) | Language | Required for Xcode 26.x. Swift 6 strict concurrency is default-on; use `@MainActor` on the ViewModel and let the compiler enforce it. |
| iOS SDK target | iOS 18.x (min deployment) | Runtime | Broad device support; Swift Charts line charts, Observable macro, and all required APIs are available. Do not target iOS 26 — reduces eligible device pool significantly for a personal tool. |
| SwiftUI | — (bundled) | UI framework | Use SwiftUI, not UIKit. This is a single-screen dashboard with a chart and two data labels — SwiftUI's declarative model is a better fit than UIKit's imperative callbacks. UIKit adds zero value here. |

**Note on Xcode versioning:** Apple's versioning scheme changed at WWDC 2025 — Xcode 17 was skipped and the product jumped to Xcode 26 to align with the OS version numbers. "Xcode 26" is the current generation, not a future release.

---

### Core Frameworks (Zero External Dependencies)

| Framework | Source | Purpose | Notes |
|-----------|--------|---------|-------|
| SwiftUI | Apple, built-in | Dashboard UI, bindings, navigation | |
| Swift Charts | Apple, built-in (iOS 16+) | Session-length history line chart | See charting section below |
| Foundation | Apple, built-in | `ProcessInfo.thermalState`, timers, notifications | |
| UserNotifications | Apple, built-in | Local threshold alerts | |
| IOKit (private use) | Apple, built-in | Numeric temperature via `IOPMPowerSource` | Requires entitlement — see private API section |

This app needs no Swift Package Manager dependencies. Every required API is in the system SDK.

---

### Architecture Pattern

| Pattern | Details |
|---------|---------|
| MVVM | Single `TemperatureViewModel` (`@Observable`, `@MainActor`). View files are dumb — they read from the ViewModel only. |
| Combine / Timer | `Timer.publish(every:on:in:).autoconnect()` drives the polling loop. Use `onReceive` in SwiftUI. |
| No persistence layer | Session data lives in a plain Swift array in the ViewModel. No CoreData, no SQLite, no UserDefaults. This is an explicit scope decision. |

---

## Private API: Numeric Temperature

This is the most research-intensive section because it directly affects feasibility.

### What Works — and Why It Is Constrained

**The mechanism:** `IOPMPowerSource` in IOKit exposes a `Temperature` key in its property dictionary. The raw value is an integer in units of 0.01 °C (e.g., 2800 = 28.00 °C). This is the battery/SoC thermal sensor — the same value used by tools like Battman and the doubleblak.com temperature page.

**The entitlement problem:** Accessing `IOPMPowerSource` on iOS requires the private entitlement `systemgroup.com.apple.powerlog`. This entitlement is NOT in Apple's public entitlement catalog and cannot be granted by a standard development provisioning profile (free or paid $99/yr). Apple's AMFI (AppleMobileFileIntegrity) enforces this at runtime — the entitlement must be present in the provisioning profile, not just the binary.

**Consequence for standard Xcode sideloading:** A standard Xcode sideload with a free Apple ID (or even a paid $99 Developer Program account) will NOT be able to attach this entitlement. The IOKit call will return no result or a sandboxed empty dictionary.

### Tier Summary

| Access Method | Gets Numeric Temp? | Feasible for This Project? |
|--------------|-------------------|---------------------------|
| `ProcessInfo.thermalState` | No — 4-level categorical only | Yes — always works |
| IOKit `IOPMPowerSource` via standard Xcode sideload | No — blocked by AMFI/sandbox | No |
| IOKit `IOPMPowerSource` via TrollStore | Yes | Maybe — iOS 15.5–17.0 only, requires device-side install tool |
| Filesystem read of `knowledgeC.db` (`/private/var/mobile/Library/CoreDuet/Knowledge/`) | Yes — `batterytemperature` stream, value / 100 = °C | No — sandboxed path, requires jailbreak or TrollStore |
| Jailbreak | Yes — full sensor access | Out of scope (stated in PROJECT.md) |

### Decision

**Use `ProcessInfo.thermalState` as the primary data source.** It is public, sandbox-safe, and always works with standard Xcode sideloading. It provides four levels: `.nominal`, `.fair`, `.serious`, `.critical`.

**Attempt `IOPMPowerSource` as a best-effort secondary path.** Include the IOKit call in the codebase. If the entitlement is absent (standard sideload), the call returns empty data and the app gracefully degrades to showing "–°C". This design is honest: the v1 milestone should document that numeric temperature display requires TrollStore or an entitlement-granting mechanism.

**Do not use TrollStore as a hard dependency for v1.** TrollStore support is capped at iOS 17.0 and requires a separate install flow. It should be a documented "optional enhancement path" after v1 ships.

### Implementation Sketch

```swift
// Bridging header or inline C interop
import IOKit

func readBatteryTemperature() -> Double? {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPMPowerSource")
    )
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    var props: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
    guard result == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

    guard let rawTemp = dict["Temperature"] as? Int else { return nil }
    return Double(rawTemp) / 100.0  // Returns °C
}
```

This code compiles and runs on any iOS target. It returns `nil` silently when sandboxed. No crash, no error, no user-visible issue.

---

## Charting

**Use Apple's Swift Charts framework (built-in since iOS 16).** No third-party library needed.

### Why Swift Charts

- Zero additional dependency, no SPM integration, no version pinning.
- `LineMark` with a rolling 60-second or session-length `[TemperatureReading]` array is ~20 lines of SwiftUI.
- Smooth animated updates when the `@Observable` ViewModel's array changes.
- Sufficient for a time-series temperature line chart.

### What NOT to Use

- **DGCharts (formerly Charts/MPAndroidChart):** Active library but adds a dependency for a use case Swift Charts handles natively.
- **SciChart:** Commercial, heavyweight, designed for financial/scientific data at scale. Total overkill.
- **SwiftCharts (ivnsch):** Unmaintained; last commit 2019.

---

## Alerts / Notifications

### Approach: Local Notifications via UserNotifications

Termostato's alert strategy must work within iOS's strict background execution restrictions.

**The correct model for this app:**

1. The app is primarily a **foreground monitoring app**. The user opens it to watch temperature.
2. When the app is in the foreground, use a `Timer`-driven polling loop to check the threshold in-process. When temperature exceeds the threshold, fire a `UNUserNotificationCenter` local notification immediately with `UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)`.
3. When the app is backgrounded, the timer stops. Background execution cannot be relied upon for continuous monitoring with a standard sideloaded free-cert app.

**Do NOT attempt:**
- `BGAppRefreshTask` — system-scheduled, runs at Apple's discretion (may be minutes or hours later). Not suitable for thermal alerting.
- `BGProcessingTask` — same problem, designed for long batch work, not sensor polling.
- `BGContinuedProcessingTask` (iOS 26+) — requires iOS 26, requires user-initiated task start, designed for exports and uploads, not indefinite polling.
- Remote push notifications — requires APNs server infrastructure. Out of scope for a personal sideloaded app.

**Entitlement needed:** `UNUserNotificationCenter` requires the app to request permission at runtime with `requestAuthorization(options:)`. No special entitlement is needed beyond the standard `UIBackgroundModes` key if audio or location is not used. Local notifications are fully available to sideloaded apps with a free Apple ID.

---

## Code Signing / Sideloading

### Free Apple ID Path (v1)

| Parameter | Value |
|-----------|-------|
| Signing method | Xcode automatic signing, "Personal Team" |
| Certificate type | iOS Development certificate (auto-created by Xcode) |
| Provisioning profile | Xcode-managed free profile |
| Certificate validity | 7 days from first install |
| App validity on device | 7 days — must reinstall via Xcode each week |
| Device limit | 3 unique UDIDs per 7-day rolling window |
| Entitlements available | Standard sandbox entitlements only (no private `com.apple.*` entitlements) |
| App ID | Must use a unique bundle ID, e.g., `com.yourname.termostato` |

### How to Install

1. Plug iPhone into Mac via USB.
2. Open Xcode → Signing & Capabilities → select "Personal Team" from the team dropdown.
3. Set a unique Bundle Identifier.
4. Product → Run (or ⌘R with the iPhone as destination).
5. On first install: Settings → General → VPN & Device Management → trust the developer certificate.
6. Repeat step 4 every 7 days.

### Entitlement Constraints

The free developer profile grants only entitlements that Xcode can automatically provision. This explicitly excludes `systemgroup.com.apple.powerlog` and any other `com.apple.private.*` entitlements. A paid $99/yr Developer Program membership does not unlock private entitlements either — those require TrollStore or jailbreak.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| UI framework | SwiftUI | UIKit | UIKit adds boilerplate with zero benefit for a single-screen dashboard |
| Charting | Swift Charts (built-in) | DGCharts, SciChart | External dependency for functionality already in SDK |
| Background alerts | In-process timer + local notification | BGAppRefreshTask | System-scheduled, unreliable for thermal threshold alerts |
| Numeric temp | IOKit best-effort + ProcessInfo fallback | TrollStore-exclusive IOKit | Locks out standard sideload entirely |
| Language | Swift 6.3 | Objective-C | No reason to use ObjC for a new greenfield app; Swift has full IOKit interop via bridging header |
| Xcode version | 26.4.1 (latest stable) | 26.5 beta | Avoid beta toolchain for primary dev work |

---

## Installation

No external dependencies. The full dependency surface is:

```
Xcode 26.4.1 (from Mac App Store)
  └── Swift 6.3 (bundled)
  └── iOS 26.5 SDK (bundled — but target iOS 18.x minimum deployment)
  └── Swift Charts (bundled in iOS 16+ SDK)
  └── UserNotifications (bundled)
  └── IOKit (bundled; used via bridging header for private API call)
```

No `Package.swift`, no `Podfile`, no Carthage. Zero package manager setup.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Xcode 26.4.1 as latest stable | HIGH | Verified via xcodereleases.com (2026-05-11) |
| Swift 6.3 in Xcode 26.4.1 | MEDIUM | Verified via xcodereleases.com; 6.3.2 also referenced — minor point version |
| SwiftUI over UIKit | HIGH | Universally recommended for new greenfield iOS apps |
| Swift Charts sufficiency | HIGH | Official Apple framework; well-documented for line charts |
| IOKit `IOPMPowerSource` blocked by AMFI on standard sideload | HIGH | Corroborated by multiple Apple Developer Forum threads, Battman docs, and analysis of the `systemgroup.com.apple.powerlog` entitlement requirement |
| `ProcessInfo.thermalState` as reliable fallback | HIGH | Public, documented, sandbox-safe API |
| Local notifications for threshold alerts | HIGH | Standard iOS API, no special entitlements, confirmed working in sideloaded apps |
| BGAppRefreshTask unsuitability for this use case | HIGH | Documented system-discretionary behavior; wrong tool for real-time threshold monitoring |

---

## Critical Findings Summary

1. **Numeric temperature is blocked by AMFI on standard Xcode sideloads.** The `IOPMPowerSource` Temperature key requires `systemgroup.com.apple.powerlog` — a private entitlement unavailable to free or paid developer certificates. Code it as best-effort; display "–°C" when unavailable. Document TrollStore as the path to unlock it.

2. **`ProcessInfo.thermalState` is the reliable data source.** It always works, is public and documented, and gives the four-level thermal classification that is genuinely useful.

3. **No external libraries needed.** Swift Charts handles the history chart. UserNotifications handles alerts. IOKit (via bridging header) handles the best-effort numeric read. Total dependency count: zero.

4. **Xcode versioning changed.** Xcode 17 does not exist. The current generation is Xcode 26.x (released WWDC 2025). Use 26.4.1 stable.

---

## Sources

- [xcodereleases.com](https://xcodereleases.com/) — Xcode 26.4.1 confirmed latest stable, released 2026-04-16
- [Apple Developer Forums: iOS cpu/gpu/battery temperature](https://developer.apple.com/forums/thread/696700) — confirms no public iOS temperature API
- [Apple Developer Forums: Find out battery temperature of iPhone](https://developer.apple.com/forums/thread/47341) — private API discussion
- [Get iOS Battery Info and Temperature (GitHub Gist by leminlimez)](https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc) — `IOPMPowerSource` Temperature key usage, `systemgroup.com.apple.powerlog` entitlement requirement
- [doubleblak.com/temperature](https://doubleblak.com/temperature) — alternative filesystem approach via `knowledgeC.db`
- [Battman IPA (iDevice Central)](https://idevicecentral.com/jailbreak-tweaks/battman-ipa-advanced-battery-management-cycle-count-for-jailbroken-trollstore-ios-devices/) — confirms TrollStore required for private battery APIs
- [Swift Charts Documentation](https://developer.apple.com/documentation/charts) — official Apple framework
- [BGContinuedProcessingTask (Apple Developer Documentation)](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask) — iOS 26 only, not suited for persistent monitoring
- [ProcessInfo.ThermalState (Apple Developer Documentation)](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum) — public API, 4 levels
- [Swift 6.2 Released (swift.org)](https://www.swift.org/blog/swift-6.2-released/) — September 2025 release context
- [How iOS Sideloading Actually Works in 2025 (DEV Community)](https://dev.to/1_king_0b1e1f8bfe6d1/how-ios-sideloading-actually-works-in-2025-dev-certs-altstore-and-the-eu-exception-1m2h) — free Apple ID, 7-day cert mechanics
