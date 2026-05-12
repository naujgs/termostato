# Phase 2: Dashboard UI - Research

**Researched:** 2026-05-12
**Domain:** SwiftUI dashboard layout, Swift Charts step-chart, ring buffer, @Observable ViewModel extension
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Large pill/card badge at the top half of the screen. Full-width rounded rectangle with a color fill and the state name in large text. The badge must be glanceable — state visible before the user fully reads it.
- **D-02:** Step-chart fills the lower portion of the screen, below the badge. Badge dominates the upper area; chart is secondary but always visible.
- **D-03:** Chart type is a step-chart (discrete state levels, not a smooth line). Required by ROADMAP DISP-02.
- **D-04:** The chart is not scrollable — it always shows the full session window within its bounds. Old data shifts off the left edge as new readings arrive.
- **D-05:** Fixed-capacity ring buffer of **120 readings** (~60 minutes of history at the 30s polling interval). When capacity is reached, oldest entries are evicted.
- **D-06:** Ring buffer is session-only — resets to empty on cold launch. No persistence.
- **D-07:** App follows **system appearance** — standard iOS light/dark mode. Do NOT force dark mode. Four thermal-state colors (green/yellow/orange/red) must read clearly in both modes.
- **D-08:** Four distinct colors for the four thermal levels: Nominal → green, Fair → yellow, Serious → orange, Critical → red. Applied to both badge fill and chart line/area.

### Claude's Discretion

- Chart Y-axis labels — whether to show state names (Nominal/Fair/Serious/Critical) on the Y-axis or just color bands.
- Chart X-axis — whether to show a time axis or omit it.
- Exact typography, padding, and spacing.
- Animation behavior on new data points.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DISP-01 | App displays current thermal state (Nominal / Fair / Serious / Critical) prominently with distinct color coding for each level | Badge component pattern, Color mapping, SwiftUI RoundedRectangle |
| DISP-02 | App displays a session history step-chart of thermal state changes since the app was opened (in-memory only, not persisted) | Swift Charts LineMark + .stepEnd, ring buffer pattern, @Observable history array |

</phase_requirements>

---

## Summary

Phase 2 builds directly on the Phase 1 `TemperatureViewModel` and `ContentView` foundation. The work is entirely within two existing files: `TemperatureViewModel.swift` (add the `ThermalReading` struct and `history` ring buffer) and `ContentView.swift` (replace the placeholder `VStack` with the full dashboard layout).

The technology stack is exclusively Apple built-in: SwiftUI for layout, Swift Charts for the step-chart, Foundation for the data model. No third-party packages. All APIs are available on the iOS 18+ deployment target.

The most technically precise aspect of this phase is the per-step coloring of the chart. Swift Charts' `LineMark` with `.stepEnd` interpolation produces the correct discrete-step visual, but coloring each step segment by the thermal state of that reading requires using `foregroundStyle(by: .value(...))` mapped to a nominal category (the thermal state string), combined with `.chartForegroundStyleScale` to provide the explicit color mapping. An alternative — using `AreaMark` segments per contiguous run — is more complex and not needed here.

**Primary recommendation:** Implement `ThermalReading` with a `stateColor: Color` computed property, use `LineMark` + `.interpolationMethod(.stepEnd)` + `.foregroundStyle(by: .value("State", reading.stateName))`, and supply explicit color overrides via `.chartForegroundStyleScale(domain:range:)` on the `Chart` view. For the Y-axis, map the discrete Int (0–3) to state-name labels via a custom `AxisMarks` closure. Hide the X axis with `.chartXAxis(.hidden)`.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18 SDK (bundled) | Dashboard layout, badge, navigation | Project constraint — SwiftUI only, no UIKit |
| Swift Charts | iOS 16+ (bundled) | Step-chart of thermal state history | Zero dependency; `LineMark` + `.stepEnd` handles discrete state plot natively |
| Foundation | iOS 18 SDK (bundled) | Data model (`ProcessInfo.ThermalState`), timer | Already in use from Phase 1 |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SF Symbols | iOS 18 SDK (bundled) | Optional iconography | If a thermometer icon is added to the badge |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Swift Charts (built-in) | DGCharts | External SPM dependency for functionality already in SDK — no benefit |
| `Array` with `removeFirst` for ring buffer | Custom `CircularBuffer` struct | O(n) removeFirst is acceptable for 120 elements at 30s intervals (max 2 evictions/minute); custom struct adds complexity with no measurable gain at this scale |

