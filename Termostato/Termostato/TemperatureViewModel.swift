import Foundation
import Observation
import Combine

/// Primary data pipeline for Termostato.
/// Phase 2 adds: history array, chart data points.
/// Phase 3 adds: notification triggering on threshold crossing.
@Observable
@MainActor
final class TemperatureViewModel {

    // MARK: - Published state

    /// Current thermal state. Observers (SwiftUI Views) read this directly.
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    // MARK: - Private polling state
    // D-07: No stored mutable timer reference — cancel-and-recreate pattern.
    private var timerCancellable: AnyCancellable?

    // MARK: - Init

    init() {
        // D-01: One-shot IOKit probe. Runs on init, result logged, code removed after Phase 1.
        probeIOKit()
    }

    // MARK: - Lifecycle (called by ContentView scenePhase observer — D-06)

    /// Start the 30-second polling timer. Call when scenePhase becomes .active.
    /// D-07: Always creates a fresh timer — does NOT resume a stored reference.
    func startPolling() {
        // Guard: don't double-start.
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [self] _ in
                self.updateThermalState()
            }
        // Immediately read on start so the UI shows data without a 30-second delay.
        updateThermalState()
        print("[Termostato] Polling started.")
    }

    /// Cancel the polling timer. Call when scenePhase becomes .background.
    /// D-05: Foreground-only polling. Background thermal events handled in Phase 3.
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
        print("[Termostato] Polling stopped (backgrounded).")
    }

    // MARK: - Private

    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        print("[Termostato] thermalState = \(thermalStateDescription)")
    }

    private var thermalStateDescription: String {
        switch thermalState {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown(\(thermalState.rawValue))"
        }
    }

    // MARK: - IOKit Probe (D-01, D-02: REMOVE THIS ENTIRE METHOD AFTER PHASE 1)

    /// Attempts to read the IOPMPowerSource Temperature key via IOKit.
    /// Result logged to console; becomes the Phase 1 decision record.
    /// THIS METHOD AND ITS CALL IN init() MUST BE DELETED before Phase 2 work begins.
    private func probeIOKit() {
        let serviceName = "IOPMPowerSource"
        guard let matchingUnmanaged = IOServiceMatching(serviceName) else {
            print("[Termostato][IOKit] IOServiceMatching returned nil — IOKit unavailable")
            return
        }
        // IOServiceMatching returns Unmanaged<CFMutableDictionary>?; take retained value for use.
        let matchingDict = matchingUnmanaged.takeRetainedValue()
        let service = IOServiceGetMatchingService(0 /* kIOMasterPortDefault */, matchingDict)
        guard service != 0 else {
            print("[Termostato][IOKit] IOServiceGetMatchingService returned 0 — service not found (BLOCKED or no matching service)")
            return
        }
        var properties: Unmanaged<CFMutableDictionary>? = nil
        let kr = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        IOObjectRelease(service)
        guard kr == 0, let dict = properties?.takeRetainedValue() as? [String: Any] else {
            print("[Termostato][IOKit] IORegistryEntryCreateCFProperties failed (kr=\(kr)) — BLOCKED by AMFI/sandbox")
            return
        }
        if let temp = dict["Temperature"] {
            print("[Termostato][IOKit] Temperature key found: \(temp) — IOKit ACCESS GRANTED")
        } else {
            print("[Termostato][IOKit] Temperature key absent from dict — key not present (keys: \(dict.keys.sorted().prefix(10).joined(separator: ", ")))")
        }
    }
}
