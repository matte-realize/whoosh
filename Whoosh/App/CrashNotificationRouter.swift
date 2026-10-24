import Foundation
import Observation
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif

/// Routes crash-alert **backup** local-notification taps to the app so it can
/// open the crash status screen (crash-response task 26: "route notification
/// taps to the status screen").
///
/// A notification can only *prompt*; it never sends or cancels an alert
/// (Requirement 13.3). When the rider taps a deadline or "not sent" notice, the
/// `UNUserNotificationCenter` delegate sets `shouldOpenStatus = true`, which
/// `WhooshApp` observes to present `CrashAlertStatusView`. The tap carries no
/// action beyond "bring the rider to the status screen".
///
/// `@Observable` so SwiftUI reacts; the `UNUserNotificationCenterDelegate` work
/// hops to the main actor.
@Observable
@MainActor
final class CrashNotificationRouter: NSObject {
    /// Set to `true` when the rider taps a crash backup notification; `WhooshApp`
    /// consumes it to open the status screen, then resets it.
    var shouldOpenStatus = false

    /// Identifier prefixes used by `UserNotificationsCrashNotificationScheduler`.
    nonisolated static let crashPrefixes = ["whoosh.crash.deadline.", "whoosh.crash.notsent."]

    /// Register this router as the notification-center delegate (live app only).
    func install() {
        #if canImport(UIKit)
        UNUserNotificationCenter.current().delegate = self
        #endif
    }
}

#if canImport(UIKit)
extension CrashNotificationRouter: UNUserNotificationCenterDelegate {
    /// Foreground presentation: still show the banner/sound so the rider sees
    /// the backup prompt even if the app is open but not on the status screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// A tap routes to the status screen (prompt only — nothing automatic).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        let isCrash = Self.crashPrefixes.contains { id.hasPrefix($0) }
        // Acknowledge the response immediately (off the main actor), then hop to
        // the main actor to update observable state.
        completionHandler()
        if isCrash {
            Task { @MainActor in
                self.shouldOpenStatus = true
            }
        }
    }
}
#endif