**Installation:** No installation required — all libraries are bundled with Xcode 26.4.1 / iOS 18 SDK.

---

## Architecture Patterns

### Recommended Project Structure

```
Termostato/Termostato/
├── TemperatureViewModel.swift   # Add ThermalReading struct + history array (extend Phase 1)
├── ContentView.swift            # Replace placeholder with badge + chart dashboard
├── TermostatoApp.swift          # Unchanged
├── Termostato-Bridging-Header.h # Unchanged (Phase 1 IOKit artifact — leave or remove per Phase 1 cleanup)
└── Assets.xcassets              # Unchanged
```

No new files are needed for Phase 2. All changes land in exactly two existing Swift files.

### Pattern 1: ThermalReading Value Type

**What:** A lightweight `struct` capturing a thermal state snapshot at a point in time, used as the chart data element.

**When to use:** Add to `TemperatureViewModel.swift` before the class declaration.

```swift
// [ASSUMED] — pattern derived from Swift Charts documentation conventions
struct ThermalReading: Identifiable {
    let id = UUID()
    let timestamp: Date
    let state: ProcessInfo.ThermalState

    /// Integer Y-axis value for Swift Charts (Nominal=0, Fair=1, Serious=2, Critical=3)
    var yValue: Int {
        switch state {
        case .nominal:  return 0
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }

    /// Nominal name string used for foregroundStyle categorical mapping
    var stateName: String {
        switch state {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Nominal"
        }
    }
}
```

### Pattern 2: Ring Buffer via Array (120-entry cap)

**What:** A plain Swift `Array<ThermalReading>` capped at `maxHistory` entries. When the array is full, `removeFirst()` evicts the oldest entry before appending the new one. This is called from `updateThermalState()` on the ViewModel.

**Performance note:** `Array.removeFirst()` is O(n) because Swift arrays are contiguous in memory and shift all remaining elements. At 120 elements maximum, this is ~119 pointer-size moves per eviction — effectively free on any iOS device. A true circular buffer (with head/tail indices) is unnecessary at this scale. [ASSUMED — performance reasoning; no benchmark verified]

```swift
// Inside TemperatureViewModel, add:
private static let maxHistory = 120
private(set) var history: [ThermalReading] = []

// Inside updateThermalState(), after reading ProcessInfo.thermalState:
private func updateThermalState() {
    thermalState = ProcessInfo.processInfo.thermalState
    let reading = ThermalReading(timestamp: Date(), state: thermalState)
    if history.count >= Self.maxHistory {
        history.removeFirst()
    }
    history.append(reading)
    print("[Termostato] thermalState = \(thermalStateDescription)")
}
```

### Pattern 3: Badge Component

**What:** A full-width `RoundedRectangle` with color fill, housing `.largeTitle` bold text. Color and text map from `thermalState` on the ViewModel.

**When to use:** Top section of `ContentView.body`.

```swift
// [ASSUMED] — SwiftUI idiom for color-filled rounded rectangle
var badgeColor: Color {
    switch viewModel.thermalState {
    case .nominal:  return .green
    case .fair:     return .yellow
    case .serious:  return .orange
    case .critical: return .red
    @unknown default: return .green
    }
}

var badgeTextColor: Color {
    switch viewModel.thermalState {
    case .nominal, .fair: return .primary
    case .serious, .critical: return .white
    @unknown default: return .primary
    }
}

// In body:
RoundedRectangle(cornerRadius: 20)
    .fill(badgeColor)
    .overlay {
        Text(thermalStateLabel)
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundStyle(badgeTextColor)
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 100)
```

### Pattern 4: Step-Chart with Per-Step Color

