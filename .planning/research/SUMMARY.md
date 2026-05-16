# Research Summary — CoreWatch v1.1

**Project:** CoreWatch
**Domain:** iOS thermal monitoring app (sideloaded, personal use)
**Milestone:** v1.1 — Custom app icon + polling interval reduction (30s → 10s)
**Researched:** 2026-05-13
**Confidence:** HIGH

> **Scope note:** v1.1 research originally covered three features: app icon, TrollStore IOKit numeric
> temperature, and polling interval. The TrollStore/IOKit path has been ruled **out of scope** for
> this milestone. The target device runs iOS 18.x; TrollStore supports a maximum of iOS 17.0 and
> will never support iOS 17.0.1 or later (Apple patched the CoreTrust vulnerability CVE-2023-41991
> in iOS 17.0.1). The numeric temperature feature is deferred to a future milestone contingent on
> a compatible device being available. All TrollStore-specific findings are documented in the
> research files for reference but are NOT roadmap-relevant for v1.1.

---

## Executive Summary

CoreWatch v1.1 is a low-risk, two-change milestone. Both in-scope features are well-understood,
require no new frameworks or dependencies, and can be validated quickly. The custom app icon is a
pure asset-catalog change — zero Swift code involved. The polling interval reduction from 30s to
10s is a single integer literal change in `TemperatureViewModel.swift`, with one required companion
change: `maxHistory` must increase from 120 to 360 to preserve 60 minutes of session history at
the new sampling rate, and the chart sub-label in `ContentView.swift` must be updated to match.

The main implementation risk is a subtle behavioral consequence of the polling change: failing to
update `maxHistory` alongside the timer interval silently shrinks the history window from 60 minutes
to 20 minutes, with no build warning or runtime error. Both constants must ship in the same commit.
The app icon risk is lower — the existing `AppIcon.appiconset/Contents.json` is already in the
correct Xcode 14+ single-size format. The only pitfalls are dragging the PNG into Finder instead of
Xcode's asset catalog editor (which leaves `Contents.json` unreferenced), and failing to clean-build
before verifying on device (Xcode caches asset catalog output).

No new tooling, no new frameworks, no new entitlements, no new files. The bridging header, signing
configuration, and notification infrastructure from v1.0 are untouched. This milestone closes
entirely within the existing app structure.

---

## Key Findings

### Recommended Stack

The v1.0 stack is unchanged. Xcode 26.4.1 with Swift 6.3 and iOS 18.x minimum deployment remain
correct. No new frameworks are introduced. The existing `Timer.publish(every:on:in:)` Combine
pipeline handles the polling interval change natively — `Timer.publish(every: 10, ...)` is a
drop-in replacement with identical behavior at a different cadence.

**Core technologies relevant to v1.1:**
- `Timer.publish(every:on:in:)` (Combine/Foundation): drives polling loop — interval literal is the only change
- Swift Charts (bundled): renders history chart — unchanged; handles 360 data points without performance concern
- `Assets.xcassets` / `AppIcon.appiconset`: Xcode 14+ single-size mode already configured; one PNG slot to fill

### In-Scope Features

**Must do (v1.1 scope):**
- Custom app icon — Xcode placeholder signals "dev build" even on a personal tool; one 1024x1024 PNG resolves it
- Reduce polling interval 30s → 10s — surfaces thermal state changes 3x faster; notification latency from the polling path drops from 30s worst-case to 10s
- Increase `maxHistory` 120 → 360 — mandatory companion to interval change; preserves 60-minute history window
- Update chart sub-label — "Session history (last 60 min)" remains accurate after the maxHistory increase

**Out of scope for v1.1 (explicitly deferred):**
- Numeric temperature via TrollStore/IOKit — device runs iOS 18.x; TrollStore maximum is iOS 17.0; blocked at the device level. Defer until a compatible device is available or an alternative access path is identified.

### Architecture Impact

Both in-scope changes are surgical. The v1.0 MVVM structure (`TemperatureViewModel @Observable @MainActor` + dumb `ContentView`) is untouched architecturally.

**Modified components:**

