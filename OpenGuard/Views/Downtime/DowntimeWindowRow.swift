import SwiftUI
import FamilyControls
import ManagedSettings

/// A single row in the downtime list, showing time range, days, and enabled toggle.
struct DowntimeWindowRow: View {
    let window: DowntimeWindow
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(window.formattedTimeRange)
                    .font(.headline)
                    .monospacedDigit()

                Text(window.formattedDays)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !window.excludedAppTokensData.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("\(window.excludedAppTokensData.count) app(s) allowed")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { window.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        DowntimeWindowRow(
            window: DowntimeWindow.makeDefault(),
            onToggle: {}
        )

        DowntimeWindowRow(
            window: DowntimeWindow(
                id: UUID(),
                startHour: 21,
                startMinute: 0,
                endHour: 23,
                endMinute: 0,
                activeDays: [2, 3, 4, 5, 6],
                isEnabled: false,
                excludedAppTokensData: [],
                excludedAppNames: ["Messages", "Phone"]
            ),
            onToggle: {}
        )
    }
}