**What:** A Swift Charts `Chart` view using `LineMark` with `.stepEnd` interpolation. Each reading's step is colored by its thermal state category via `foregroundStyle(by:)` + `.chartForegroundStyleScale`.

**Critical nuance:** `LineMark` connects consecutive points with the line segment colored by the source data point's category. With `.stepEnd`, the horizontal segment at a given Y level extends rightward until the next data point — giving the visual appearance of "the line stays at Nominal until it changes to Fair." This matches the step-chart requirement.

**Why `foregroundStyle(by:)` over direct `.foregroundStyle(color)`:** Passing a direct `Color` to `foregroundStyle` on a `LineMark` sets a uniform color for the entire line series, overriding per-point variation. Using `by:` with a nominal plottable value (the state name string) allows Swift Charts to manage per-segment color automatically. [VERIFIED: developer.apple.com/documentation/charts/chartcontent/foregroundstyle(by:)]

```swift
// [ASSUMED for exact syntax; pattern verified via multiple community sources]
Chart(viewModel.history) { reading in
    LineMark(
        x: .value("Time", reading.timestamp),
        y: .value("Level", reading.yValue)
    )
    .interpolationMethod(.stepEnd)
    .foregroundStyle(by: .value("State", reading.stateName))
}
.chartForegroundStyleScale([
    "Nominal":  Color.green,
    "Fair":     Color.yellow,
    "Serious":  Color.orange,
    "Critical": Color.red
])
.chartYScale(domain: 0...3)
.chartYAxis {
    AxisMarks(values: [0, 1, 2, 3]) { value in
        AxisGridLine()
        AxisValueLabel {
            switch value.as(Int.self) {
            case 0: Text("Nominal").font(.caption)
            case 1: Text("Fair").font(.caption)
            case 2: Text("Serious").font(.caption)
            case 3: Text("Critical").font(.caption)
            default: EmptyView()
            }
        }
    }
}
.chartXAxis(.hidden)
.frame(minHeight: 200)
.animation(.easeInOut(duration: 0.3), value: viewModel.history.count)
```

### Pattern 5: Empty State Guard

**What:** When `viewModel.history` is empty (cold launch before first poll), show placeholder text instead of rendering the `Chart` with an empty dataset. Swift Charts renders an empty chart frame with no data if given an empty array — technically valid but visually poor.

```swift
// [ASSUMED] — standard SwiftUI conditional view pattern
if viewModel.history.isEmpty {
    VStack {
        Text("Warming up...")
            .font(.headline)
        Text("Thermal data will appear here once the first reading arrives.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    .frame(minHeight: 200)
} else {
    // Chart view here
}
```

**In practice:** `startPolling()` calls `updateThermalState()` immediately on `.onAppear`, so the empty state is visible for less than one frame. The guard is a safety net.

### Anti-Patterns to Avoid

- **Forcing dark mode:** `ContentView` must NOT apply `.preferredColorScheme(.dark)`. D-07 explicitly requires system appearance.
- **Adding `@Published` or `ObservableObject`:** The project already uses `@Observable` from Phase 1. Do not mix observation systems.
- **Storing `timer` as a stored property across transitions:** Phase 1 established the cancel-and-recreate pattern (D-07). Do not change it.
- **Using `Array.append(contentsOf:)` in a loop to batch-add history:** History must be added one reading at a time in `updateThermalState()` to preserve the ring-buffer eviction semantics.
- **`LineMark` with `.lineStyle` for color:** `.lineStyle(StrokeStyle(...))` controls stroke width/dash, not color. Color requires `foregroundStyle`.
- **Persistent history:** D-06 is explicit — no `UserDefaults`, no `CoreData`, no `@AppStorage`. History is an in-memory array only.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Time-series step chart | Custom `Canvas`/`Path` step renderer | Swift Charts `LineMark` + `.stepEnd` | Handles axis scaling, animation, accessibility labels automatically |
| Per-category color mapping | Manual `switch` inside `foregroundStyle` | `.chartForegroundStyleScale([...])` | Swift Charts manages the mapping and produces a consistent legend |
| Discrete Y-axis labels | Custom `ZStack` overlay with `Text` labels | `chartYAxis { AxisMarks { AxisValueLabel } }` | Built-in axis layout handles alignment and Dynamic Type |
| Color-adaptive badge text | Custom `UIColor` luminance check | Hardcoded per-state rule (primary/white) | Only 4 states; runtime luminance check is overengineering |

