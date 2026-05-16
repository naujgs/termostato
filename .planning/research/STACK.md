# Technology Stack

**Project:** CoreWatch
**Researched:** 2026-05-14 (v1.2 update — CPU usage, memory, battery APIs for iOS 18 free sideload)
**Mode:** Ecosystem / Feasibility

---

## Established Stack (v1.1 — Do Not Change)

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

## v1.2 New Data Sources — Verdict by API

This section answers: what is accessible, what is blocked, and why, under **free Apple ID sideload on iOS 18**.

The constraint that governs all answers: AMFI enforces the sandbox profile. Standard free Apple ID sideloading gives apps the standard `container.sb` sandbox with the entitlements Apple's provisioning portal grants to free-tier development certificates. Any API requiring a private Apple entitlement (`com.apple.*` or `systemgroup.*`) is blocked. Public SDK APIs require no special entitlements and work normally.

---

### API 1: `UIDevice.current.batteryLevel` / `batteryState`

**Verdict: ACCESSIBLE**
**Confidence: HIGH**

`UIDevice.batteryLevel` and `UIDevice.batteryState` are public UIKit APIs. They require no entitlements. They are available to all iOS apps including App Store apps, meaning they are unambiguously sandbox-safe. The only activation requirement is setting `UIDevice.current.isBatteryMonitoringEnabled = true` before reading; without it, `batteryLevel` returns `-1.0` and `batteryState` returns `.unknown`.

**Why it works under free sideload:** These properties are in the public iOS SDK. Free sideloading gives the app the same public API surface as an App Store app. No private entitlement gates this API.

**What it provides:**
- `batteryLevel`: Float from `0.0` (empty) to `1.0` (full). Returns `-1.0` if monitoring not enabled.
- `batteryState`: Enum — `.unknown`, `.unplugged`, `.charging`, `.full`

**What it does NOT provide:** Battery health percentage, cycle count, temperature, voltage, current draw. Those fields are IOKit private territory, blocked by AMFI.

**Implementation pattern:**
```swift
// In init or onAppear — enable once
UIDevice.current.isBatteryMonitoringEnabled = true

// Read in polling loop
let level = UIDevice.current.batteryLevel   // e.g. 0.83 → "83%"
let state = UIDevice.current.batteryState   // .charging, .unplugged, etc.
```

**Notification-based updates (optional):**
```swift
NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, ...)
NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, ...)
```
Both require `isBatteryMonitoringEnabled = true`.

---

### API 2: `mach_task_basic_info` / `task_vm_info` — App's own memory footprint

**Verdict: ACCESSIBLE (own process only)**
**Confidence: HIGH**

`task_info(mach_task_self_, ...)` is callable for an app's own process without any special entitlement. The key distinction: `mach_task_self_` gives the app a port to its own task — no `task_for_pid()` is needed, which is the sandboxed operation. Apple's own documentation and WWDC sessions confirm that `phys_footprint` from `TASK_VM_INFO` is how Xcode's memory gauge measures app memory.

**Why it works under free sideload:** Accessing your own task port is always permitted. `task_for_pid()` on another process's PID is what the sandbox blocks. Using `mach_task_self_` is equivalent to `getpid()` — the kernel grants this by design.

**Two flavors — use `TASK_VM_INFO` for accuracy:**

`MACH_TASK_BASIC_INFO` gives `resident_size`, which is less accurate because it includes shared memory pages that the system can reclaim. Apple's preferred metric is `phys_footprint` from `TASK_VM_INFO`, which is what Xcode's Memory Report and Instruments use. It matches what counts against the app's memory budget.

**Implementation pattern:**
```swift
import Darwin

func appMemoryFootprint() -> UInt64? {
    var info = task_vm_info_data_t()
    // TASK_VM_INFO_COUNT is too complex for Swift C importer — compute manually
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return info.phys_footprint  // bytes; divide by 1_048_576 for MB
}
```

**Also available — total device RAM:**
```swift
ProcessInfo.processInfo.physicalMemory  // UInt64, total RAM in bytes
```
`ProcessInfo.physicalMemory` is a public Foundation API, no entitlement needed.

**What this provides:** The app's own memory footprint in bytes. Not system-wide memory pressure — just this app's physical memory usage.

---

### API 3: `host_cpu_load_info` / `host_statistics` — System-wide CPU

**Verdict: UNCERTAIN — Probably inaccessible from sandbox, use thread-level alternative**
**Confidence: MEDIUM (LOW for sandbox accessibility claim)**

`host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ...)` reads system-wide CPU tick counters across all processes. Apple's sandbox philosophy explicitly states that apps should only be able to get information about themselves, not the system as a whole. Apple Developer Forum posts from multiple engineers note that "it's not hard to imagine Mach host APIs running afoul of the sandbox at some point in the future" — suggesting the intent is to restrict these, even if enforcement is inconsistent across iOS versions.

