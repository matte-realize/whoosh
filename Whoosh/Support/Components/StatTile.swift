import SwiftUI

/// A labeled number tile for cards like the weekly-stats card and the summary
/// (Requirement 15.3). Uses large bold **tabular** numerals so values don't
/// shift horizontally as they change (Requirement 15.2).
///
/// `value` is the already-formatted primary number (e.g. "12.4"); an optional
/// `unit` renders smaller and muted beside it (e.g. "mi"). A combined
/// accessibility label reads "label, value unit" as one phrase.
struct StatTile: View {
    let label: String
    let value: String
    var unit: String?
    var valueSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label.uppercased())
                .font(Theme.Typography.sectionHeader)
                .tracking(0.8)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(value)
                    .font(Theme.Typography.metric(valueSize))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: valueSize * 0.5, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        if let unit {
            return "\(label), \(value) \(unit)"
        }
        return "\(label), \(value)"
    }
}

#Preview("StatTile") {
    HStack {
        StatTile(label: "This week", value: "12.4", unit: "mi")
        StatTile(label: "Rides", value: "3")
    }
    .padding()
    .background(Theme.Colors.cardSurface)
}
