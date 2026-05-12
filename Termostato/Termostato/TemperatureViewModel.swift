import Foundation
import Observation
import Combine

/// A single thermal state snapshot, used as a data point in the session history chart.
struct ThermalReading: Identifiable {
    let id = UUID()
    let timestamp: Date
    let state: ProcessInfo.ThermalState

    /// Integer Y-axis value for Swift Charts mapping (Nominal=0, Fair=1, Serious=2, Critical=3).
    var yValue: Int {
        switch state {
        case .nominal:   return 0
        case .fair:      return 1
        case .serious:   return 2
        case .critical:  return 3
        @unknown default: return 0
        }
    }

    /// State name string used as the nominal category key for foregroundStyle color mapping.
    var stateName: String {
        switch state {
        case .nominal:   return "Nominal"
        case .fair:      return "Fair"
        case .serious:   return "Serious"
        case .critical:  return "Critical"
        @unknown default: return "Nominal"
        }
    }
}

/// Primary data pipeline for Termostato.
/// Phase 2 adds: history array, chart data points.
/// Phase 3 adds: notification triggering on threshold crossing.
@Observable
@MainActor
final class TemperatureViewModel {

    // MARK: - Published state

    /// Current thermal state. Observers (SwiftUI Views) read this directly.
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    /// Session history ring buffer — max 120 readings (D-05). Session-only, never persisted (D-06).
    private static let maxHistory = 120
    private(set) var history: [ThermalReading] = []

    // MARK: - Private polling state
    // D-07: No stored mutable timer reference — cancel-and-recreate pattern.
    private var timerCancellable: AnyCancellable?

    // MARK: - Init

    init() {}

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
        let reading = ThermalReading(timestamp: Date(), state: thermalState)
        if history.count >= Self.maxHistory {
            history.removeFirst()
        }
        history.append(reading)
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

}
