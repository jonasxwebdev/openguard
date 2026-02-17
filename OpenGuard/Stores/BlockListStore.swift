import Foundation
import FamilyControls
import ManagedSettings
import Combine
import os.log

/// Main app's observable wrapper around `SharedDataStore`.
/// Provides a reactive interface for SwiftUI views and handles
/// FamilyControls authorization state.
@MainActor
final class BlockListStore: ObservableObject {

    static let shared = BlockListStore()

    @Published var apps: [BlockedApp] = []
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false

    private let logger = Logger(subsystem: "com.jonasreidel.openguard", category: "BlockListStore")
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Observe authorization status changes
        AuthorizationCenter.shared.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authorizationStatus = status
                self?.isAuthorized = (status == .approved)
                if status == .denied {
                    self?.logger.warning("FamilyControls authorization revoked")
                }
            }
            .store(in: &cancellables)

        // Initial load
        reload()
    }

    // MARK: - Authorization

    /// Requests FamilyControls authorization for individual use.
    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        logger.info("FamilyControls authorization requested")
    }

    // MARK: - Data Access

    /// Reloads the block list from the shared data store.
    func reload() {
        apps = SharedDataStore.shared.loadAllApps()
    }

    // MARK: - Adding Apps

    /// Adds apps from a FamilyActivitySelection to the block list.
    /// Each selected app is immediately shielded.
    func addApps(from selection: FamilyActivitySelection) {
        let tokens = selection.applicationTokens

        for token in tokens {
            guard let tokenData = try? JSONEncoder().encode(token) else {
                logger.error("Failed to encode application token")
                continue
            }

            // Check for duplicates
            guard !apps.contains(where: { $0.applicationTokenData == tokenData }) else {
                continue
            }

            let app = BlockedApp(
                id: UUID(),
                applicationTokenData: tokenData,
                displayName: "App", // Display name will be shown via the token
                opensPerDay: AppConstants.defaultOpensPerDay,
                timeLimitPerOpen: AppConstants.defaultTimeLimitPerOpen,
                opensUsedToday: 0,
                currentOpenExpiresAt: nil
            )

            SharedDataStore.shared.addApp(app)

            // Immediately shield the app
            ShieldManager.shared.addShield(for: token)
        }

        reload()
        syncToCloud()
        logger.info("Added \(tokens.count) app(s) to block list")
    }

    // MARK: - Removing Apps

    /// Removes an app from the block list and immediately removes its shield.
    func removeApp(_ app: BlockedApp) {
        // Remove shield first
        if let token = app.applicationToken() {
            ShieldManager.shared.removeShield(for: token)
        }

        // Cancel any pending notifications
        NotificationManager.shared.cancelNotifications(for: app.id)

        // Remove from store
        SharedDataStore.shared.removeApp(by: app.id)

        reload()
        syncToCloud()
        logger.info("Removed \(app.displayName) from block list")
    }

    /// Removes an app at the given index set (for List swipe-to-delete).
    func removeApps(at offsets: IndexSet) {
        for index in offsets {
            removeApp(apps[index])
        }
    }

    // MARK: - Updating Apps

    /// Updates settings for a specific app.
    func updateApp(_ app: BlockedApp) {
        SharedDataStore.shared.updateApp(app)
        reload()
        syncToCloud()
    }

    // MARK: - Cloud Sync

    private func syncToCloud() {
        CloudSyncManager.shared.uploadToCloud()
    }
}
