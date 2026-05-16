import UserNotifications

/// UNUserNotificationCenterDelegate that enables notification banners while the app is
/// foregrounded. Without this, iOS silently drops notifications when the app is in the
/// foreground (RESEARCH.md Pitfall 2).
///
/// Both delegate methods are nonisolated — required for Swift 6 conformance from a
/// non-isolated class (RESEARCH.md Pattern 5, Apple Developer Forums thread 762217).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Called when a notification arrives while the app is foregrounded.
    /// Returns [.banner, .sound] so the user sees a banner and hears the alert tone.
    /// (.alert is deprecated since iOS 14 — use .banner. RESEARCH.md State of the Art.)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Called when the user taps the notification or the "Dismiss" action button (D-03).
    /// Tapping the notification body opens the app via standard iOS behavior — no action needed here.
    /// Tapping "Dismiss" also routes here — the destructive action removes the notification automatically.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
