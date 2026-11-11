import SwiftUI

/// Global app settings screen.
struct SettingsView: View {
    @EnvironmentObject var cloudSync: CloudSyncManager
    @EnvironmentObject var blockListStore: BlockListStore
    @EnvironmentObject var downtimeStore: DowntimeStore
    @State private var showRestoreAlert = false
    @State private var restoreResult = ""

    var body: some View {
        Form {
            // MARK: - iCloud Screen Time
            Section("iCloud Screen Time") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make sure **Share Across Devices** is disabled in Settings → Screen Time for OpenGuard to work correctly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                    }
                }
            }

            // MARK: - iCloud Backup
            Section("iCloud Backup") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your block list settings are automatically backed up to iCloud. If you reinstall OpenGuard, your settings will be restored.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    let restoredApps = cloudSync.restoreFromCloud()
                    let restoredDowntime = cloudSync.restoreDowntimeFromCloud()
                    let restored = restoredApps || restoredDowntime
                    if restoredApps {
                        // Shield the restored apps and refresh the UI
                        ShieldManager.shared.applyAllShields()
                        blockListStore.reload()
                    }
                    if restoredDowntime {
                        downtimeStore.reload()
                        downtimeStore.scheduleAllActivities()
                        ShieldManager.shared.reapplyDowntimeIfNeeded()
                    }
                    restoreResult = restored
                        ? "Settings restored from iCloud!"
                        : "No iCloud backup found or data is empty."
                    showRestoreAlert = true
                } label: {
                    Label("Restore from iCloud", systemImage: "arrow.clockwise.icloud")
                }
            }

            // MARK: - About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://github.com/jonasxwebdev/openguard")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            // MARK: - Debug (development only)
            #if DEBUG
            Section("Debug") {
                Button("Reset Onboarding") {
                    cloudSync.resetOnboarding()
                }

                Button("Reset All Opens (Daily Reset)") {
                    SharedDataStore.shared.resetAllOpens()
                    ShieldManager.shared.applyAllShields()
                    blockListStore.reload()
                }

                Button("Force Re-apply All Shields") {
                    ShieldManager.shared.applyAllShields()
                }

                Button(role: .destructive) {
                    // Clear all data
                    let data = BlockListData.empty
                    SharedDataStore.shared.save(data)
                    ShieldManager.shared.removeAllShields()
                    blockListStore.reload()
                } label: {
                    Text("Clear All Data & Shields")
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        .alert("Restore", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreResult)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(CloudSyncManager.shared)
            .environmentObject(BlockListStore.shared)
            .environmentObject(DowntimeStore.shared)
    }
}
