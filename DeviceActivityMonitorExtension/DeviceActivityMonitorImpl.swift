import DeviceActivity
import ManagedSettings
import os.log

/// Handles scheduled device activity events:
/// - Daily reset at midnight (resets all opens, re-applies shields)
/// - Ticker (checks for expired open windows and re-applies shields)
///
/// This extension runs in a separate process. All state is read/written
/// through the shared App Group container via `SharedDataStore`.
class DeviceActivityMonitorImpl: DeviceActivityMonitor {

    private let logger = Logger(
        subsystem: "com.jonasreidel.openguard",
        category: "ActivityMonitor"
    )

    // MARK: - Interval Callbacks

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.info("intervalDidStart: \(activity.rawValue)")

        // Per-open relock activities fire at the moment an open window expires
        if activity.rawValue.hasPrefix(AppConstants.relockActivityPrefix) {
            handleRelock(for: activity)
            return
        }

        // Downtime activities fire when a downtime window starts
        if activity.rawValue.hasPrefix(AppConstants.downtimeActivityPrefix) {
            handleDowntimeStart(for: activity)
            return
        }

        switch activity.rawValue {
        case AppConstants.dailyResetActivityName:
            handleDailyReset()

        case AppConstants.tickerActivityName:
            handleTicker()

        default:
            logger.info("Unknown activity started: \(activity.rawValue)")
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.info("intervalDidEnd: \(activity.rawValue)")

        // Downtime window ended
        if activity.rawValue.hasPrefix(AppConstants.downtimeActivityPrefix) {
            handleDowntimeEnd(for: activity)
            return
        }

        switch activity.rawValue {
        case AppConstants.tickerActivityName:
            // Also check on interval end for good measure
            handleTicker()

        default:
            break
        }
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        logger.info("intervalWillStartWarning: \(activity.rawValue)")
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        logger.info("intervalWillEndWarning: \(activity.rawValue)")

        // If the ticker is about to end, do a final check
        if activity.rawValue == AppConstants.tickerActivityName {
            handleTicker()
        }
    }

    // MARK: - Event Thresholds

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        logger.info("eventDidReachThreshold: \(event.rawValue) for \(activity.rawValue)")
    }

    // MARK: - Handlers

    /// Midnight reset: clear all opensUsedToday, re-apply all shields.
    private func handleDailyReset() {
        logger.info("Performing daily reset")

        // Reset all opens
        SharedDataStore.shared.resetAllOpens()

        // Re-apply shields to all blocked apps
        ShieldManager.shared.applyAllShields()

        // Cancel any lingering notifications from yesterday
        NotificationManager.shared.cancelAllNotifications()

        logger.info("Daily reset complete")
    }

    /// Ticker: check for expired open windows and re-shield.
    private func handleTicker() {
        // Also do a day-change safety check
        SharedDataStore.shared.resetIfNewDay()

        // Re-apply shields for any expired open windows
        ShieldManager.shared.reapplyExpiredShields()
    }

    // MARK: - Per-Open Relock

    /// Called when a per-open DeviceActivity fires at the exact expiry time.
    /// Re-applies shields for the expired app and stops monitoring this activity.
    private func handleRelock(for activity: DeviceActivityName) {
        logger.info("Handling relock for: \(activity.rawValue)")

        // Re-apply shields for all expired open windows (covers this app + any others)
        ShieldManager.shared.reapplyExpiredShields()

        // Stop monitoring this one-shot activity to free the slot
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])

        logger.info("Relock complete, stopped monitoring: \(activity.rawValue)")
    }

    // MARK: - Downtime Handlers

    /// Called when a downtime window starts — shield all apps except exclusions.
    private func handleDowntimeStart(for activity: DeviceActivityName) {
        let windowID = String(activity.rawValue.dropFirst(AppConstants.downtimeActivityPrefix.count))
        logger.info("Downtime started for window: \(windowID)")

        let downtimeData = SharedDataStore.shared.loadDowntime()
        guard let window = downtimeData.windows.first(where: { $0.id.uuidString == windowID }),
              window.isEnabled else {
            logger.info("Downtime window not found or disabled, skipping")
            return
        }

        // Check if this window applies today
        let currentWeekday = Calendar.current.component(.weekday, from: Date())
        guard window.appliesOn(currentWeekday) else {
            logger.info("Downtime window does not apply today (weekday \(currentWeekday))")
            return
        }

        let excludedTokens = window.excludedTokens()
        ShieldManager.shared.applyDowntimeShields(excluding: excludedTokens)
        logger.info("Downtime shields applied, excluding \(excludedTokens.count) app(s)")
    }

    /// Called when a downtime window ends — remove shields, unless another window is still active.
    private func handleDowntimeEnd(for activity: DeviceActivityName) {
        let windowID = String(activity.rawValue.dropFirst(AppConstants.downtimeActivityPrefix.count))
        logger.info("Downtime ended for window: \(windowID)")

        // Check if any other downtime window is still active before removing shields
        ShieldManager.shared.reapplyDowntimeIfNeeded()
    }
}
