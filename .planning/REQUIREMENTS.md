# Termostato — v1 Requirements

## v1 Requirements

### Display

- [ ] **DISP-01**: App displays current thermal state (Nominal / Fair / Serious / Critical) prominently with distinct color coding for each level
- [ ] **DISP-02**: App displays a session history step-chart of thermal state changes since the app was opened (in-memory only, not persisted)

### Alerts

- [x] **ALRT-01**: App requests notification permission from the user on first launch (graceful no-permission fallback)
- [x] **ALRT-02**: App fires a local notification when thermal state reaches Serious or Critical — includes cooldown to prevent repeat firing while state remains elevated
- [x] **ALRT-03**: Alerts fire via `thermalStateDidChangeNotification` so they work when the app is in the background (app not terminated)

### Installation

- [ ] **INST-01**: App targets iOS 18+ and is installable directly via Xcode sideload onto the owner's iPhone — no App Store submission required

---

## v2 (Deferred)

- State duration display ("Serious for 4 min") — useful but not core for v1
- "Back to Nominal" notification — nice quality-of-life, defer to v2
- Persistent history across sessions — adds complexity, not needed for personal use

---

## Out of Scope

- **Numeric °C / °F temperature reading** — requires private entitlement `systemgroup.com.apple.powerlog` which cannot be granted via standard Xcode sideloading on iOS 18+. Deferred indefinitely.
- **App Store distribution** — personal sideload only; App Store would block private API access anyway
- **APNs remote push notifications** — free Apple Developer account cannot carry `aps-environment` entitlement; local notifications (`UNUserNotificationCenter`) are the correct approach
- **Persistent cross-session history** — adds storage/migration complexity for zero core-value gain in v1
- **Battery health, network stats, CPU metrics** — out of scope; single-purpose thermal monitor

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INST-01 | Phase 1 | Pending |
| DISP-01 | Phase 2 | Pending |
| DISP-02 | Phase 2 | Pending |
| ALRT-01 | Phase 3 | Complete |
| ALRT-02 | Phase 3 | Complete |
| ALRT-03 | Phase 3 | Complete |
