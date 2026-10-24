import SwiftUI

/// The ride-history screen (Requirement 7, mockup 5). Light app chrome; pushed
/// from Home with a "Home" back label (the composition root owns the stack).
///
/// Shows finished rides grouped into month sections (header: "OCTOBER 2026" with
/// "4 rides · 18.7 mi" on the right), each a `RideRow` (distance · duration, no
/// speed per the mockup). Swiping a row left reveals a red Delete action that
/// asks for confirmation before permanently removing the ride; tapping a row
/// opens its `RideSummaryView` (history detail). A friendly empty state shows
/// when there are no rides, and a legend footer explains the sync icons.
///
/// Per the layering table this view uses only the `HistoryViewModel` and model
/// values; it imports no framework service types. Navigation to the detail is
/// expressed with a closure so the composition root wires the push.
struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel
    var onSelectRide: (Ride) -> Void = { _ in }

    @State private var pendingDelete: Ride?

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Rides")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.load() }
        .confirmationDialog(
            "Delete this ride?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete ride", role: .destructive) {
                if let ride = pendingDelete {
                    viewModel.delete(ride)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This permanently removes the ride from this iPhone. This can't be undone.")
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.rides) { ride in
                        Button {
                            onSelectRide(ride)
                        } label: {
                            RideRow(ride: ride, showSpeed: false)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Theme.Colors.cardSurface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = ride
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    sectionHeader(section)
                }
            }

            legendFooter
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func sectionHeader(_ section: HistoryViewModel.MonthSection) -> some View {
        HStack {
            Text(section.title)
                .font(Theme.Typography.sectionHeader)
                .tracking(0.8)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(section.summaryText)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(section.summaryText)")
    }

    // MARK: - Legend footer

    private var legendFooter: some View {
        HStack(spacing: Theme.Spacing.lg) {
            legendItem(.synced)
            legendItem(.pending)
            legendItem(.localOnly)
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: Synced, Pending, On device")
    }

    private func legendItem(_ status: SyncStatus) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: variant(for: status).systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(status.title)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func variant(for status: SyncStatus) -> StateChip.Variant {
        switch status {
        case .localOnly: return .onDevice
        case .pending: return .pending
        case .synced: return .synced
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bicycle")
                .font(.system(size: 34))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No rides yet")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Your finished rides will appear here, grouped by month.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No rides yet. Your finished rides will appear here, grouped by month.")
    }
}

#Preview("History — with rides") {
    NavigationStack {
        HistoryView(
            viewModel: HistoryViewModel(
                repository: InMemoryRideRepository(
                    rides: PreviewSeed.rides(now: Date(timeIntervalSince1970: 1_729_784_400))
                )
            )
        )
    }
}

#Preview("History — empty") {
    NavigationStack {
        HistoryView(viewModel: HistoryViewModel(repository: InMemoryRideRepository()))
    }
}