**Risk:** There is no definitive Apple documentation confirming `host_statistics` is whitelisted in `container.sb`. MacOS SystemKit (which uses this API) is macOS-targeted and works in a less restricted environment. Relying on `host_cpu_load_info` for a sideloaded iOS app creates fragility risk — it may silently fail or be tightened in future iOS point releases.

**The safer alternative: thread-level CPU for this process only**

`task_threads(mach_task_self_, ...)` + `thread_info(..., THREAD_BASIC_INFO, ...)` reads CPU usage for all threads in your own process. This is the same mechanism that Xcode's CPU gauge uses to show per-process CPU %. It gives CPU % consumed by the CoreWatch app, not total device CPU — which is arguably more relevant for a self-monitoring tool.

**Implementation pattern (own-process CPU %):**
```swift
import Darwin

func appCPUUsage() -> Double {
    var threadList: thread_act_array_t?
    var threadCount: mach_msg_type_number_t = 0
    guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
          let threads = threadList else { return 0 }
    defer {
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: threads),
            vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
        )
    }

    var totalUsage: Double = 0
    for i in 0..<Int(threadCount) {
        var info = thread_basic_info()
        var infoCount = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
            }
        }
        if result == KERN_SUCCESS {
            let threadInfo = info
            if threadInfo.flags & TH_FLAGS_IDLE == 0 {
                totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)
            }
        }
    }
    return totalUsage * 100  // percentage; can exceed 100% on multi-core devices
}
```

**If system-wide CPU is required:** The app should attempt `host_statistics` and gracefully handle failure (return `nil`). If the call fails on the target iOS 18 device, fall back to own-process CPU or omit the metric. Do not assume it will succeed.

---

### API 4: `sysctl` — Device info and memory

**Verdict: PARTIALLY ACCESSIBLE**
**Confidence: HIGH (for listed keys), MEDIUM (for process-list keys)**

`sysctl` is a broad interface — some keys are accessible from sandbox, others are blocked. Apple's sandbox blocks process enumeration (`CTL_KERN, KERN_PROC`) as of iOS 9. However, hardware info keys work fine.

**Accessible from sandbox (confirmed by multiple sources):**

| Key | Value | Notes |
|-----|-------|-------|
| `hw.physmem` / `hw.memsize` | Total device RAM in bytes | Same as `ProcessInfo.physicalMemory` |
| `hw.ncpu` | CPU core count | Logical cores |
| `hw.machine` | Device model string (e.g. `iPhone14,2`) | |
| `kern.osversion` | iOS build number | |

**Blocked from sandbox:**
- `CTL_KERN, KERN_PROC` — process listing — explicitly blocked since iOS 9
- Process-specific info for other PIDs

**Bottom line for v1.2:** `ProcessInfo.processInfo.physicalMemory` (Foundation) and `ProcessInfo.processInfo.processorCount` (Foundation) already surface the most useful `sysctl` values without the `sysctl` ceremony. Use Foundation APIs instead.

---

### API 5: `IOPSCopyPowerSourcesInfo` — Battery data via IOKit

**Verdict: BLOCKED**
**Confidence: HIGH**

`IOPSCopyPowerSourcesInfo` is part of IOKit's power source subsystem. On iOS, IOKit was added to the public SDK in iOS 16, but its scope is limited: the public iOS IOKit API exists solely to support apps that contain DriverKit extensions (system-level driver code), not for general power source querying. The `IOPowerSources` functions (`IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`) are macOS APIs. Apple removed battery data access via IOKit from iOS in iOS 10 (confirmed via MacRumors developer forum discussion from that period). Under free sideload, there is no entitlement path to access these functions even if headers can be imported.

**What to use instead:** `UIDevice.current.batteryLevel` + `batteryState` (API 1, above).

---

### API 6: `MTLDevice.currentAllocatedSize` — GPU memory usage

**Verdict: ACCESSIBLE but scope is GPU memory only, not GPU utilization %**
**Confidence: MEDIUM**

`MTLDevice.currentAllocatedSize` is a public Metal API property that reports the total bytes of GPU memory currently allocated by all Metal resources created by the app (buffers, textures, heaps). It is available on iOS and does not require entitlements. However:

- It measures **GPU memory allocated by this app's Metal objects**, not GPU compute utilization %.
- For CoreWatch (a SwiftUI dashboard with no Metal rendering), this value will be near-zero and meaningless — the app creates no Metal resources.
- There is no public iOS API to read GPU utilization % at runtime from an arbitrary app. GPU profiling (via Metal Performance Counters and Instruments) is a development-time tool, not a runtime API.