| File | Change | Lines affected |
|------|--------|---------------|
| `TemperatureViewModel.swift` | `Timer.publish(every: 30)` → `Timer.publish(every: 10)` | 1 line (line 111) |
| `TemperatureViewModel.swift` | `maxHistory = 120` → `maxHistory = 360` | 1 line (line 49) |
| `ContentView.swift` | Chart sub-label string update | 1 line (line 113) |
| `Assets.xcassets/AppIcon.appiconset/` | Add 1024x1024 PNG; `Contents.json` gains `"filename"` key | Asset + JSON |

No new files. No new Swift types. No new framework imports.

### Critical Pitfalls

1. **`maxHistory` not updated with polling interval** — At 10s polling, the existing 120-entry ring buffer covers only 20 minutes. Failing to increase to 360 silently degrades the history window with no error. Both constants must change in the same commit. (PITFALLS.md: Pitfall F)

2. **App icon PNG dragged to Finder instead of Xcode's asset catalog editor** — The file lands on disk but `Contents.json` is never updated with a `"filename"` key. The build succeeds; the icon remains a placeholder on the home screen. Always drag into Xcode's editor UI. (PITFALLS.md: Pitfall D)

3. **Stale asset cache after icon change** — Xcode caches asset catalog output. Always run `Product → Clean Build Folder` before verifying on device after any icon change. (PITFALLS.md: Pitfall D)

4. **Timer RunLoop mode accidentally changed** — When editing `every: 30` to `every: 10`, only the `every:` argument changes. `on: .main, in: .common` must remain. Switching to `.default` pauses timer delivery during touch interactions. (PITFALLS.md: Pitfall G)

5. **App icon PNG has alpha channel or wrong dimensions** — iOS rejects icons with transparency. No pre-applied rounded corners (iOS applies squircle mask; pre-rounded source creates double-masking). Must be exactly 1024x1024 pixels, sRGB PNG, opaque. (PITFALLS.md: Pitfall D)

---

## Implications for Roadmap

Both features are independent. Neither blocks the other. Recommended execution order is lowest-risk
first to establish a working baseline before the slightly more involved asset work.

### Phase 1: Polling Interval + History Preservation

**Rationale:** One-line code change with a well-understood behavioral consequence. Verifiable in Simulator immediately. Establishes a clean commit before touching assets.

**Delivers:** 10-second polling cadence with 60-minute history preserved at the higher resolution.

**Addresses:**
- Timer interval reduction (30s → 10s) — `TemperatureViewModel.swift` line 111
- Ring buffer expansion (120 → 360) — `TemperatureViewModel.swift` line 49
- Chart sub-label accuracy — `ContentView.swift` line 113

**Avoids:**
- Pitfall F: `maxHistory` and timer interval must ship together; a half-done change silently corrupts the history window
- Pitfall G: only `every:` changes; `on: .main, in: .common` is preserved exactly

**Research flag:** No additional research needed. Documented Combine API, direct codebase line references confirmed.

---

### Phase 2: Custom App Icon

**Rationale:** Pure asset change with zero code risk. Requires a designed PNG (external dependency) and device verification after a clean build.

**Delivers:** Custom icon visible on home screen, Spotlight, and Settings.

**Addresses:**
- Custom app icon — `Assets.xcassets/AppIcon.appiconset/` PNG slot + `Contents.json` filename key

**Avoids:**
- Pitfall D: drag into Xcode editor (not Finder); clean build before device verify
- Pitfall E: keep asset set named `AppIcon`; do not rename
- PNG requirements: 1024x1024, RGB (no alpha), no pre-rounded corners, sRGB

**Research flag:** No additional research needed. Existing `Contents.json` already in Xcode 14+ single-size format; the slot is pre-configured.

---

### Phase Ordering Rationale

- Code-only phase first: the polling change requires no external assets, is instantly testable in Simulator, and has a deterministic pass/fail (either the chart shows 360 entries over 60 minutes or it does not). No design tooling dependency.
- Asset phase second: icon work depends on a designed PNG being ready. Keeping it second means the polling work is committed and verified before any asset pipeline questions arise.
- Both phases are small enough to merge into a single milestone build. The phase split only matters if the icon design takes longer than the code change.

---

### Research Flags

