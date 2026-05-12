import SwiftUI
import UserNotifications

@main
struct TermostatoApp: App {

    /// Retained for the app lifetime so UNUserNotificationCenter.delegate is not deallocated
    /// (RESEARCH.md Pitfall 6 — delegate is a weak reference; must be strongly held here).
    @State private var notificationDelegate = NotificationDelegate()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                }
        }
    }
}