**Conclusion for v1.2:** GPU utilization % is not obtainable via public APIs. `MTLDevice.currentAllocatedSize` is technically accessible but useless for CoreWatch's use case. Do not implement.

---

## v1.2 Recommended New APIs — Summary

| API | Framework | Accessible? | Entitlement Required? | What It Provides |
|-----|-----------|-------------|----------------------|-----------------|
| `UIDevice.batteryLevel` | UIKit | YES | None | Battery % (0.0–1.0) |
| `UIDevice.batteryState` | UIKit | YES | None | Charging/Unplugged/Full |
| `task_info(mach_task_self_, TASK_VM_INFO)` | Darwin/Mach | YES | None | App memory footprint (bytes) |
| `ProcessInfo.physicalMemory` | Foundation | YES | None | Total device RAM (bytes) |
| `task_threads` + `thread_info(THREAD_BASIC_INFO)` | Darwin/Mach | YES (own process) | None | App CPU usage % |
| `host_statistics(HOST_CPU_LOAD_INFO)` | Darwin/Mach | UNCERTAIN | Likely required | System-wide CPU % |
| `IOPSCopyPowerSourcesInfo` | IOKit | NO | Private, blocked | (Battery detail — macOS only) |
| `MTLDevice.currentAllocatedSize` | Metal | YES | None | GPU memory (useless for this app) |
| GPU utilization % | — | NO | N/A | No public API exists |

---

## v1.2 Stack Additions

No new frameworks are required. The new APIs are in frameworks already in use:

| New API | Framework Already in Stack | Notes |
|---------|---------------------------|-------|
| `UIDevice.batteryLevel/batteryState` | UIKit (already imported by SwiftUI) | Needs `isBatteryMonitoringEnabled = true` in init |
| `task_info(TASK_VM_INFO)` | Darwin (available via Foundation import) | Swift C importer limitation for `TASK_VM_INFO_COUNT` — compute count manually |
| `task_threads` + `thread_info(THREAD_BASIC_INFO)` | Darwin | Requires `vm_deallocate` for thread list cleanup |
| `ProcessInfo.physicalMemory` | Foundation | Already imported; zero changes needed |

**No new imports, no new frameworks, no new dependencies.**

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `host_statistics(HOST_CPU_LOAD_INFO)` for system-wide CPU | Likely blocked by iOS sandbox; fragile across iOS versions; philosophy violation | `task_threads` + `thread_info` for own-process CPU |
| `IOPSCopyPowerSourcesInfo` | macOS API; removed from iOS since iOS 10; blocked by AMFI under free sideload | `UIDevice.batteryLevel` + `batteryState` |
| `task_for_pid()` on any PID ≠ own process | Explicitly blocked in iOS sandbox for sandboxed apps | Not applicable — only need own-process data |
| `MTLDevice.currentAllocatedSize` | GPU memory only; near-zero for a non-Metal UI app; not GPU utilization % | N/A — omit GPU entirely |
| Any `IOPMPowerSource` IOKit key | Requires `systemgroup.com.apple.powerlog` private entitlement; AMFI blocks under free sideload | `UIDevice.batteryState` for charging state |
| `BGAppRefreshTask` / `BGProcessingTask` for periodic sensor reads | System-discretionary scheduling; unsuitable for real-time monitoring | Timer-based polling while foregrounded |

---

## Updated Dependency Surface (v1.2)

```
Xcode 26.4.1 (from Mac App Store)
  └── Swift 6.3 (bundled)
  └── iOS 26 SDK (bundled — target iOS 18.x minimum deployment)
  └── SwiftUI (bundled)
  └── Swift Charts (bundled in iOS 16+ SDK)
  └── Foundation (bundled) — ProcessInfo.thermalState, physicalMemory, timers
  └── UIKit (bundled, via SwiftUI) — UIDevice.batteryLevel, batteryState
  └── Darwin / libSystem (bundled) — task_info, task_threads, thread_info (Mach APIs)
  └── UserNotifications (bundled)
  └── IOKit (bundled via bridging header — entitlement-gated, no new uses in v1.2)

Dev tooling: no change from v1.1
```

