<!-- GSD:project-start source:PROJECT.md -->
## Project

**Termostato**

Termostato is a personal iOS app (sideloaded, not App Store) that monitors the internal temperature of an iPhone in real time. It displays both a numeric temperature reading (via private iOS APIs) and the system thermal state level, rendered in a live dashboard with a session-length history chart and push-notification alerts when the device overheats.

**Core Value:** The phone's actual internal temperature, always visible at a glance — with an alert before it gets dangerously hot.

### Constraints

- **Platform:** iOS only — no cross-platform framework needed
- **API access:** Private APIs required for numeric temperature; accepted risk since sideloaded
- **Signing:** Free Apple ID → 7-day certificate expiry, must re-install weekly unless upgraded to $99/yr Developer account
- **Background execution:** Push-notification-based alerting needs a background task or local notification strategy; full background execution is restricted on iOS
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Toolchain
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Xcode | 26.4.1 (stable) | IDE, compiler, device install | Latest stable as of May 2026; Apple renamed from 16.x to 26.x at WWDC25. 26.4.1 released 2026-04-16. Do NOT use 26.5 — still in beta as of this writing. |
| Swift | 6.3 (ships with Xcode 26.4.1) | Language | Required for Xcode 26.x. Swift 6 strict concurrency is default-on; use `@MainActor` on the ViewModel and let the compiler enforce it. |
| iOS SDK target | iOS 18.x (min deployment) | Runtime | Broad device support; Swift Charts line charts, Observable macro, and all required APIs are available. Do not target iOS 26 — reduces eligible device pool significantly for a personal tool. |
| SwiftUI | — (bundled) | UI framework | Use SwiftUI, not UIKit. This is a single-screen dashboard with a chart and two data labels — SwiftUI's declarative model is a better fit than UIKit's imperative callbacks. UIKit adds zero value here. |
### Core Frameworks (Zero External Dependencies)
| Framework | Source | Purpose | Notes |
|-----------|--------|---------|-------|
| SwiftUI | Apple, built-in | Dashboard UI, bindings, navigation | |
| Swift Charts | Apple, built-in (iOS 16+) | Session-length history line chart | See charting section below |
| Foundation | Apple, built-in | `ProcessInfo.thermalState`, timers, notifications | |
| UserNotifications | Apple, built-in | Local threshold alerts | |
| IOKit (private use) | Apple, built-in | Numeric temperature via `IOPMPowerSource` | Requires entitlement — see private API section |
### Architecture Pattern
| Pattern | Details |
|---------|---------|
| MVVM | Single `TemperatureViewModel` (`@Observable`, `@MainActor`). View files are dumb — they read from the ViewModel only. |
| Combine / Timer | `Timer.publish(every:on:in:).autoconnect()` drives the polling loop. Use `onReceive` in SwiftUI. |
| No persistence layer | Session data lives in a plain Swift array in the ViewModel. No CoreData, no SQLite, no UserDefaults. This is an explicit scope decision. |
## Private API: Numeric Temperature
### What Works — and Why It Is Constrained
### Tier Summary
| Access Method | Gets Numeric Temp? | Feasible for This Project? |
|--------------|-------------------|---------------------------|
| `ProcessInfo.thermalState` | No — 4-level categorical only | Yes — always works |
| IOKit `IOPMPowerSource` via standard Xcode sideload | No — blocked by AMFI/sandbox | No |
| IOKit `IOPMPowerSource` via TrollStore | Yes | Maybe — iOS 15.5–17.0 only, requires device-side install tool |
| Filesystem read of `knowledgeC.db` (`/private/var/mobile/Library/CoreDuet/Knowledge/`) | Yes — `batterytemperature` stream, value / 100 = °C | No — sandboxed path, requires jailbreak or TrollStore |
| Jailbreak | Yes — full sensor access | Out of scope (stated in PROJECT.md) |
### Decision
### Implementation Sketch
## Charting
### Why Swift Charts
- Zero additional dependency, no SPM integration, no version pinning.
- `LineMark` with a rolling 60-second or session-length `[TemperatureReading]` array is ~20 lines of SwiftUI.
- Smooth animated updates when the `@Observable` ViewModel's array changes.
- Sufficient for a time-series temperature line chart.
### What NOT to Use
- **DGCharts (formerly Charts/MPAndroidChart):** Active library but adds a dependency for a use case Swift Charts handles natively.
- **SciChart:** Commercial, heavyweight, designed for financial/scientific data at scale. Total overkill.
- **SwiftCharts (ivnsch):** Unmaintained; last commit 2019.
## Alerts / Notifications
### Approach: Local Notifications via UserNotifications
- `BGAppRefreshTask` — system-scheduled, runs at Apple's discretion (may be minutes or hours later). Not suitable for thermal alerting.
- `BGProcessingTask` — same problem, designed for long batch work, not sensor polling.
- `BGContinuedProcessingTask` (iOS 26+) — requires iOS 26, requires user-initiated task start, designed for exports and uploads, not indefinite polling.
- Remote push notifications — requires APNs server infrastructure. Out of scope for a personal sideloaded app.
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
### Entitlement Constraints
## Alternatives Considered
| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| UI framework | SwiftUI | UIKit | UIKit adds boilerplate with zero benefit for a single-screen dashboard |
| Charting | Swift Charts (built-in) | DGCharts, SciChart | External dependency for functionality already in SDK |
| Background alerts | In-process timer + local notification | BGAppRefreshTask | System-scheduled, unreliable for thermal threshold alerts |
| Numeric temp | IOKit best-effort + ProcessInfo fallback | TrollStore-exclusive IOKit | Locks out standard sideload entirely |
| Language | Swift 6.3 | Objective-C | No reason to use ObjC for a new greenfield app; Swift has full IOKit interop via bridging header |
| Xcode version | 26.4.1 (latest stable) | 26.5 beta | Avoid beta toolchain for primary dev work |
## Installation
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
## Critical Findings Summary
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
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
