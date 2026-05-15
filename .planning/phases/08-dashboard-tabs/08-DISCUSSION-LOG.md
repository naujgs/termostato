# Phase 8: Dashboard Tabs - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 08-dashboard-tabs
**Areas discussed:** Phase scope, UI polish / Phase 9 seed, Tab persistence (SC5), Requirements cleanup

---

## Phase Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Implement the designs | Phase 8 is a UI implementation phase — apply Claude Design mockups on top of Phase 7 scaffold | |
| Verify + close out | Phase 7 is essentially done. Phase 8: SC5 verification, mark requirements complete, update docs | ✓ |
| Both equally | UI redesign + formal requirement close-out | |

**User's choice:** Verify + close out. And define a little spoiler for Phase 9 (implement the Claude Design mockups).

**Notes:** User has Claude Design mockups for a full visual redesign of all 3 tabs. Phase 8 closes out v1.2; Phase 9 implements the designs.

---

## UI Polish / Phase 9 Seed

| Option | Description | Selected |
|--------|-------------|----------|
| All 3 tabs redesigned | Thermal, CPU, and Memory tabs all get a visual overhaul | ✓ |
| CPU + Memory only | Thermal tab stays; CPU and Memory get redesigned | |
| Full app refresh | Navigation, colors, typography, card layout, and app structure | |

**User's choice:** All 3 tabs redesigned in Phase 9.

**Notes:** Claude Design mockups exist and cover all 3 tabs. Phase 9 will implement them.

---

## Tab Persistence (SC5)

| Option | Description | Selected |
|--------|-------------|----------|
| On-device UAT only | No code changes — architecture already satisfies SC5. Verify on device. | |
| Add @State selectedTab + verify | Explicitly bind TabView selection to @State var, then UAT on device | ✓ |

**User's choice:** Add `@State selectedTab` binding to ContentView and verify on device.

**Notes:** Makes persistence explicit and observable. Satisfies SC5 with both a code artifact and a UAT step.

---

## Requirements Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Mark all done in Phase 8 | Tick all 6 v1.2 requirements, update traceability, mark v1.2 milestone complete | ✓ |
| Update traceability only | Correct Phase columns but leave status for milestone-complete step | |

**User's choice:** Mark all 6 requirements done in Phase 8 and fully close out v1.2.

**Notes:** REQUIREMENTS.md, ROADMAP.md, PROJECT.md, and STATE.md all need updates.

---

## Claude's Discretion

- Exact `selectedTab` integer tag values for each tab
- Whether to use explicit `.tag()` modifiers or leave implicit ordering
- Commit message wording for documentation updates

## Deferred Ideas

- Phase 9: Claude Design UI redesign (all 3 tabs — Thermal, CPU, Memory)
- Rolling history charts for CPU/Memory (v1.3+)
- Battery display (v1.3+)
