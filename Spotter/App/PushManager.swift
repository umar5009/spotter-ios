import FirebaseMessaging
import UIKit
import UserNotifications

/// Remote notifications through Firebase Cloud Messaging.
/// Opted-in devices subscribe to the `spotter` topic so a message can be sent from the Firebase console.
@MainActor
final class PushManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = PushManager()
    static let topic = "spotter"

    @Published private(set) var isAuthorized = false
    @Published private(set) var wantsPush = UserDefaults.standard.bool(forKey: Keys.enabled)
    @Published var pendingRoute: String?
    @Published private(set) var token: String?

    private enum Keys {
        static let enabled = "pushEnabled"
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        Messaging.messaging().isAutoInitEnabled = wantsPush
        refreshAuthorization()
    }

    func refreshAuthorization() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            isAuthorized = Self.allowed(settings.authorizationStatus)
            if wantsPush && isAuthorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func setEnabled(_ on: Bool) async {
        guard on else {
            wantsPush = false
            UserDefaults.standard.set(false, forKey: Keys.enabled)
            Messaging.messaging().isAutoInitEnabled = false
            UIApplication.shared.unregisterForRemoteNotifications()
            try? await Messaging.messaging().unsubscribe(fromTopic: Self.topic)
            SpotterAnalytics.log("notification_permission", ["granted": "false"])
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            applyChoice(granted)
        case .denied:
            wantsPush = false
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        case .authorized, .provisional, .ephemeral:
            applyChoice(true)
        @unknown default:
            applyChoice(false)
        }
    }

    func handle(userInfo: [AnyHashable: Any]) {
        let screen = userInfo["screen"] as? String
        SpotterAnalytics.log("notification_open", ["screen": screen ?? "none"])
        if let screen, !screen.isEmpty {
            pendingRoute = screen
        }
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            token = fcmToken
            subscribeIfNeeded()
        }
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistration installationId: String?) {
        Task { @MainActor in
            subscribeIfNeeded()
            _ = installationId
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        await handle(userInfo: info)
    }

    private func applyChoice(_ granted: Bool) {
        wantsPush = granted
        isAuthorized = granted
        UserDefaults.standard.set(granted, forKey: Keys.enabled)
        Messaging.messaging().isAutoInitEnabled = granted
        SpotterAnalytics.log("notification_permission", ["granted": granted ? "true" : "false"])
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        subscribeIfNeeded()
    }

    private func subscribeIfNeeded() {
        guard wantsPush else { return }
        Task { try? await Messaging.messaging().subscribe(toTopic: Self.topic) }
    }

    private static func allowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied: return false
        @unknown default: return false
        }
    }
}
