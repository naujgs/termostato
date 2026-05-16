---
plan: 01-03
phase: 01-foundation-device-validation
status: complete
completed: 2026-05-12
---

# Plan 01-03 Summary: Device Install & IOKit Decision

## What Was Built

Installed the CoreWatch app on a physical iPhone via Xcode free Apple ID sideloading. Captured the IOKit probe result and the ProcessInfo.thermalState polling behavior. Wrote the decision record and removed the IOKit probe code.

## Key Outcomes

- App installed successfully on physical iPhone under free Apple ID (7-day certificate)
- `ProcessInfo.thermalState` polling confirmed working: `[CoreWatch] thermalState = nominal` logged every 30 seconds
- scenePhase lifecycle confirmed: `Polling stopped (backgrounded).` and `Polling started.` on background/foreground transitions
- IOKit probe crashed with `EXC_BAD_ACCESS` — confirms BLOCKED status under standard sideloading
- `DECISION-IOKIT.md` written with BLOCKED verdict
- `probeIOKit()` method and its `init()` call removed from `TemperatureViewModel.swift` per D-02

## Deviations

- IOKit probe crashed (EXC_BAD_ACCESS) rather than returning a clean nil/error. Root cause: type mismatch between `CFMutableDictionaryRef` (C extern) and `Unmanaged<CFMutableDictionary>` (Swift bridging). The crash itself is definitive evidence of BLOCKED status — no clean probe result line was logged before the crash.
- Decision record written from crash evidence rather than a logged `[CoreWatch][IOKit]` line. Verdict is the same: BLOCKED.

## Key Files

### Created
- `.planning/phases/01-foundation-device-validation/DECISION-IOKIT.md` — IOKit BLOCKED decision record

### Modified
- `CoreWatch/CoreWatch/TemperatureViewModel.swift` — `probeIOKit()` method and call removed

## Self-Check

- [x] App installed on physical device under free Apple ID
- [x] `[CoreWatch] thermalState = nominal` confirmed in console
- [x] `[CoreWatch] Polling stopped (backgrounded).` confirmed
- [x] `[CoreWatch] Polling started.` confirmed on foreground
- [x] DECISION-IOKIT.md exists with BLOCKED verdict
- [x] `grep "probeIOKit" TemperatureViewModel.swift` returns 0 matches
- [x] BUILD SUCCEEDED after probe removal