No new runtime frameworks. No SPM, no CocoaPods, no Carthage.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| `UIDevice.batteryLevel/batteryState` — accessible under free sideload | HIGH | Public UIKit API; no entitlement required; universally documented; App Store safe |
| `task_info(TASK_VM_INFO)` for app memory footprint — accessible | HIGH | Apple Developer Forums confirm; `phys_footprint` is how Xcode's memory gauge works; own-process access requires no entitlement |
| `task_threads` + `thread_info(THREAD_BASIC_INFO)` for app CPU — accessible | MEDIUM-HIGH | Community implementations confirm; Apple forums confirm `task_for_pid` is blocked but own process is allowed; no definitive Apple doc confirming the exact entitlement boundary |
| `host_statistics(HOST_CPU_LOAD_INFO)` blocked in iOS sandbox | MEDIUM | Apple engineers warn sandbox may restrict this; philosophy is apps see only themselves; no definitive test result found, but risk is documented |
| `IOPSCopyPowerSourcesInfo` blocked on iOS | HIGH | macOS-only API; iOS 10 removed battery IOKit detail access; no available entitlement path under free sideload |
| GPU utilization % — no public API | HIGH | No public API exists; Metal Performance Counters are development-time only |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| App memory | `task_info(TASK_VM_INFO).phys_footprint` | `MACH_TASK_BASIC_INFO.resident_size` | `resident_size` includes shared pages not charged to app; less accurate than `phys_footprint` |
| App CPU | `task_threads` + `thread_info(THREAD_BASIC_INFO)` | `host_statistics(HOST_CPU_LOAD_INFO)` | `host_statistics` requires system-wide host access likely restricted by sandbox; own-thread approach is sandbox-safe and gives app-specific data |
| Battery level | `UIDevice.batteryLevel` | `IOPSCopyPowerSourcesInfo` | IOKit power sources API is macOS-only; blocked by AMFI on iOS under free sideload |
| Total RAM | `ProcessInfo.physicalMemory` | `sysctl hw.memsize` | Foundation property is simpler and already imported; identical data |

---

## Sources

- [UIDevice.batteryLevel — Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uidevice/batterylevel) — public API, no entitlement documented
- [UIDevice.BatteryState — Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uidevice/batterystate) — public API
- [how to overall cpu utilization of iphone device — Apple Developer Forums (thread/11393)](https://developer.apple.com/forums/thread/11393) — confirms sandbox philosophy: apps see themselves only; host APIs may be restricted
- [Obtaining CPU usage by process — Apple Developer Forums (thread/655349)](https://developer.apple.com/forums/thread/655349) — `task_for_pid` blocked; own-process `task_threads` approach documented
- [how to get iOS app specific heap memory usage — Apple Developer Forums (thread/119906)](https://developer.apple.com/forums/thread/119906) — `task_vm_info` with `phys_footprint` confirmed working, no entitlement noted
- [Swift 4 iOS app memory usage gist (pejalo)](https://gist.github.com/pejalo/671dd2f67e3877b18c38c749742350ca) — `MACH_TASK_BASIC_INFO` implementation without special entitlements
- [Battery level with IOPSCopyPowerSourcesInfo — Apple Developer Forums (thread/712711)](https://developer.apple.com/forums/thread/712711) — forum thread confirming IOPSCopyPowerSourcesInfo is not the iOS path
- [Battery data gone in iOS 10 — MacRumors Forums](https://forums.macrumors.com/threads/battery-data-cycles-health-etc-gone-in-ios-10.1977954/) — confirms Apple removed detailed battery data via IOKit in iOS 10
- [MTLDevice.currentAllocatedSize — Apple Developer Documentation](https://developer.apple.com/documentation/metal/mtldevice/currentallocatedsize) — public Metal API, no entitlement; tracks GPU memory not CPU utilization
- [Reading iOS Sandbox Profiles — 8kSec](https://8ksec.io/reading-ios-sandbox-profiles/) — confirms `container.sb` governs all App Store/sideloaded apps; entitlements drive permission differences
- [ProcessInfo — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/processinfo) — `physicalMemory`, `processorCount`, `thermalState` all public, no entitlement
- [iOS Sideloading How It Works 2025 — DEV Community](https://dev.to/1_king_0b1e1f8bfe6d1/how-ios-sideloading-actually-works-in-2025-dev-certs-altstore-and-the-eu-exception-1m2h) — confirms free Apple ID sideload entitlement constraints match App Store sandbox

---

## Appendix: v1.1 Research (App Icon, TrollStore, Polling Interval)

Preserved from v1.1 for traceability. See git history for full v1.1 content.

Key v1.1 decisions still in force:
- IOKit `IOPMPowerSource` Temperature: blocked under free Apple ID, TrollStore path requires iOS ≤17.0 (device on iOS 18 — permanently blocked)
- App icon: single-size 1024×1024 opaque RGB PNG, Xcode 26 handles resizing
- Polling interval: 10s `Timer.publish`
- `ldid` for TrollStore build path — not needed for v1.2

---
*Stack research for: CoreWatch v1.2 — iOS system health APIs under free Apple ID sideload*
*Researched: 2026-05-14*
