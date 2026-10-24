import SwiftUI
import WatchKit

/// The watchOS app delegate (watch-companion spec task 17). Its one job for now
/// is to forward WatchConnectivity background tasks to the single watch link so
/// **every** `WKWatchConnectivityRefreshBackgroundTask` is completed once its
/// content drains — otherwise the app exhausts its background runtime budget and
/// the system stops waking it (Requirement 10.2).
///
/// Any other background-task kind is completed immediately (the watch app has no
/// other background work: it holds no ride data and makes no network request).
///
/// The delegate owns the process-wide link (behind `WatchLinkConnectivity`, so
/// the WatchConnectivity framework stays confined to the Link folder) and
/// activates it at launch, so the SwiftUI scene and (later) the
/// `WatchSessionModel` share one activated session.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    /// The one connectivity link for the app; activated at launch.
    let link: any WatchLinkConnectivity = WatchLinkFactory.make()

    func applicationDidFinishLaunching() {
        Task { await link.activate() }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let wcTask as WKWatchConnectivityRefreshBackgroundTask:
                // The link completes it once pending WC content has drained.
                link.register(wcTask)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
