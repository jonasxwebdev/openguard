import Foundation
import os.log

/// Mirrors the local block list to iCloud Key-Value Storage for
/// reinstall recovery. Only used by the main app target.
@MainActor
final class CloudSyncManager: ObservableObject {

    static let shared = CloudSyncManager()

    private let store = NSUbiquitousKeyValueStore.default
    private let logger = Logger(subsystem: "com.jonasreidel.openguard", category: "CloudSync")

    @Published var isOnboardingCompleted: Bool = false

    private init() {
        // Observe external iCloud changes (e.g., from another device or reinstall)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )

        // Initialize onboarding state from persisted storage
        isOnboardingCompleted = checkOnboardingCompleted()
    }

    // MARK: - Upload

    /// Mirrors the current local block list to iCloud KV store.
    func uploadToCloud() {
        let data = SharedDataStore.shared.load()
        do {
            let encoded = try JSONEncoder().encode(data)
            store.set(encoded, forKey: AppConstants.iCloudBlockListKey)
            store.synchronize()
            logger.info("Uploaded block list to iCloud (\(data.apps.count) apps)")
        } catch {
            logger.error("Failed to encode block list for iCloud: \(error.localizedDescription)")
        }
    }

    // MARK: - Downtime Upload

    /// Mirrors the current downtime settings to iCloud KV store.
    func uploadDowntimeToCloud() {
        let data = SharedDataStore.shared.loadDowntime()
        do {
            let encoded = try JSONEncoder().encode(data)
            store.set(encoded, forKey: AppConstants.iCloudDowntimeKey)
            store.synchronize()
            logger.info("Uploaded downtime to iCloud (\(data.windows.count) windows)")
        } catch {
            logger.error("Failed to encode downtime for iCloud: \(error.localizedDescription)")
        }
    }

    /// Restores downtime settings from iCloud if local data is empty.
    @discardableResult
    func restoreDowntimeFromCloudIfNeeded() -> Bool {
        let localData = SharedDataStore.shared.loadDowntime()
        guard localData.windows.isEmpty else {
            logger.info("Local downtime data exists, skipping iCloud restore")
            return false
        }
        return restoreDowntimeFromCloud()
    }

    /// Force-restores downtime from iCloud regardless of local state.
    @discardableResult
    func restoreDowntimeFromCloud() -> Bool {
        store.synchronize()

        guard let cloudData = store.data(forKey: AppConstants.iCloudDowntimeKey) else {
            logger.info("No iCloud downtime data found")
            return false
        }

        do {
            let decoded = try JSONDecoder().decode(DowntimeData.self, from: cloudData)
            guard !decoded.windows.isEmpty else {
                logger.info("iCloud downtime data is empty")
                return false
            }
            SharedDataStore.shared.saveDowntime(decoded)
            logger.info("Restored \(decoded.windows.count) downtime windows from iCloud")
            return true
        } catch {
            logger.error("Failed to decode iCloud downtime data: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Download / Restore

    /// Manually restores settings from iCloud. Used when:
    /// - First launch after reinstall (local data is empty)
    /// - User taps "Restore from iCloud" in settings
    /// Returns true if data was restored.
    @discardableResult
    func restoreFromCloudIfNeeded() -> Bool {
        let localData = SharedDataStore.shared.load()

        // Only restore if local data is empty
        guard localData.apps.isEmpty else {
            logger.info("Local data exists, skipping iCloud restore")
            return false
        }

        return restoreFromCloud()
    }

    /// Force-restores from iCloud regardless of local state.
    @discardableResult
    func restoreFromCloud() -> Bool {
        store.synchronize()

        guard let cloudData = store.data(forKey: AppConstants.iCloudBlockListKey) else {
            logger.info("No iCloud data found")
            return false
        }

        do {
            let decoded = try JSONDecoder().decode(BlockListData.self, from: cloudData)
            guard !decoded.apps.isEmpty else {
                logger.info("iCloud data is empty")
                return false
            }

            // Restore settings (opens per day, time limits) but reset runtime state
            var restoredData = decoded
            for i in restoredData.apps.indices {
                restoredData.apps[i].opensUsedToday = 0
                restoredData.apps[i].currentOpenExpiresAt = nil
            }
            restoredData.lastResetDate = Date()

            SharedDataStore.shared.save(restoredData)
            logger.info("Restored \(restoredData.apps.count) apps from iCloud")
            return true
        } catch {
            logger.error("Failed to decode iCloud data: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Onboarding State

    /// Persists the onboarding-completed flag to both local and iCloud storage.
    func setOnboardingCompleted() {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(true, forKey: AppConstants.onboardingCompletedKey)
        store.set(true, forKey: AppConstants.onboardingCompletedKey)
        store.synchronize()
        isOnboardingCompleted = true
    }

    /// Reads the persisted onboarding state from UserDefaults / iCloud.
    private func checkOnboardingCompleted() -> Bool {
        let local = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .bool(forKey: AppConstants.onboardingCompletedKey) ?? false
        let cloud = store.bool(forKey: AppConstants.onboardingCompletedKey)
        return local || cloud
    }

    // MARK: - External Change Handler

    @objc private func iCloudDidChange(_ notification: Notification) {
        logger.info("iCloud KV store changed externally")
        // We don't auto-merge to avoid overwriting user's current state.
        // The user can manually restore from Settings.
    }
}