- **Phase 1 (polling interval):** No research needed. Standard Combine timer pattern; exact line numbers in codebase confirmed.
- **Phase 2 (app icon):** No research needed. Xcode 14+ single-size mode is fully documented; the project's asset catalog is already correctly configured for it.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack (polling change) | HIGH | Timer.publish is a documented Combine API; interval is an unconstrained scalar; codebase line confirmed |
| Stack (app icon) | HIGH | Xcode 14+ single-size mode confirmed via Apple docs; Contents.json already in correct format |
| Features (in-scope) | HIGH | Both features are additive changes to existing confirmed-working infrastructure |
| Architecture | HIGH | Codebase read directly; exact line numbers for every constant confirmed 2026-05-13 |
| Pitfalls | HIGH | Derived from official Apple docs, direct codebase analysis, and TrollStore GitHub |

**Overall confidence:** HIGH

### Gaps to Address

- **Icon design asset:** The technical pipeline is fully understood but the 1024x1024 PNG must be produced before Phase 2 can execute. This is a prerequisite for the implementer, not a research gap.
- **Device icon cache quirk:** A freshly sideloaded icon occasionally requires a device restart to appear on the home screen. This is a known iOS behavior, not a build bug. Document in the phase plan to prevent wasted debugging time.

---

## Out-of-Scope Reference: TrollStore / IOKit Numeric Temperature

The following findings are preserved for future planning but are **not actionable for v1.1**.

- TrollStore supports iOS 14.0b2 through iOS 17.0 only. iOS 17.0.1 and all iOS 18.x are permanently incompatible (CoreTrust CVE-2023-41991 patched by Apple, confirmed in TrollStore README and iDevice Central).
- Numeric temperature key: `"Temperature"` in the `IOPMPowerSource` IOKit dictionary. Raw value is centidegrees Celsius (divide by 100 for °C).
- Required entitlement: `systemgroup.com.apple.powerlog` (private, boolean true).
- The bridging header (`CoreWatch-Bridging-Header.h`) already declares all needed IOKit C functions. No bridging header changes are needed when this feature is eventually implemented.
- Build workflow would require a separate Xcode build configuration with `CODE_SIGNING_ALLOWED=NO` and an ldid Run Script phase.
- Graceful degradation is architecture-ready: a `numericTemperature: Double?` property returning nil when the entitlement is absent displays nothing rather than "0.0°C".

**To revisit:** Acquire a device on iOS 17.0 or earlier, or monitor TrollStore project for future iOS 18+ support (no current timeline from opa334).

---

## Sources

### Primary (HIGH confidence)
- [Apple Developer Documentation — Configuring your app icon](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) — single-size asset catalog workflow
- [Apple Energy Efficiency Guide — Minimize Timer Use](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeTimerUse.html) — timer wakeup overhead guidance
- `TemperatureViewModel.swift` (existing codebase, read 2026-05-13) — `Timer.publish(every: 30)` at line 111, `maxHistory = 120` at line 49
- `ContentView.swift` (existing codebase, read 2026-05-13) — chart sub-label at line 113
- `Assets.xcassets/AppIcon.appiconset/Contents.json` (existing codebase, read 2026-05-13) — single-entry modern format confirmed
- [TrollStore GitHub (opa334)](https://github.com/opa334/TrollStore) — iOS version ceiling confirmed

### Secondary (MEDIUM confidence)
- [SwiftLee — App Icon Generator no longer needed with Xcode 14](https://www.avanderlee.com/xcode/replacing-app-icon-generators/) — single-size workflow confirmation
- [Use Your Loaf — Xcode 14 Single Size App Icon](https://useyourloaf.com/blog/xcode-14-single-size-app-icon/) — asset catalog mode details
- [iDevice Central — TrollStore on iOS 17.0.1–26.2](https://idevicecentral.com/tweaks/can-you-install-trollstore-on-ios-17-0-1-ios-18-3/) — iOS 18 incompatibility confirmation (out-of-scope reference)
- [leminlimez — IOPMPowerSource gist](https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc) — Temperature key, entitlement string (out-of-scope reference)

---

*Research completed: 2026-05-13*
*Ready for roadmap: yes*
