import Foundation
import ManagedSettings
import os.log

/// Process-safe data store for the block list, backed by a JSON file
/// in the shared App Group container AND mirrored to UserDefaults(suiteName:)
/// for reliable cross-process access from sandboxed shield extensions.
///
/// The main app writes to both the JSON file and UserDefaults.
/// Extensions read from UserDefaults first (most reliable), then fall back to file.
final class SharedDataStore {

    static let shared = SharedDataStore()

    private let fileURL: URL
    private let userDefaults: UserDefaults?
    private static let userDefaultsKey = "blocklist_data_v1"
    private let logger = Logger(subsystem: "com.jonasreidel.openguard", category: "SharedDataStore")

    private init() {
        self.fileURL = AppConstants.blockListFileURL
        self.userDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if userDefaults == nil {
            logger.error("Failed to create UserDefaults with suite: \(AppConstants.appGroupIdentifier)")
        }
    }

    // MARK: - Core Read / Write

    /// Reads the block list data, trying multiple sources in order of reliability:
    /// 1. UserDefaults (suite) — most reliable in sandboxed extensions
    /// 2. Direct file read — simple, no coordinator overhead
    /// 3. NSFileCoordinator read — for cross-process safety
    func load() -> BlockListData {
        // 1. Try UserDefaults first (most reliable for extensions)
        if let defaults = userDefaults,
           let data = defaults.data(forKey: SharedDataStore.userDefaultsKey) {
            do {
                let decoded = try JSONDecoder().decode(BlockListData.self, from: data)
                logger.info("UserDefaults read succeeded: \(decoded.apps.count) apps")
                return decoded
            } catch {
                logger.error("UserDefaults decode failed: \(error.localizedDescription)")
            }
        } else {
            logger.info("UserDefaults read: no data found (defaults=\(self.userDefaults != nil))")
        }

        // 2. Try direct file read
        if let data = loadDirect() {
            return data
        }

        // 3. Try coordinated file read
        var result = BlockListData.empty
        var coordinatorError: NSError?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinatorError) { url in
            do {
                let fileData = try Data(contentsOf: url)
                result = try JSONDecoder().decode(BlockListData.self, from: fileData)
            } catch {
                self.logger.info("Coordinated read failed: \(error.localizedDescription)")
            }
        }

        if let error = coordinatorError {
            logger.error("File coordinator read error: \(error.localizedDescription)")
        }

