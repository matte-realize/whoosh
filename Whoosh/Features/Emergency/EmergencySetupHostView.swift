import SwiftUI

/// Navigation host for the Emergency setup hub and its sub-screens (spec design
/// "Other screens"; crash-response tasks 16–18, 22 wiring).
///
/// Owns a `NavigationStack` and wires the hub's navigation hooks
/// (`onAddContact`, `onEditContact`, `onOpenConsent`, `onOpenTest`,
/// `onOpenLog`) to push the contact editor, the consent screen (task 17), the
/// intro/test flow (task 18), and the crash alert log (task 22). It builds each
/// sub-screen's view model from the injected seams, so the composition root can
/// mount the whole emergency feature with one view.
///
/// Consent revocation is forwarded to `onConsentRevoked` so the composition root
/// can ask the `CrashResponseCoordinator` to disarm and cancel any queued unsent
/// alert (Requirement 3.7). `isMessagingConnected` reflects whether a real
/// notifier is wired (`false` for the Tier 0 Noop) so the test flow shows the
/// honest "not connected" fallback.
///
/// A thin view: it only constructs view models and routes navigation.
struct EmergencySetupHostView: View {
    @State private var viewModel: EmergencySetupViewModel
    @State private var path: [Route] = []

    private let contactStore: EmergencyContactStore
    private let consentStore: ConsentStore
    private let settingsStore: CrashAlertSettingsStore
    private let notifier: CrashNotifier
    private let connectivity: ConnectivityMonitor
    private let scheduler: CrashNotificationScheduler
    private let repository: CrashAlertRepository
    private let clock: Clock
    private let isMessagingConnected: Bool
    private let onConsentRevoked: (() -> Void)?

    /// The pushable sub-screens.
    private enum Route: Hashable {
        case addContact
        case editContact(UUID)
        case consent
        case test
        case log
    }

    init(
        contactStore: EmergencyContactStore,
        consentStore: ConsentStore,
        settingsStore: CrashAlertSettingsStore,
        notifier: CrashNotifier,
        connectivity: ConnectivityMonitor,
        scheduler: CrashNotificationScheduler,
        repository: CrashAlertRepository,
        clock: Clock,
        isMessagingConnected: Bool,
        onConsentRevoked: (() -> Void)? = nil
    ) {
        self.contactStore = contactStore
        self.consentStore = consentStore
        self.settingsStore = settingsStore
        self.notifier = notifier
        self.connectivity = connectivity
        self.scheduler = scheduler
        self.repository = repository
        self.clock = clock
        self.isMessagingConnected = isMessagingConnected
        self.onConsentRevoked = onConsentRevoked
        _viewModel = State(initialValue: EmergencySetupViewModel(
            contactStore: contactStore,
            settingsStore: settingsStore
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            EmergencySetupView(viewModel: viewModel)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .onAppear { wireHooks() }
    }

    // MARK: - Hook wiring

    private func wireHooks() {
        viewModel.onAddContact = { path.append(.addContact) }
        viewModel.onEditContact = { contact in path.append(.editContact(contact.id)) }
        viewModel.onOpenConsent = { path.append(.consent) }
        viewModel.onOpenTest = { path.append(.test) }
        viewModel.onOpenLog = { path.append(.log) }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .addContact:
            ContactEditorView(viewModel: ContactEditorViewModel(
                mode: .add,
                store: contactStore,
                onFinish: { popAndReload() }
            ))
        case let .editContact(id):
            if let contact = contactStore.contactsOrEmpty().first(where: { $0.id == id }) {
                ContactEditorView(viewModel: ContactEditorViewModel(
                    mode: .edit(contact),
                    store: contactStore,
                    onFinish: { popAndReload() }
                ))
            } else {
                missingContact
            }
        case .consent:
            ConsentView(viewModel: makeConsentViewModel())
        case .test:
            TestAlertView(viewModel: makeTestViewModel())
        case .log:
            CrashAlertLogView(viewModel: CrashAlertLogViewModel(
                repository: repository,
                clock: clock
            ))
        }
    }

    private var missingContact: some View {
        Text("This contact is no longer available.")
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(Theme.Spacing.lg)
    }

    private func makeConsentViewModel() -> ConsentViewModel {
        let vm = ConsentViewModel(
            consentStore: consentStore,
            settingsStore: settingsStore,
            contactStore: contactStore,
            scheduler: scheduler,
            clock: clock
        )
        vm.onConsentRevoked = {
            onConsentRevoked?()
            viewModel.reload()
        }
        return vm
    }

    private func makeTestViewModel() -> TestAlertViewModel {
        TestAlertViewModel(
            notifier: notifier,
            contactStore: contactStore,
            connectivity: connectivity,
            settingsStore: settingsStore,
            clock: clock,
            isMessagingConnected: isMessagingConnected
        )
    }

    private func popAndReload() {
        if !path.isEmpty { path.removeLast() }
        viewModel.reload()
    }
}

#Preview("Emergency setup host (Tier 0)") {
    let contacts = [
        EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123", verification: .reachable),
    ]
    return EmergencySetupHostView(
        contactStore: InMemoryEmergencyContactStore(contacts: contacts),
        consentStore: InMemoryConsentStore(),
        settingsStore: InMemoryCrashAlertSettingsStore(
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
        ),
        notifier: NoopCrashNotifier(),
        connectivity: FakeConnectivityMonitor(isOnline: true),
        scheduler: FakeCrashNotificationScheduler(),
        repository: InMemoryCrashAlertRepository(),
        clock: SystemClock(),
        isMessagingConnected: false
    )
}
