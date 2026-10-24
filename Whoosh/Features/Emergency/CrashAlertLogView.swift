import SwiftUI

/// The crash alert log, pushed from the Emergency setup hub (spec Requirement
/// 11.5, 11.7, 11.9, task 22).
///
/// Lists records most-recent-first with an icon + text status, lets the rider
/// open a detail (per-recipient attempts and the exact text that was/would be
/// sent), and delete one record (swipe) or all records (toolbar) with real
/// deletion. A thin view over `CrashAlertLogViewModel`.
struct CrashAlertLogView: View {
    @Bindable var viewModel: CrashAlertLogViewModel
    @State private var showDeleteAllConfirmation = false
    @State private var selectedRecord: CrashAlertRecord?

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                recordList
            }
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Crash alert log")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Text("Delete all")
                            .foregroundStyle(Theme.Palette.alert)
                    }
                    .accessibilityLabel("Delete all crash alert records")
                }
            }
        }
        .confirmationDialog(
            "Delete all records?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) { viewModel.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every crash alert record on this iPhone. This can't be undone.")
        }
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                CrashAlertRecordDetailView(record: record)
            }
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - List

    private var recordList: some View {
        List {
            ForEach(viewModel.records) { record in
                Button {
                    selectedRecord = record
                } label: {
                    CrashAlertLogRow(record: record)
                }
                .listRowBackground(Theme.Colors.cardSurface)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.delete(id: record.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No crash alerts yet")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Alerts you send or simulate will appear here. Whoosh can't guarantee detection or delivery.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No crash alerts yet. Alerts you send or simulate will appear here.")
    }
}

// MARK: - Row

/// A single log row: overall status (icon + text) plus the local date and a
/// summary of recipients.
private struct CrashAlertLogRow: View {
    let record: CrashAlertRecord

    var body: some View {
        let state = record.event.state
        let isDrill = record.event.isDrill
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: CrashAlertLogDisplay.systemImage(for: state, isDrill: isDrill))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CrashAlertLogDisplay.tint(for: state, isDrill: isDrill))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(CrashAlertLogDisplay.title(for: state, isDrill: isDrill))
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(dateText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(CrashAlertLogDisplay.title(for: state, isDrill: isDrill)), \(dateText)")
        .accessibilityHint("Shows the recipients and the message")
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE MMM d, h:mm a"
        return formatter.string(from: record.event.detectedAt)
    }
}

// MARK: - Detail

/// Detail of one record: per-recipient attempts (masked numbers, icon + text
/// status) and the exact text that was/would be sent.
private struct CrashAlertRecordDetailView: View {
    let record: CrashAlertRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                statusHeader
                recipientsSection
                messageSection
                Text("Whoosh is not a guaranteed emergency-response service and cannot guarantee detection or delivery. It does not contact emergency services.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Crash alert")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var statusHeader: some View {
        let state = record.event.state
        let isDrill = record.event.isDrill
        return HStack(spacing: Theme.Spacing.md) {
            Image(systemName: CrashAlertLogDisplay.systemImage(for: state, isDrill: isDrill))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CrashAlertLogDisplay.tint(for: state, isDrill: isDrill))
            Text(CrashAlertLogDisplay.title(for: state, isDrill: isDrill))
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var recipientsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Recipients")
            if record.attempts.isEmpty {
                Text("No recipients.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(record.attempts.enumerated()), id: \.element.id) { index, attempt in
                        attemptRow(attempt)
                        if index < record.attempts.count - 1 {
                            Rectangle()
                                .fill(Theme.Colors.separator)
                                .frame(height: 1)
                                .padding(.leading, Theme.Spacing.md)
                        }
                    }
                }
                .background(Theme.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    private func attemptRow(_ attempt: AlertAttempt) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(attempt.labelSnapshot)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                // Masked number only — full numbers are never stored (Req 11.3).
                Text("•••• \(attempt.maskedNumber)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: CrashAlertLogDisplay.systemImage(for: attempt.status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CrashAlertLogDisplay.tint(for: attempt.status))
                Text(CrashAlertLogDisplay.title(for: attempt.status))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attempt.labelSnapshot), ending \(attempt.maskedNumber), \(CrashAlertLogDisplay.title(for: attempt.status))")
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Message")
            Text(record.renderedText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .accessibilityLabel("Message text: \(record.renderedText)")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Typography.sectionHeader)
            .tracking(0.8)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

#Preview("Log — with records") {
    let records = [
        CrashAlertRecordPreview.sent,
        CrashAlertRecordPreview.drill,
        CrashAlertRecordPreview.queued,
    ]
    return NavigationStack {
        CrashAlertLogView(
            viewModel: CrashAlertLogViewModel(
                repository: InMemoryCrashAlertRepository(records: records),
                clock: SystemClock()
            )
        )
    }
}

#Preview("Log — empty") {
    NavigationStack {
        CrashAlertLogView(
            viewModel: CrashAlertLogViewModel(
                repository: InMemoryCrashAlertRepository(),
                clock: SystemClock()
            )
        )
    }
}

// MARK: - Preview fixtures

private enum CrashAlertRecordPreview {
    static func make(
        state: CrashEventState,
        isDrill: Bool,
        attempts: [AlertAttempt]
    ) -> CrashAlertRecord {
        let event = CrashEvent(
            id: UUID(),
            detectedAt: Date(),
            utcOffsetMinutes: -240,
            isDrill: isDrill,
            source: isDrill ? "simulator" : "motion-heuristic",
            confidence: 0.9,
            rideId: nil,
            state: state,
            countdown: nil,
            suppressedUntil: nil,
            locationAtDetection: .unavailable,
            footageRef: nil,
            outcome: .expired
        )
        return CrashAlertRecord(
            event: event,
            locationAtSend: nil,
            templateVersion: 1,
            renderedText: "WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.",
            attempts: attempts,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static var sent: CrashAlertRecord {
        make(state: .sent, isDrill: false, attempts: [
            AlertAttempt(recipientRef: UUID(), labelSnapshot: "Mom", maskedNumber: "23", kind: .crashAlert, status: .delivered, attemptedAt: Date(), updatedAt: Date()),
            AlertAttempt(recipientRef: UUID(), labelSnapshot: "Sam", maskedNumber: "24", kind: .crashAlert, status: .sent, attemptedAt: Date(), updatedAt: Date()),
        ])
    }

    static var drill: CrashAlertRecord {
        make(state: .sent, isDrill: true, attempts: [
            AlertAttempt(recipientRef: UUID(), labelSnapshot: "Mom", maskedNumber: "23", kind: .drill, status: .delivered, attemptedAt: Date(), updatedAt: Date()),
        ])
    }

    static var queued: CrashAlertRecord {
        make(state: .queuedOffline, isDrill: false, attempts: [
            AlertAttempt(recipientRef: UUID(), labelSnapshot: "Mom", maskedNumber: "23", kind: .crashAlert, status: .queued, attemptedAt: Date(), updatedAt: Date()),
        ])
    }
}
