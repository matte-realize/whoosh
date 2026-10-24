import Foundation

/// Production `PowerStateMonitoring` backed by `ProcessInfo` (Requirement 11.2).
///
/// Reads `ProcessInfo.isLowPowerModeEnabled` and `thermalState`, and listens for
/// `NSProcessInfoPowerStateDidChange` and `ProcessInfo.thermalStateDidChange`
/// notifications. On any change it hops to the main actor and fires
/// `onPowerStateChange` so the ride engine can pick a gentler accuracy profile
/// for the next location request.
///
/// Foundation-only: `ProcessInfo` lives in Foundation, so this does not pull in
/// UIKit and the engine stays framework-light. This is the single type that
/// reads the device power state directly.
final class ProcessInfoPowerMonitor: PowerStateMonitoring {
    private let processInfo: ProcessInfo
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    var onPowerStateChange: (() -> Void)?

    init(
        processInfo: ProcessInfo = .processInfo,
        notificationCenter: NotificationCenter = .default
    ) {
        self.processInfo = processInfo
        self.notificationCenter = notificationCenter
    }

    var isLowPowerModeEnabled: Bool {
        processInfo.isLowPowerModeEnabled
    }

    var isThermallyThrottled: Bool {
        switch processInfo.thermalState {
        case .serious, .critical:
            return true
        case .nominal, .fair:
            return false
        @unknown default:
            return false
        }
    }

    func startMonitoring() {
        guard observers.isEmpty else { return }
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            // Notifications may arrive off the main actor; hop before firing.
            Task { @MainActor [weak self] in
                self?.onPowerStateChange?()
            }
        }
        observers.append(
            notificationCenter.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: nil,
                using: handler
            )
        )
        observers.append(
            notificationCenter.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil,
                using: handler
            )
        )
    }

    func stopMonitoring() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}