---

## Common Pitfalls

### Pitfall 1: `@Observable` Array Pessimization

**What goes wrong:** Swift's `@Observable` macro tracks the entire array as a single observable property. Appending a single element triggers a full rediff of all observers, which for very large arrays can become quadratic. [CITED: forums.swift.org/t/observable-pessimizes-arrays/69508]

**Why it happens:** The macro wraps the array with willSet/didSet-like access tracking at the property level, not element level.

**How to avoid:** At 120 elements maximum, this is inconsequential. No mitigation needed. If the cap were 10,000+, you would consider `@Published` with `ObservableObject` or a custom wrapper.

**Warning signs:** UI jank when appending, but only visible at much larger array sizes than 120.

### Pitfall 2: `LineMark` Series Fragmentation

**What goes wrong:** If you use `foregroundStyle(by: .value("State", reading.stateName))` without also specifying `series:`, Swift Charts may draw a separate disconnected line segment for each unique state value, rather than one continuous connected line.

**Why it happens:** Swift Charts interprets different `foregroundStyle` categories as separate data series by default, and series are not automatically connected across category boundaries.

**How to avoid:** Add `.foregroundStyle(by: .value("State", reading.stateName))` but also explicitly set `series: .value("History", "all")` on the `LineMark` to force all points into one connected series. [ASSUMED — behavior reported in Apple Developer Forums thread 708816; verify during implementation]

```swift
LineMark(
    x: .value("Time", reading.timestamp),
    y: .value("Level", reading.yValue),
    series: .value("History", "all")   // <-- keeps line connected across state changes
)
.interpolationMethod(.stepEnd)
.foregroundStyle(by: .value("State", reading.stateName))
```

### Pitfall 3: Y-Axis Overflows at Chart Edges

**What goes wrong:** Without `chartYScale(domain: 0...3)`, Swift Charts auto-scales the Y axis with padding — the chart may show Y values below 0 or above 3, making the state levels appear to float in the middle of the chart.

**How to avoid:** Always pin the domain explicitly: `.chartYScale(domain: 0...3)`.

### Pitfall 4: `@MainActor` Mutation Outside Main Thread

**What goes wrong:** If `history.append(...)` is ever called from a background context (e.g., a `Task { }` block without actor hopping), Swift 6.3 strict concurrency will produce a compile error or, if unchecked, a data race.

**Why it happens:** The ViewModel is `@MainActor`-isolated, but closures inside `Task { }` blocks are not automatically on the main actor unless explicitly annotated.

**How to avoid:** `updateThermalState()` is already called from the `Timer.publish` sink, which runs on `.main` RunLoop. No issue in the existing pattern. If future code adds a `Task { }` that calls `updateThermalState()`, use `await MainActor.run { ... }`.

### Pitfall 5: Empty `Chart` Frame with No Data

**What goes wrong:** Passing an empty array to `Chart(data)` renders an empty frame with no axes or content — functionally blank and visually indistinguishable from a view that failed to render.

**How to avoid:** Guard with `if viewModel.history.isEmpty { /* empty state view */ } else { Chart(...) }` as described in Pattern 5 above.

---

## Code Examples

Verified patterns from official and community sources:

### stepEnd Interpolation (Confirmed Available)

```swift
// Source: appcoda.com/swiftui-line-charts — confirmed .stepEnd is a valid interpolation method
// Availability: iOS 16+ (Swift Charts introduction)
LineMark(
    x: .value("Time", reading.timestamp),
    y: .value("Level", reading.yValue)
)
.interpolationMethod(.stepEnd)
```

### Hide X Axis

```swift
// Source: Apple Developer Forums / community consensus
// .chartXAxis(.hidden) removes all X-axis ticks, labels, and gridlines
Chart { ... }
    .chartXAxis(.hidden)
```

