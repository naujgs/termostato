# Milestones

## v1.2 Sensor Research & Data Expansion (Shipped: 2026-05-15)

**Phases completed:** 3 phases, 8 plans, 5 tasks

**Key accomplishments:**

- Mach API probe engine with 4 probe functions, 3-sample verdict sequencing, and a SwiftUI debug sheet triggered by long-pressing the app title
- All 4 Mach APIs (host_statistics, host_statistics64, task_info, task_threads) confirmed Accessible under free Apple ID sideload on iOS 18 — no graceful fallback needed
- MetricsViewModel with four nonisolated Mach calls polling every 5s via Task.detached, plus all four new Swift files registered in project.pbxproj
- ThermalView extracted from ContentView; CPUView and MemoryView created with metric cards for App CPU, System CPU, App Memory, Memory Used/Free
- ContentView replaced with pure TabView container owning both ViewModels — all 18 on-device verification points passed
- TabView selection made explicit via `@State private var selectedTab: Int = 0` + `TabView(selection: $selectedTab)` + `.tag(0/1/2)` on each tab, enabling SC5 on-device verification
- SC5 tab-persistence UAT passed on physical iOS 18 device — all 7 test steps confirmed, no metric resets or regressions observed
- All 6 v1.2 requirements marked satisfied; v1.2 milestone formally closed across ROADMAP.md, STATE.md, and PROJECT.md

---

## v1.1 Visual Improvements (Shipped: 2026-05-14)

**Phases completed:** 2 phases, 2 plans, 2 tasks

**Key accomplishments:**

- Polling cadence reduced from 30s to 10s and ring-buffer expanded from 120 to 360 entries, preserving the 60-minute history window at 3x higher resolution
- One-liner:

---

## v1.0 MVP (Shipped: 2026-05-12)

**Phases completed:** 3 phases, 6 plans, 6 tasks

**Key accomplishments:**

- One-liner:
- One-liner:
- SwiftUI dashboard with color-coded thermal-state badge and session-history step-chart using Swift Charts, backed by a 120-entry ring buffer — verified live on physical iPhone
- UserNotifications permission, cooldown-gated scheduling, and thermalStateDidChangeNotification background observer wired into TemperatureViewModel under Swift 6.3 strict concurrency
- One-liner:

---
