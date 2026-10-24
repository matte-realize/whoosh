import Foundation
import WhooshWire
#if os(watchOS)
import WatchKit
#endif

/// The watch link seam exposed to the app delegate (watch-companion spec task
/// 17). It is a `WireLink` that also completes WatchConnectivity background
/// tasks. Keeping the concrete `WCSessionWireLink` behind this protocol lets the
/// app delegate (`WhooshWatch/App/`) register background tasks without naming the
/// WatchConnectivity adapter, so the framework stays confined to
/// `WhooshWatch/Services/Link/` (privacy rule 14).
protocol WatchLinkConnectivity: WireLink {
    #if os(watchOS)
    /// Forward a WatchConnectivity background task so the link completes it once
    /// its content drains (Requirement 10.2).
    @MainActor func register(_ task: WKWatchConnectivityRefreshBackgroundTask)
    #endif
}

extension WCSessionWireLink: WatchLinkConnectivity {}

/// Builds the watch's single connectivity link. Lives in the Link folder so the
/// app delegate never names the WatchConnectivity adapter.
enum WatchLinkFactory {
    static func make() -> any WatchLinkConnectivity {
        WCSessionWireLink()
    }
}
