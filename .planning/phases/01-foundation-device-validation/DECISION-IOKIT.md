# IOKit Probe Decision Record

**Date observed:** 2026-05-12
**Device:** iPhone (iOS 18.x)
**Signing:** Free Apple ID personal team (7-day certificate)
**Xcode version:** 26.4.1

## Observed Result

The IOKit probe crashed with `EXC_BAD_ACCESS (code=1, address=0xadf1046)` inside `probeIOKit()` on the physical device under free Apple ID sideloading.

The crash occurred at the IOKit function call boundary — the Swift bridging layer produced a type mismatch between `CFMutableDictionaryRef` (C) and `Unmanaged<CFMutableDictionary>` (Swift), resulting in a bad memory access rather than a clean nil/error return. This confirms that IOKit's `IOPMPowerSource` registry path is not accessible via standard sideloading: the AMFI sandbox prevents the call from executing safely, and the function signatures diverge from what the public iOS SDK exposes.

## Decision

**BLOCKED:** IOKit `IOPMPowerSource` Temperature key is not accessible under free Apple ID sideloading.
AMFI enforces the `systemgroup.com.apple.powerlog` entitlement requirement at runtime.
The app will display thermal state via `ProcessInfo.thermalState` only.
Numeric °C display is confirmed Out of Scope for v1.

## Impact on Architecture

- `TemperatureViewModel` continues with `ProcessInfo.thermalState` as the sole data source.
- No fallback "—°C" UI needed; the app displays thermal state levels only.
- Phase 2 and Phase 3 proceed as planned.
- The bridging header and `IOKit.framework` link remain in the project (harmless) but the probe Swift code has been deleted per D-02.
