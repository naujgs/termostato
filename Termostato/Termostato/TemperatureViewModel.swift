import Foundation
import Observation
import Combine
import UserNotifications

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

    // MARK: - Phase 3: Notification state (D-04, D-12)

    /// Tracks which thermal level was last notified. nil = no active alert. Shared cooldown for
    /// both foreground and background paths (D-04). Cleared when state drops below Serious (D-05).
    private(set) var lastAlertedState: ProcessInfo.ThermalState?

    /// Whether the user has granted notification permission. Drives the permission-denied banner
    /// in ContentView (D-12). Updated in startPolling() on each foreground (D-13).
    private(set) var notificationsAuthorized: Bool = false

    /// Block-based NotificationCenter observer token. nonisolated(unsafe) allows access in
    /// nonisolated deinit; @ObservationIgnored opts it out of @Observable tracking.
    /// Swift 6 @Observable + @MainActor pattern — RESEARCH.md Pattern 1.
    @ObservationIgnored
    nonisolated(unsafe) private var thermalObserver: (any NSObjectProtocol)?

    // MARK: - Init

    init() {
        // D-07: Register background observer. queue: .main satisfies @MainActor isolation
        // (A1 assumption — if compiler warns, wrap closure in Task { @MainActor in }).
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleBackgroundThermalChange()
            }
        }
        // D-03: Register category so "Dismiss" button appears on the notification.
        registerNotificationCategories()
    }

    deinit {
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        Task { await requestNotificationPermission() }   // D-09
        Task { await refreshNotificationStatus() }        // D-13
        print("[Termostato] Polling started.")
    }

    /// Cancel the polling timer. Call when scenePhase becomes .background.
    /// D-05: Foreground-only polling. Background thermal events handled via thermalStateDidChangeNotification.
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
        checkAndFireNotification()   // Phase 3 foreground notification gate
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

    // MARK: - Phase 3: Notification methods

    /// Request notification permission (async throws variant — required for Swift 6; D-09).
    /// Sets notificationsAuthorized. Silently continues on denial (D-10).
    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            notificationsAuthorized = granted
            if !granted {
                print("[Termostato] Notification permission denied.")
            }
        } catch {
            print("[Termostato] Notification auth error: \(error)")
            notificationsAuthorized = false
        }
    }

    /// Re-check authorization status on each foreground (D-13). Updates notificationsAuthorized.
    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = (settings.authorizationStatus == .authorized)
    }

    /// Register the "thermalAlert" UNNotificationCategory with a "Dismiss" destructive action (D-03).
    /// Must be called before the first notification is delivered.
    private func registerNotificationCategories() {
        let dismissAction = UNNotificationAction(
            identifier: "dismissAlert",
            title: "Dismiss",
            options: [.destructive]
        )
        let thermalCategory = UNNotificationCategory(
            identifier: "thermalAlert",
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([thermalCategory])
    }

    /// Shared cooldown gate (D-06). Called from both the foreground (updateThermalState) and
    /// background (handleBackgroundThermalChange) paths.
    private func checkAndFireNotification() {
        let state = thermalState
        let isElevated = (state == .serious || state == .critical)

        if isElevated {
            guard lastAlertedState == nil else {
                // Still in cooldown — state is elevated but we already notified (D-06 skip rule).
                return
            }
            lastAlertedState = state          // set cooldown (D-04)
            guard notificationsAuthorized else {
                print("[Termostato] Notification skipped — permission not granted.")
                return
            }
            let levelName = (state == .serious) ? "Serious" : "Critical"
            scheduleOverheatNotification(level: levelName)
        } else {
            lastAlertedState = nil            // cooldown reset — state dropped below Serious (D-05)
        }
    }

    /// Background thermalStateDidChangeNotification handler (D-08).
    /// Reads current state, applies D-06 gate, schedules notification.
    /// Does NOT call updateThermalState() — must not corrupt session history ring buffer.
    private func handleBackgroundThermalChange() {
        print("[Termostato] Background thermal change received.")
        // Re-read from ProcessInfo (D-08) — do not use self.thermalState which reflects last foreground read.
        let state = ProcessInfo.processInfo.thermalState
        let isElevated = (state == .serious || state == .critical)

        if isElevated {
            guard lastAlertedState == nil else { return }
            lastAlertedState = state
            guard notificationsAuthorized else { return }
            let levelName = (state == .serious) ? "Serious" : "Critical"
            scheduleOverheatNotification(level: levelName)
        } else {
            lastAlertedState = nil
        }
    }

    /// Schedule a fire-once "iPhone Overheating" local notification (D-01, D-02).
    /// Uses fixed identifier "thermalAlert" so re-scheduling replaces a pending notification
    /// rather than stacking (belt-and-suspenders alongside the D-06 cooldown gate).
    private func scheduleOverheatNotification(level: String) {
        let content = UNMutableNotificationContent()
        content.title = "iPhone Overheating"                                     // D-01
        content.body = "Thermal state: \(level) — performance may be limited"   // D-02
        content.sound = .default
        content.categoryIdentifier = "thermalAlert"                              // D-03

        let request = UNNotificationRequest(
            identifier: "thermalAlert",   // fixed ID — replaces pending rather than stacking
            content: content,
            trigger: nil                  // nil = deliver immediately
        )
        Task {
            try? await UNUserNotificationCenter.current().add(request)
            print("[Termostato] Overheating notification scheduled for \(level).")
        }
    }

}