### Custom Y-Axis Labels

```swift
// Source: appcoda.com — AxisMarks with custom AxisValueLabel content
Chart { ... }
    .chartYAxis {
        AxisMarks(values: [0, 1, 2, 3]) { value in
            AxisGridLine()
            AxisValueLabel {
                switch value.as(Int.self) {
                case 0: Text("Nominal").font(.caption)
                case 1: Text("Fair").font(.caption)
                case 2: Text("Serious").font(.caption)
                case 3: Text("Critical").font(.caption)
                default: EmptyView()
                }
            }
        }
    }
```

### Chart Animation on Data Change

```swift
// Source: [ASSUMED] — standard SwiftUI animation API applied to Chart
// Animates the chart whenever the history array size changes
Chart(viewModel.history) { ... }
    .animation(.easeInOut(duration: 0.3), value: viewModel.history.count)
```

### foregroundStyle by Category + Color Scale Override

```swift
// Source: developer.apple.com/documentation/charts/chartcontent/foregroundstyle(by:)
// + community verification (swiftwithmajid.com mark styling)
.foregroundStyle(by: .value("State", reading.stateName))
// Applied to Chart view:
.chartForegroundStyleScale([
    "Nominal":  Color.green,
    "Fair":     Color.yellow,
    "Serious":  Color.orange,
    "Critical": Color.red
])
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ObservableObject` + `@Published` | `@Observable` macro + `@MainActor` | Swift 5.9 / iOS 17 | Simpler syntax; no `$` binding needed for `@State` init |
| `UIKit` `UIViewController` | SwiftUI `View` | Long-standing; project enforces SwiftUI | Not applicable here |
| Custom `Canvas` step rendering | Swift Charts `LineMark` + `.stepEnd` | iOS 16 (Swift Charts introduction) | Zero custom path math needed |

**Deprecated/outdated:**
- `ObservableObject` / `@Published` combination: Still works, but `@Observable` is the modern approach and is already established in Phase 1. Do not revert.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Array.removeFirst()` at 120 elements is fast enough that no circular buffer optimization is needed | Architecture Patterns — Pattern 2 | Negligible; 120 is too small for measurable O(n) cost |
| A2 | `.animation(.easeInOut(duration: 0.3), value: viewModel.history.count)` is the correct attachment point for chart update animation | Code Examples | Animation may not fire, or may animate incorrectly; verify during implementation |
| A3 | `LineMark` with `foregroundStyle(by:)` requires `series:` parameter to stay connected across category changes | Common Pitfalls — Pitfall 2 | Without `series:`, chart may show disconnected segments per state; verify against Xcode Simulator |
| A4 | `chartForegroundStyleScale` accepts a `[String: Color]` dictionary literal directly | Code Examples | May require explicit type annotation or `PlottableValue` wrapping; verify against compiler |
| A5 | `AxisMarks(values: [0, 1, 2, 3])` with `Int` values works with a `chartYScale(domain: 0...3)` set | Code Examples | Axis labels may require `.chartYScale` type to match; verify during implementation |

---

## Open Questions

1. **`series:` parameter requirement for connected multi-color LineMark**
   - What we know: Apple Developer Forums discuss series fragmentation when using `foregroundStyle(by:)` on LineMark
   - What's unclear: Whether iOS 18 has changed this default behavior; exact `series:` parameter syntax for this use case
   - Recommendation: Test in Xcode Simulator immediately on first chart task. If connected: no `series:` needed. If fragmented: add `series: .value("History", "all")`.

2. **`chartForegroundStyleScale` dictionary type signature**
   - What we know: Community examples show dictionary-literal usage
   - What's unclear: Whether a `[String: Color]` literal works without explicit type annotation in Swift 6.3
   - Recommendation: If the compiler rejects the literal, wrap in an explicit `[(String, Color)]` array of tuples or use `.chartForegroundStyleScale(domain:range:)` with separate arrays.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 2 has no external dependencies beyond the Apple SDK already verified in Phase 1. All frameworks (SwiftUI, Swift Charts, Foundation) are bundled with Xcode 26.4.1 / iOS 18 SDK.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected — no XCTest target, no test schemes in project |
| Config file | None |
| Quick run command | N/A — manual Simulator/device verification |
| Full suite command | N/A |

**Note:** The Termostato project has no automated test target. `ProcessInfo.thermalState` and `ProcessInfo.thermalStateDidChangeNotification` cannot be injected in an XCTest host without a custom abstraction layer, which is out of scope for this phase. Validation is manual (Xcode Simulator + physical device).

### Phase Requirements — Test Map

| Req ID | Behavior | Test Type | Automated Command | Available |
|--------|----------|-----------|-------------------|-----------|
| DISP-01 | Badge displays correct state name and color for each of 4 levels | Manual visual | N/A | Manual |
| DISP-01 | Badge color is green/yellow/orange/red per state | Manual visual | N/A | Manual |
| DISP-02 | Step chart shows history since app open | Manual visual | N/A | Manual |
| DISP-02 | Chart does not scroll; old data shifts left | Manual visual | N/A | Manual |
| DISP-02 | History resets on cold launch | Manual: kill app, re-launch | N/A | Manual |

### Wave 0 Gaps

None for automated tests — no test target exists and none is in scope for this phase.

Manual verification checklist (to be confirmed at phase end):
- [ ] Simulator: all 4 badge states display correctly (simulate via mock or `@State` override in `#Preview`)
- [ ] Device: step chart updates on polling tick
- [ ] Device: 120-reading cap reached without crash
- [ ] Device: cold launch shows empty state then first reading within ~1 second

