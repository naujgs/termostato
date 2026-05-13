# Technology Stack

**Project:** Termostato
**Researched:** 2026-05-13 (v1.1 update — app icon, TrollStore IOKit, polling interval)
**Mode:** Ecosystem

---

## Established Stack (v1.0 — Do Not Change)

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| Xcode | 26.4.1 (stable) | IDE, compiler, device install | Confirmed — do not upgrade to 26.5 beta |
| Swift | 6.3 (ships with Xcode 26.4.1) | Language | Confirmed — strict concurrency on, `@MainActor` on ViewModel |
| iOS SDK target | iOS 18.x (min deployment) | Runtime | Confirmed |
| SwiftUI | bundled | UI framework | Confirmed |
| Swift Charts | bundled (iOS 16+) | Session-length history chart | Confirmed |
| Foundation | bundled | `ProcessInfo.thermalState`, timers | Confirmed |
| UserNotifications | bundled | Local threshold alerts | Confirmed |
| IOKit | bundled (via bridging header) | Private API access point | Header exists; call blocked under free Apple ID |

No external dependencies. No SPM, no CocoaPods, no Carthage.

---

## v1.1 Stack Changes

### 1. App Icon

**What to do:** Add a single 1024x1024 PNG to the existing `AppIcon.appiconset` slot. No new tooling required — Xcode 26 already uses single-size mode.

**Current state of `AppIcon.appiconset/Contents.json`:**
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

The slot is already configured for single-size (universal, ios, 1024x1024). It is missing a `"filename"` key because no image has been placed yet. Adding an image via Xcode's asset catalog editor writes the filename automatically.

**Image requirements (HIGH confidence — Apple developer documentation + multiple sources):**
- **Dimensions:** 1024x1024 pixels exactly
- **Format:** PNG
- **Alpha channel:** Must be absent (opaque). Transparent pixels appear black; Xcode warns on build
- **Rounded corners:** Do not add — iOS applies superellipse mask automatically. Adding your own creates double-masking artifacts
- **Color space:** sRGB recommended

**Tooling options for generating the PNG (no installation required):**
- Sketch, Figma, Affinity Designer, or any image editor that can export 1024x1024 PNG without alpha
- macOS Preview: File > Export, format PNG, uncheck alpha if shown
- SF Symbols-derived icon: use Xcode's SF Symbol renderer at 1024x1024 via a small SwiftUI view snapshot (requires a script or manual Simulator screenshot)

**No third-party icon generator tools are needed.** Xcode 14+ single-size mode eliminates the need for tools like MakeAppIcon, IconGenerator, or Asset Catalog Creator. The `AppIcon.appiconset` in this project is already correctly configured — adding the PNG file is the only step.

**How to add in Xcode:**
1. Drag the 1024x1024 PNG onto the single slot in Assets.xcassets > AppIcon
2. Xcode writes the filename into Contents.json and shows a preview
3. Build — the icon appears on device after install

**Confidence:** HIGH — single-size AppIcon has been the Xcode default for new iOS projects since Xcode 14 (released 2022). The project's existing Contents.json already matches the correct format.

---

### 2. IOKit IOPMPowerSource Temperature via TrollStore

#### TrollStore Version Support

**Supported iOS range:** iOS 14.0 beta 2 through iOS 17.0 (inclusive)
**Maximum iOS version:** 17.0
**iOS 17.0.1 and all iOS 18.x: NOT supported and will never be supported** — Apple patched the CoreTrust vulnerability (CVE-2023-41991) in iOS 17.0.1, and this fix persists through iOS 18.x and iOS 26.x.

**Critical implication for this project:** The target device must be on iOS 14.0b2–16.6.1, 16.7 RC (20H18), or exactly iOS 17.0. The project currently targets iOS 18.x as its minimum deployment target. This means the TrollStore path is a **device-specific feature** that only works on a device meeting the above version constraint. The app must gracefully degrade on iOS 17.0.1+ (which includes the production v1.0 device running iOS 18.x).

**Confidence:** HIGH — verified via TrollStore GitHub README and multiple corroborating sources.

#### Entitlement

**Required entitlement:** `systemgroup.com.apple.powerlog`
**Type:** Boolean, value `true`
**Verified by:** leminlimez GitHub Gist (primary source), corroborated by STACK.md v1.0 research

This entitlement is a private Apple entitlement not in Apple's public entitlement catalog. TrollStore preserves it during its fake-root-certificate resign process — this is the core of what TrollStore enables.

#### IOKit Key and Value

**Service name:** `IOPMPowerSource`
**Dictionary key:** `"Temperature"`
**Raw value units:** Integer in hundredths of degrees Celsius (e.g., `2850` = 28.50°C)
**Conversion:** `Double(rawValue) / 100.0`

