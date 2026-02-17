import SwiftUI
import FamilyControls

/// Step 3: Requests FamilyControls authorization and notification permissions.
struct PermissionsView: View {
    let onComplete: () -> Void

    @EnvironmentObject var blockListStore: BlockListStore

    @State private var familyControlsGranted = false
    @State private var notificationsGranted = false
    @State private var showError = false
    @State private var errorMessage = ""

    var allGranted: Bool {
        familyControlsGranted && notificationsGranted
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Permissions")
                .font(.title)
                .fontWeight(.bold)

            Text("OpenGuard needs two permissions to manage your app access.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Permission cards
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Screen Time Access",
                    description: "Required to block and unblock apps",
                    isGranted: familyControlsGranted
                ) {
                    await requestFamilyControls()
                }

                PermissionCard(
                    icon: "bell.badge.fill",
                    title: "Notifications",
                    description: "Alerts when your open window starts and ends",
                    isGranted: notificationsGranted
                ) {
                    await requestNotifications()
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            if showError {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button(action: onComplete) {
                Text(allGranted ? "Let's Go!" : "Skip for Now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(allGranted ? .green : .gray.opacity(0.5))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Permission Requests

    private func requestFamilyControls() async {
        do {
            try await blockListStore.requestAuthorization()
            familyControlsGranted = true
            showError = false
        } catch {
            errorMessage = "Screen Time access was denied. You can enable it in Settings."
            showError = true
        }
    }

    private func requestNotifications() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        notificationsGranted = granted
        if !granted {
            errorMessage = "Notifications were denied. Enable them in Settings to get open window alerts."
            showError = true
        }
    }
}

// MARK: - Permission Card

private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () async -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Enable") {
                    Task { await action() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    PermissionsView(onComplete: {})
        .environmentObject(BlockListStore.shared)
}
