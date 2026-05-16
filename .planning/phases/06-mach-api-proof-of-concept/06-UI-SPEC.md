---
phase: 6
slug: mach-api-proof-of-concept
status: draft
shadcn_initialized: false
preset: none
created: 2026-05-15
revised: 2026-05-15
---

# Phase 6 — UI Design Contract

> Visual and interaction contract for the Mach API debug probe sheet. This is throwaway validation UI (D-04, D-05) — it will not ship to end users. The contract is intentionally minimal but prescriptive enough for consistent implementation.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (native SwiftUI) |
| Preset | not applicable |
| Component library | SwiftUI built-in |
| Icon library | SF Symbols (system) |
| Font | San Francisco (system default) |

---

## Spacing Scale

Declared values (must be multiples of 4):

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4pt | Inline padding between icon and label in verdict rows |
| sm | 8pt | Vertical gap between verdict rows |
| md | 16pt | Horizontal sheet padding, section padding |
| lg | 24pt | Gap between header area and verdict list |
| xl | 32pt | Gap between verdict list and action button |

Exceptions: none. Sheet is a simple vertical layout — only xs through xl needed.

---

## Typography

Two weights only: semibold (600) for titles and badges, regular (400) for body and detail text.

| Role | Size | Weight | Line Height | SwiftUI Modifier |
|------|------|--------|-------------|-----------------|
| Sheet title | 20pt | semibold (600) | 1.2 | `.font(.title3).fontWeight(.semibold)` |
| API name label | 17pt | semibold (600) | 1.3 | `.font(.headline)` |
| Verdict badge text | 13pt | semibold (600) | 1.0 | `.font(.caption).fontWeight(.semibold)` |
| Detail text (kern_return_t, raw values) | 13pt | regular (400) | 1.4 | `.font(.caption)` |
| Progress label ("Sample 2 of 3") | 13pt | regular (400) | 1.4 | `.font(.caption)` |

Rationale for badge text at 13pt semibold: The colored pill background provides the primary visual distinction for verdict badges, not font size. Using 13pt semibold differentiates badges from 13pt regular detail text through weight alone, while maintaining clear separation from the 17pt API name labels above. The previous 15pt was only 2pt from 17pt — an imperceptible difference at the same weight.

---

## Color

This phase uses iOS semantic colors exclusively. No custom hex values — the debug sheet must respect system light/dark mode automatically.

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `Color(.systemBackground)` | Sheet background |
| Secondary (30%) | `Color(.secondarySystemBackground)` | Verdict row cards |
| Accent — Accessible | `Color.green` | Verdict badge fill for "Accessible" status |
| Accent — Degraded | `Color.yellow` | Verdict badge fill for "Degraded" status |
| Accent — Blocked | `Color.red` | Verdict badge fill for "Blocked" status |
| Neutral | `Color(.secondaryLabel)` | Detail text (kern_return_t values, timestamps, raw data) |
| In-progress | `Color(.tertiaryLabel)` | Verdict row before probe completes |

Accent reserved for: verdict status badges only — green/yellow/red map directly to the three-tier classification from D-06.

### Badge Text Color Rules

| Badge Fill | Text Color | Reason |
|------------|------------|--------|
| Green (Accessible) | `.primary` | Dark text on light fill for readability |
| Yellow (Degraded) | `.primary` | Dark text on light fill for readability |
| Red (Blocked) | `.white` | White text on saturated fill (matches existing thermal badge pattern) |

---

## Visual Focal Point

The **verdict badge row list** is the primary visual anchor of the debug sheet. The four color-coded verdict cards are what the developer scans first after a probe completes. The executor must ensure:

- Verdict rows receive the most visual weight (card backgrounds, colored pill badges, data density).
- The "Run Probe" button is visually subordinate — standard `.borderedProminent` is sufficient but must not compete with the verdict row area.
- The sheet title "Mach API Probe" is a static label, not a focal point. It orients the user but does not draw the eye.

---

## Component Inventory

### 1. Debug Sheet Trigger (D-05)

- **Gesture:** Long press on "CoreWatch" title text in ContentView
- **Duration:** System default long press (0.5s)
- **Feedback:** System haptic on activation (`.sensoryFeedback(.impact, trigger:)`)
- **No visible affordance** — this is intentionally hidden throwaway UI

### 2. MachProbeDebugView (Sheet)

- **Presentation:** `.sheet(isPresented:)` modifier on ContentView
- **Dismiss:** Standard iOS sheet drag-to-dismiss + "Done" button top-trailing
- **Layout:** Single `VStack` with:
  1. Sheet title: "Mach API Probe"
  2. Progress indicator: "Sample {n} of 3" with `ProgressView` (linear, determinate)
  3. Verdict list: 4 rows (one per API) — **this is the focal point of the sheet**
  4. "Run Probe" button (bottom)

### 3. Verdict Row (repeated 4x)

One row per API probe. Each row is a rounded rectangle card containing:

| Element | Position | Content |
|---------|----------|---------|
| API name | Top-left | e.g. "host_statistics (CPU)" |
| Verdict badge | Top-right | Pill shape: "Accessible" / "Degraded" / "Blocked" / "Pending" |
| kern_return_t | Below name, left | e.g. "kern_return_t: 0 (KERN_SUCCESS)" |
| Raw data summary | Below kern_return_t | e.g. "user: 12345, system: 6789, idle: 98765, nice: 0" |
| Timestamp | Bottom-right | e.g. "14:32:05" (HH:mm:ss format) |

**Card styling:**
- Background: `Color(.secondarySystemBackground)`
- Corner radius: 12pt
- Padding: 16pt all sides
- Vertical gap between cards: 8pt

### 4. Verdict Badge (Pill)

- Shape: `Capsule()` with horizontal padding 12pt, vertical padding 4pt
- Fill: verdict color (green/yellow/red) or `Color(.tertiarySystemFill)` for "Pending"
- Text: verdict label in 13pt semibold (600)
- Text color: per Badge Text Color Rules above

### 5. Run Probe Button

- **Label:** "Run Probe"
- **Style:** `.buttonStyle(.borderedProminent)` (system accent blue)
- **State during probe:** Disabled, label changes to "Probing..." with `ProgressView()` spinner
- **State after completion:** Re-enabled, label returns to "Run Probe" for re-run capability

### 6. Progress Indicator

- **Type:** `ProgressView(value: samplesCompleted, total: 3)` — linear determinate bar
- **Label:** "Sample {n} of 3"
- **Hidden when:** Probe has not started or probe is complete

---

## States

### Sheet States

| State | What User Sees |
|-------|---------------|
| Initial (no probe run) | 4 verdict rows all showing "Pending" badge in gray. "Run Probe" button enabled. No progress bar. |
| Probing (in progress) | Progress bar visible. Completed rows update with verdict badge + data. Remaining rows stay "Pending". Button disabled showing "Probing..." |
| Complete | All 4 rows show final verdict. Progress bar hidden. "Run Probe" re-enabled for re-run. |
| Error (unexpected) | If probe throws, show inline text below the row: "Error: {description}" in `.caption` red text. |

### Verdict Row States

| State | Badge | Detail Text | Timestamp |
|-------|-------|-------------|-----------|
| Pending | Gray pill "Pending" | Em dash "---" | Em dash "---" |
| Accessible | Green pill "Accessible" | kern_return_t + raw data values | HH:mm:ss |
| Degraded | Yellow pill "Degraded" | kern_return_t + raw data (zeroed values noted) | HH:mm:ss |
| Blocked | Red pill "Blocked" | kern_return_t error code | HH:mm:ss |

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Sheet title | "Mach API Probe" |
| Primary CTA | "Run Probe" |
| CTA disabled state | "Probing..." |
| Progress label | "Sample {n} of 3" |
| Pending badge | "Pending" |
| Accessible badge | "Accessible" |
| Degraded badge | "Degraded" |
| Blocked badge | "Blocked" |
| Empty state (before first probe) | No separate empty state — rows show "Pending" badges |
| Error inline | "Error: {system error description}" |
| Done button | "Done" |
| API row labels | "host_statistics (CPU)", "host_statistics64 (Memory)", "task_info (Process Memory)", "task_threads (Process CPU)" |

---

## Interaction Contract

| Interaction | Behavior |
|-------------|----------|
| Long press title | Opens debug sheet with haptic feedback |
| Tap "Run Probe" | Starts 3-sample probe sequence at 10s intervals (D-07). Button disables. Progress bar appears. |
| Tap "Done" | Dismisses sheet. Probe stops if in progress. |
| Drag sheet down | Standard iOS dismiss. Probe stops if in progress. |
| Tap "Run Probe" after completion | Clears previous results, re-runs full 3-sample sequence |
| Background app during probe | Probe pauses (Timer invalidated per existing pattern). Sheet state preserved. |

---

## Accessibility

| Element | Accessibility Treatment |
|---------|------------------------|
| Verdict badge | `accessibilityLabel("{API name}: {verdict}")` e.g. "host_statistics CPU: Accessible" |
| Run Probe button | Standard button semantics (automatic) |
| Progress bar | `accessibilityLabel("Probe progress: sample {n} of 3")` |
| Detail text | `accessibilityElement(children: .combine)` on each verdict row card |
| Long press trigger | No accessibility alternative needed — this is throwaway debug UI |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| Not applicable | N/A | N/A — native SwiftUI, no component registry |

---

## Scope Notes

This UI contract covers **throwaway debug UI only**. Per D-04 and D-05:
- The debug sheet is temporary Phase 6 validation UI
- It will be removed or hidden before Phase 8 ships the final TabView dashboard
- Visual polish is not a priority — clarity of probe results is the only goal
- No design system tokens are established by this phase for downstream reuse

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