**Verified by:** leminlimez GitHub Gist (direct inspection of working code), apple/darwin-xnu IOPMPowerSource.h source.

#### Bridging Header Status

The project's `Termostato-Bridging-Header.h` already declares all required IOKit C functions:
- `IOServiceGetMatchingService`
- `IOServiceMatching`
- `IORegistryEntryCreateCFProperties`
- `IOObjectRelease`

No changes to the bridging header are needed for v1.1.

#### Xcode Project Configuration for TrollStore

TrollStore requires the entitlement to be embedded in the binary before installation. Standard Xcode code signing strips non-provisioned entitlements at build time, so a two-part approach is needed:

**Option A — ldid post-build script (recommended, no external tool on device needed):**

1. Create `Termostato.entitlements` file in the project with:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>systemgroup.com.apple.powerlog</key>
    <true/>
    <key>application-identifier</key>
    <string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>get-task-allow</key>
    <true/>
</dict>
</plist>
```

2. Set build setting `CODE_SIGN_ENTITLEMENTS` to point to this file

3. Add a Run Script build phase:
```bash
PATH="/opt/homebrew/bin:$PATH"
if [ "$CODE_SIGNING_ALLOWED" = "NO" ]; then
    ldid -S${CODE_SIGN_ENTITLEMENTS} "${CODESIGNING_FOLDER_PATH}"
fi
```

4. Set build setting `CODE_SIGNING_ALLOWED = NO` for the TrollStore build configuration

5. Export as IPA (Product > Archive > Distribute App) and install via TrollStore

**ldid install (one-time, on dev Mac):** `brew install ldid`

**Option B — retain standard Xcode signing, export IPA, inject entitlement manually:**
Build normally (keep standard signing for Xcode USB installs), then for TrollStore distribution: export IPA, run `ldid -Sentitlements.plist Payload/Termostato.app/Termostato`, repackage as zip. More steps, less automatable.

**Recommendation:** Option A. Keep two build configurations in Xcode: `Debug` (standard Xcode signing, USB install via `⌘R`) and `TrollStore` (`CODE_SIGNING_ALLOWED=NO`, ldid script, export IPA). This preserves the normal Xcode development workflow.

**ldid version:** Use `ldid-procursus` via Homebrew — `brew install ldid`. Current stable as of May 2026 is sufficient; no specific version pinning needed.

**Confidence:** MEDIUM — ldid + TrollStore entitlement workflow is well-documented in community sources (XcodeAnyTroll project, TrollStore README). The exact entitlement string `systemgroup.com.apple.powerlog` is HIGH confidence (verified via leminlimez gist). The Xcode build configuration workflow is MEDIUM because it is documented primarily via community tooling (XcodeAnyTroll) rather than Apple official docs.

#### Swift Implementation

The bridging header already exposes the necessary functions. Implementation in `TemperatureViewModel`:

```swift
func readBatteryTemperature() -> Double? {
    let service = IOServiceGetMatchingService(
        0,  // kIOMainPortDefault
        IOServiceMatching("IOPMPowerSource")
    )
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    var propsRef: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
    guard result == KERN_SUCCESS,
          let dict = propsRef?.takeRetainedValue() as? [String: Any],
          let rawTemp = dict["Temperature"] as? Int
    else { return nil }

    return Double(rawTemp) / 100.0
}
```

Returns `nil` when entitlement is absent (standard sideload, iOS 18.x). No crash, no error thrown. UI shows "–°C" on `nil`. This is the same design from the v1.0 STACK.md and has been validated as safe.

**Note on kIOMainPortDefault:** On iOS SDK, use `0` (the integer value of `kIOMainPortDefault`) rather than the symbol directly — the symbol is defined in IOKit headers that may not be fully accessible from the iOS SDK bridging header. This matches the v1.0 bridging header approach where `io_object_t` is `mach_port_t`.

---

### 3. Polling Interval Change (30s → 10s)

**Change required:** One line in `TemperatureViewModel.swift`, line 112:
```swift
// Before
Timer.publish(every: 30, on: .main, in: .common)