        return result
    }

    /// Direct file read without NSFileCoordinator — works in sandboxed extensions.
    private func loadDirect() -> BlockListData? {
        let path = self.fileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            logger.info("Block list file does not exist at: \(path)")
            return nil
        }
        do {
            let fileData = try Data(contentsOf: self.fileURL)
            let decoded = try JSONDecoder().decode(BlockListData.self, from: fileData)
            logger.info("Direct read succeeded: \(decoded.apps.count) apps")
            return decoded
        } catch {
            logger.error("Direct read failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Writes the block list data to disk using coordinated file access,
    /// and mirrors to UserDefaults for reliable extension access.
    func save(_ data: BlockListData) {
        // 1. Always write to UserDefaults (most reliable for extensions)
        do {
            let encoded = try JSONEncoder().encode(data)
            userDefaults?.set(encoded, forKey: SharedDataStore.userDefaultsKey)
            logger.info("UserDefaults write succeeded: \(data.apps.count) apps")
        } catch {
            logger.error("UserDefaults encode failed: \(error.localizedDescription)")
        }

        // 2. Also write to file for larger data / backup
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
            do {
                let encoded = try JSONEncoder().encode(data)
                try encoded.write(to: url, options: .atomic)
            } catch {
                self.logger.error("Failed to write block list file: \(error.localizedDescription)")
            }
        }

        if let error = coordinatorError {
            logger.error("File coordinator write error: \(error.localizedDescription)")
        }
    }

    // MARK: - Convenience Accessors

    /// Returns all blocked apps.
    func loadAllApps() -> [BlockedApp] {
        load().apps
    }

    /// Finds a blocked app by its UUID.
    func findApp(by id: UUID) -> BlockedApp? {
        load().apps.first { $0.id == id }
    }

    /// Finds a blocked app by matching its stored application token data.
    func findApp(byTokenData tokenData: Data) -> BlockedApp? {
        load().apps.first { $0.applicationTokenData == tokenData }
    }

    /// Finds a blocked app by comparing decoded ApplicationTokens using Equatable.
    /// This is more robust than byte comparison since JSONEncoder output
    /// is not guaranteed to be deterministic across processes.
    func findApp(byApplicationToken token: ApplicationToken) -> BlockedApp? {
        load().apps.first { app in
            guard let storedToken = app.applicationToken() else { return false }
            return storedToken == token
        }
    }

    // MARK: - Mutations

    /// Adds a new blocked app to the list.
    func addApp(_ app: BlockedApp) {
        var data = load()
        // Prevent duplicates — compare decoded tokens (encoded bytes are not
        // guaranteed to be identical for the same token), falling back to bytes.
        let newToken = app.applicationToken()
        let isDuplicate = data.apps.contains { existing in
            if existing.applicationTokenData == app.applicationTokenData { return true }
            guard let newToken, let existingToken = existing.applicationToken() else { return false }
            return existingToken == newToken
        }
        guard !isDuplicate else {
            logger.info("App already in block list, skipping add")
            return
        }
        data.apps.append(app)
        save(data)
    }

    /// Removes a blocked app by its UUID.
    @discardableResult
    func removeApp(by id: UUID) -> BlockedApp? {
        var data = load()
        guard let index = data.apps.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = data.apps.remove(at: index)
        save(data)
        return removed
    }

    /// Updates a blocked app in-place. Returns the updated app on success.
    @discardableResult
    func updateApp(_ app: BlockedApp) -> BlockedApp? {
        var data = load()
        guard let index = data.apps.firstIndex(where: { $0.id == app.id }) else { return nil }
        data.apps[index] = app
        save(data)
        return app
    }

    /// Updates only the user-editable settings of an app (name, opens per day,
    /// time limit), preserving the latest runtime state on disk.
    ///
    /// Use this from UI code holding a possibly stale copy of the app, so that
    /// `opensUsedToday` / `currentOpenExpiresAt` changes made in the meantime by
    /// the extensions (opens consumed, windows expired, daily reset) are not
    /// overwritten.
    @discardableResult
    func updateSettings(of app: BlockedApp) -> BlockedApp? {
        var data = load()
        guard let index = data.apps.firstIndex(where: { $0.id == app.id }) else { return nil }
        var stored = data.apps[index]
        guard stored.displayName != app.displayName
                || stored.opensPerDay != app.opensPerDay
                || stored.timeLimitPerOpen != app.timeLimitPerOpen else {
            return stored
        }
        stored.displayName = app.displayName
        stored.opensPerDay = app.opensPerDay
        stored.timeLimitPerOpen = app.timeLimitPerOpen
        data.apps[index] = stored
        save(data)
        return stored
    }

    /// Consumes one open for the given app ID.
    /// Sets `currentOpenExpiresAt` and increments `opensUsedToday`.
    /// Returns the updated app, or nil if not found or no opens remain.
    @discardableResult
    func consumeOpen(for appID: UUID) -> BlockedApp? {
        var data = load()
        guard let index = data.apps.firstIndex(where: { $0.id == appID }) else { return nil }

        var app = data.apps[index]
        guard app.opensRemaining > 0 else { return nil }

        app.opensUsedToday += 1
        app.currentOpenExpiresAt = Date().addingTimeInterval(app.timeLimitPerOpen)
        data.apps[index] = app
        save(data)
        return app
    }

    /// Resets all apps' `opensUsedToday` to 0 and clears `currentOpenExpiresAt`.
    /// Called at midnight by the Device Activity Monitor extension.
    func resetAllOpens() {
        var data = load()
        for i in data.apps.indices {
            data.apps[i].opensUsedToday = 0
            data.apps[i].currentOpenExpiresAt = nil
        }
        data.lastResetDate = Date()
        save(data)
        logger.info("Daily reset: all opens cleared for \(data.apps.count) apps")
    }

    /// Finds and returns all apps whose open window has expired
    /// (i.e., `currentOpenExpiresAt` is non-nil and in the past).
    /// Clears their `currentOpenExpiresAt` on disk.
    /// Returns the list of apps that were expired.
    func expireOpenWindows() -> [BlockedApp] {
        var data = load()
        let now = Date()
        var expired: [BlockedApp] = []

        for i in data.apps.indices {
            if let expiresAt = data.apps[i].currentOpenExpiresAt, expiresAt <= now {
                expired.append(data.apps[i])
                data.apps[i].currentOpenExpiresAt = nil
            }
        }

        if !expired.isEmpty {
            save(data)
            logger.info("Expired \(expired.count) open window(s)")
        }

        return expired
    }

    /// Checks whether today's date differs from `lastResetDate` (by calendar day).
    /// If so, performs a reset. Called on app launch and extension wake-ups
    /// as a safety net in case the midnight DeviceActivity schedule didn't fire.
    ///
    /// - Returns: `true` if a reset was performed. Callers should then re-apply
    ///   shields, because the reset clears any active open windows.
    @discardableResult
    func resetIfNewDay() -> Bool {
        let data = load()
        let calendar = Calendar.current
        if !calendar.isDateInToday(data.lastResetDate) {
            logger.info("New day detected — performing safety reset")
            resetAllOpens()
            return true
        }
        return false
    }

    // MARK: - Downtime Data

    private static let downtimeUserDefaultsKey = "downtime_data_v1"

    /// Reads downtime data, trying UserDefaults first, then file fallback.
    func loadDowntime() -> DowntimeData {
        // 1. Try UserDefaults first
        if let defaults = userDefaults,
           let data = defaults.data(forKey: SharedDataStore.downtimeUserDefaultsKey) {
            do {
                let decoded = try JSONDecoder().decode(DowntimeData.self, from: data)
                logger.info("Downtime UserDefaults read succeeded: \(decoded.windows.count) windows")
                return decoded
            } catch {
                logger.error("Downtime UserDefaults decode failed: \(error.localizedDescription)")
            }
        }

        // 2. Try direct file read
        let fileURL = AppConstants.downtimeFileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let fileData = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode(DowntimeData.self, from: fileData)
                logger.info("Downtime direct read succeeded: \(decoded.windows.count) windows")
                return decoded
            } catch {
                logger.error("Downtime direct read failed: \(error.localizedDescription)")
            }
        }

        return DowntimeData.empty
    }

    /// Writes downtime data to UserDefaults and file.
    func saveDowntime(_ data: DowntimeData) {
        // 1. UserDefaults
        do {
            let encoded = try JSONEncoder().encode(data)
            userDefaults?.set(encoded, forKey: SharedDataStore.downtimeUserDefaultsKey)
            logger.info("Downtime UserDefaults write succeeded: \(data.windows.count) windows")
        } catch {
            logger.error("Downtime UserDefaults encode failed: \(error.localizedDescription)")
        }

        // 2. File
        let fileURL = AppConstants.downtimeFileURL
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
            do {
                let encoded = try JSONEncoder().encode(data)
                try encoded.write(to: url, options: .atomic)
            } catch {
                self.logger.error("Failed to write downtime file: \(error.localizedDescription)")
            }
        }

        if let error = coordinatorError {
            logger.error("Downtime file coordinator write error: \(error.localizedDescription)")
        }
    }
}