---

## Security Domain

Phase 2 is a display-only dashboard reading `ProcessInfo.thermalState` (public API) and rendering it via SwiftUI. No network calls, no user input, no authentication, no data persistence, no external services.

| ASVS Category | Applies | Notes |
|---------------|---------|-------|
| V2 Authentication | No | No auth in this phase |
| V3 Session Management | No | No session in this phase |
| V4 Access Control | No | Single-user personal app |
| V5 Input Validation | No | No user input; `ProcessInfo.thermalState` is a trusted system enum |
| V6 Cryptography | No | No secrets or sensitive data |

No security controls required for Phase 2.

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: `foregroundStyle(by:)` — https://developer.apple.com/documentation/charts/chartcontent/foregroundstyle(by:)
- WWDC22 "Swift Charts: Raise the bar" — https://developer.apple.com/videos/play/wwdc2022/10137/
- WWDC24 "Swift Charts: Vectorized and function plots" — https://developer.apple.com/videos/play/wwdc2024/10155/
- Phase 1 source files (`TemperatureViewModel.swift`, `ContentView.swift`) — confirmed @Observable/@MainActor patterns and existing integration points
- Phase 2 `02-CONTEXT.md` and `02-UI-SPEC.md` — locked decisions and visual contract

### Secondary (MEDIUM confidence)
- AppCoda SwiftUI Line Charts tutorial — confirmed `.interpolationMethod(.stepEnd)` syntax and `chartYAxis { AxisMarks { AxisValueLabel } }` pattern
- Swift with Majid "Mastering charts in SwiftUI. Mark styling." — confirmed `foregroundStyle(by:)` categorical color mapping
- Swift Forums "Observable pessimizes arrays" — https://forums.swift.org/t/observable-pessimizes-arrays/69508 — confirmed O(n) array tradeoff at small scale

### Tertiary (LOW confidence)
- Apple Developer Forums thread 708816 (SwiftCharts color management) — series fragmentation behavior with `foregroundStyle(by:)` — flagged as A3 assumption

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries are Apple built-in, previously verified in CLAUDE.md
- Architecture: HIGH — Pattern 1-3 are straightforward SwiftUI; Pattern 4 (per-step color) is MEDIUM due to `series:` open question
- Pitfalls: MEDIUM — core pitfalls verified by community sources; Pitfall 2 is LOW (single-source)

**Research date:** 2026-05-12
**Valid until:** 2026-06-12 (stable Apple framework APIs; Swift Charts axis API unlikely to change in point releases)
