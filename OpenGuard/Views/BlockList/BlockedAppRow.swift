import SwiftUI
import FamilyControls
import ManagedSettings

/// A single row in the block list showing app status.
struct BlockedAppRow: View {
    let app: BlockedApp

    var body: some View {
        HStack(spacing: 14) {
            // App name and icon from FamilyControls
            appLabel

            Spacer()

            // Opens info + status
            VStack(alignment: .trailing, spacing: 4) {
                // Re-render when the open window expires so the "OPEN" badge
                // doesn't stay visible after the app is blocked again.
                TimelineView(.explicit(app.currentOpenExpiresAt.map { [$0] } ?? [])) { _ in
                    statusBadge
                }

                HStack(spacing: 12) {
                    opensIndicator
                    timeLimitLabel
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    /// Uses FamilyControls Label to render the real app name and icon.
    private var appLabel: some View {
        Group {
            if let token = app.applicationToken() {
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(.body)
                    .lineLimit(1)
            } else {
                Label(app.displayName, systemImage: "app.fill")
                    .font(.body)
                    .lineLimit(1)
            }
        }
    }

    private var opensIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.circle")
                .font(.caption)
            Text("\(app.opensUsedToday)/\(app.opensPerDay)")
                .font(.caption)
        }
        .foregroundStyle(app.isExhausted ? .red : .secondary)
    }

    private var timeLimitLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption)
            Text(formatDuration(app.timeLimitPerOpen))
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private var statusBadge: some View {
        Group {
            if app.isInOpenWindow {
                Text("OPEN")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green)
                    .clipShape(Capsule())
            } else if app.isExhausted {
                Text("BLOCKED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.red)
                    .clipShape(Capsule())
            } else {
                Text("\(app.opensRemaining) left")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
        }
        return "\(minutes) min"
    }
}

#Preview {
    List {
        BlockedAppRow(app: BlockedApp(
            id: UUID(),
            applicationTokenData: Data(),
            displayName: "Instagram",
            opensPerDay: 5,
            timeLimitPerOpen: 600,
            opensUsedToday: 2,
            currentOpenExpiresAt: nil
        ))

        BlockedAppRow(app: BlockedApp(
            id: UUID(),
            applicationTokenData: Data(),
            displayName: "TikTok",
            opensPerDay: 3,
            timeLimitPerOpen: 300,
            opensUsedToday: 3,
            currentOpenExpiresAt: nil
        ))

        BlockedAppRow(app: BlockedApp(
            id: UUID(),
            applicationTokenData: Data(),
            displayName: "Twitter",
            opensPerDay: 5,
            timeLimitPerOpen: 900,
            opensUsedToday: 1,
            currentOpenExpiresAt: Date().addingTimeInterval(180)
        ))
    }
}
