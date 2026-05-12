# Phase 2: Dashboard UI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 02-dashboard-ui
**Areas discussed:** Screen layout, Ring buffer size, Visual theme

---

## Screen Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Badge top, chart below | Prominent state badge in upper portion; chart fills lower half. Glanceable at a glance — state first, trend second. | ✓ |
| Chart dominates, badge as header | Chart takes 2/3+ of screen; small badge row at top. | |
| Full-screen color wash + chart | Whole screen background changes to state color; chart rendered on top as overlay. | |

**User's choice:** Badge top, chart below

---

### Badge size (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Large pill / card | Full-width rounded rectangle with state name in large text and color fill. Hard to miss. | ✓ |
| Centered label + color dot | State name in big font with a colored dot beside it. More minimal. | |
| You decide | Claude picks size and style based on glanceability goals. | |

**User's choice:** Large pill / card

---

## Ring Buffer Size

| Option | Description | Selected |
|--------|-------------|----------|
| 120 readings (~60 min) | Full hour of history at 30s polling. Good for extended sessions. | ✓ |
| 60 readings (~30 min) | Half-hour of history. Natural sweet spot. | |
| 20 readings (~10 min) | Tight recent window. | |
| You decide | Claude picks based on chart readability. | |

**User's choice:** 120 readings (~60 min)

---

## Visual Theme

| Option | Description | Selected |
|--------|-------------|----------|
| Always dark | Dark background always. Monitoring/dashboard feel. | |
| Follows system appearance | Standard iOS behavior — light or dark based on device setting. | ✓ |

**User's choice:** Follows system appearance

---

## Claude's Discretion

- Chart Y-axis label style — state names vs. color bands vs. none
- Chart X-axis presence and time tick marks
- Exact typography, padding, and spacing
- Animation behavior on chart updates

## Deferred Ideas

None.
