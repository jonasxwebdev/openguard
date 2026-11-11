import Foundation

/// Central constants shared across all targets via the App Group container.
enum AppConstants {
    // MARK: - App Group
    static let appGroupIdentifier = "group.com.jonasreidel.openguard"

    // MARK: - Persistence
    static let blockListFileName = "blocklist.json"
    static let iCloudBlockListKey = "blocklist_v1"
    static let onboardingCompletedKey = "onboarding_completed_v1"

    // MARK: - Downtime Persistence
    static let downtimeFileName = "downtime.json"
    static let downtimeDataKey = "downtime_data_v1"
    static let iCloudDowntimeKey = "downtime_v1"

    // MARK: - Device Activity Names
    static let dailyResetActivityName = "com.jonasreidel.openguard.dailyReset"
    static let tickerActivityName = "com.jonasreidel.openguard.ticker"

    // MARK: - Defaults
    static let defaultOpensPerDay: Int = 3
    static let defaultTimeLimitPerOpen: TimeInterval = 600  // 10 minutes

    // MARK: - DeviceActivity
    /// The shortest interval `DeviceActivityCenter.startMonitoring` accepts.
    /// Shorter schedules are rejected with `intervalTooShort`.
    static let minimumScheduleIntervalMinutes: Int = 15

    // MARK: - Notification Identifiers
    static let notificationCategoryOpen = "OPEN_WINDOW"
    static let notificationUnlockedSuffix = "-unlocked"
    static let notificationWarningSuffix = "-warning"
    static let notificationBlockedSuffix = "-blocked"
    static let notificationDowntimeStartSuffix = "-downtime-start"
    static let notificationDowntimeEndSuffix = "-downtime-end"

    // MARK: - Per-Open Relock Activity
    /// Prefix for DeviceActivity names used to re-shield apps when open windows expire.
    /// Each activity is named "<prefix><appUUID>".
    static let relockActivityPrefix = "com.jonasreidel.openguard.relock."

    // MARK: - Downtime Activity
    /// Prefix for DeviceActivity names used for downtime schedules.
    /// Each activity is named "<prefix><windowUUID>".
    static let downtimeActivityPrefix = "com.jonasreidel.openguard.downtime."

    // MARK: - Managed Settings Store
    /// The name of the managed settings store used for persistent shields.
    /// Using the default (unnamed) store for simplicity.
    /// All shield state is managed through a single store instance.

    // MARK: - Helpers
    /// Returns the shared App Group container URL.
    static var appGroupContainerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            // Log instead of crashing — extensions may have different sandbox rules
            let fallback = FileManager.default.temporaryDirectory
            return fallback
        }
        return url
    }

    /// Whether the App Group container is accessible.
    static var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) != nil
    }

    /// Returns the URL for the block list JSON file in the shared container.
    static var blockListFileURL: URL {
        appGroupContainerURL.appendingPathComponent(blockListFileName)
    }

    /// Returns the URL for the downtime JSON file in the shared container.
    static var downtimeFileURL: URL {
        appGroupContainerURL.appendingPathComponent(downtimeFileName)
    }
}
