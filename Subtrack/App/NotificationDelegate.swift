import UIKit
import UserNotifications

/// Uten denne vises ikke varsler (banner/lyd) mens appen selv er åpen i
/// forgrunnen - standardoppførselen til UNUserNotificationCenter er å vise
/// dem kun når appen er i bakgrunnen. Nyttig å ha når man tester i simulator.
/// Håndterer også «Avslutt abonnement»-knappen på varslene.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            response.actionIdentifier == NotificationScheduler.openCancelLinkAction,
            let urlString = response.notification.request.content.userInfo[NotificationScheduler.cancelURLKey] as? String,
            let url = URL(string: urlString)
        else { return }
        await UIApplication.shared.open(url)
    }
}