// After
Timer.publish(every: 10, on: .main, in: .common)
```

**Stack impact:** None. `Timer.publish` with a 10s interval uses the same Combine pipeline already in place. No new frameworks, no new APIs.

**Battery / performance consideration:** At 10s polling, `ProcessInfo.thermalState` is called 6x per minute vs 2x. `ProcessInfo.thermalState` is a lightweight system property read — not a sensor query — so the CPU overhead is negligible. The thermal state itself changes infrequently; most polls return the same value. No concern at 10s intervals.

**Ring buffer capacity:** The existing `maxHistory = 120` entries now represents 20 minutes of history (120 × 10s) instead of 60 minutes (120 × 30s). This is an acceptable tradeoff for more responsive state updates. The constant can be adjusted separately if longer history is desired.

**Confidence:** HIGH — Timer.publish is a documented Combine API with no polling-rate restrictions. The performance assessment is based on the lightweight nature of ProcessInfo.thermalState (a cached kernel property, not a live sensor poll).

---

## Updated Dependency Surface

```
Xcode 26.4.1 (from Mac App Store)
  └── Swift 6.3 (bundled)
  └── iOS 26 SDK (bundled — target iOS 18.x minimum deployment)
  └── Swift Charts (bundled in iOS 16+ SDK)
  └── UserNotifications (bundled)
  └── IOKit (bundled; used via bridging header, entitlement-gated)

Dev tooling (v1.1 addition — TrollStore build path only):
  └── ldid (brew install ldid) — fake-signs binary with custom entitlements for TrollStore IPA
```

No new runtime frameworks. One new dev tool (ldid) required only for TrollStore distribution path.

---

## Alternatives Considered (v1.1)

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| App icon tooling | No tool — Xcode single-size | MakeAppIcon, Asset Catalog Creator | Xcode 14+ handles resizing natively; no external tool needed |
| TrollStore signing | ldid + Run Script phase | XcodeAnyTroll tweak | XcodeAnyTroll requires installing a tweak on the dev Mac and a jailbroken device; ldid is simpler and more portable |
| TrollStore signing | ldid + Run Script phase | Manual IPA repackage | Automating via Run Script is less error-prone than manual steps each build |
| Polling interval | 10s Timer.publish | 5s | 5s has no measurable benefit — thermalState changes slowly; 10s is responsive without unnecessary reads |
| Polling interval | 10s Timer.publish | thermalStateDidChangeNotification only (no timer) | Notification fires on change only; timer ensures UI stays live even when state is stable |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| App icon — single-size Xcode workflow | HIGH | Xcode 14+ default for new iOS projects; project's Contents.json already correct format |
| App icon — PNG requirements (no alpha, no rounded corners) | HIGH | Apple developer documentation + multiple corroborating sources |
| TrollStore iOS version ceiling (17.0 max) | HIGH | TrollStore GitHub README, CoreTrust CVE-2023-41991 patch confirmed in 17.0.1+ |
| TrollStore entitlement string | HIGH | Verified via leminlimez gist (primary source), corroborated by v1.0 research |
| IOKit key name ("Temperature") and value units (÷100 = °C) | HIGH | leminlimez gist + darwin-xnu IOPMPowerSource.h source |
| TrollStore Xcode build config (ldid + CODE_SIGNING_ALLOWED=NO) | MEDIUM | Community-documented via XcodeAnyTroll project; not in Apple official docs |
| 10s polling — performance acceptability | HIGH | ProcessInfo.thermalState is a cached property read; 10s is well within reasonable polling frequency |

---

## Sources

- [Get iOS Battery Info and Temperature (GitHub Gist, leminlimez)](https://gist.github.com/leminlimez/ed3e3ee3a287c503c5b834acdc0dfcdc) — `"Temperature"` key, `÷100` conversion, `systemgroup.com.apple.powerlog` entitlement string
- [apple/darwin-xnu IOPMPowerSource.h](https://github.com/apple/darwin-xnu/blob/main/iokit/IOKit/pwr_mgt/IOPMPowerSource.h) — kernel-level source for IOPMPowerSource property keys
- [TrollStore GitHub (opa334)](https://github.com/opa334/TrollStore) — iOS version support range, entitlement handling mechanism ("TrollStore will preserve entitlements when resigning")
- [TrollStore on iOS 17.0.1–26.2 (iDevice Central)](https://idevicecentral.com/tweaks/can-you-install-trollstore-on-ios-17-0-1-ios-18-3/) — confirms no support on iOS 17.0.1+
- [XcodeAnyTroll (Lessica)](https://github.com/Lessica/XcodeAnyTroll) — Xcode TrollStore build workflow: CODE_SIGNING_ALLOWED=NO + ldid Run Script
- [Xcode 14 Single Size App Icon (Use Your Loaf)](https://useyourloaf.com/blog/xcode-14-single-size-app-icon/) — single-size AppIcon workflow, iOS 12+ requirement
- [App Icon Generator no longer needed with Xcode 14 (SwiftLee)](https://www.avanderlee.com/xcode/replacing-app-icon-generators/) — confirms Xcode handles resizing; no third-party tool needed
- [Configuring your app icon (Apple Developer Documentation)](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) — official reference
- [ios.cfw.guide — Installing TrollStore](https://ios.cfw.guide/installing-trollstore/) — TrollStore supported version range confirmed
