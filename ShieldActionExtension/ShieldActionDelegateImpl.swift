import Foundation
import ManagedSettings
import ManagedSettingsUI
import FamilyControls
import DeviceActivity
import os.log

/// Handles user taps on shield buttons.
/// This extension runs in a separate process — all state updates go
/// through the shared App Group container via `SharedDataStore`.
class ShieldActionDelegateImpl: ShieldActionDelegate {

    private let logger = Logger(
        subsystem: "com.jonasreidel.openguard",
        category: "ShieldAction"
    )

    // MARK: - Handle Application Shield Actions

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        logger.info("Shield action triggered: \(action == .primaryButtonPressed ? "primary" : "secondary")")

        switch action {
        case .primaryButtonPressed:
            handleOpenAction(for: application, completionHandler: completionHandler)

        case .secondaryButtonPressed:
            // "Get Back to Reality" — just close
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    // MARK: - Handle Category Shield Actions

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        // For category-based shields, just close
        completionHandler(.close)
    }

    // MARK: - Handle Web Domain Shield Actions

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    // MARK: - Open Action Logic

    private func handleOpenAction(
        for applicationToken: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let store = SharedDataStore.shared

        // Safety reset check (re-shields if a reset happened)
        ShieldManager.shared.resetIfNewDayAndReshield()

        // During an active downtime window the app is also shielded by the
        // downtime store. Removing the per-app shield would not unblock it, so
        // don't let the user burn an open for nothing.
        if let downtime = store.loadDowntime().activeWindow(),
           !downtime.isExcluded(applicationToken) {
            logger.info("Downtime active — not consuming an open")
            completionHandler(.close)
            return
        }

        // Find the matching blocked app using decoded token equality
        var app = store.findApp(byApplicationToken: applicationToken)
        if app == nil {
            logger.warning("Token equality match failed, trying byte comparison")
            if let tokenData = try? JSONEncoder().encode(applicationToken) {
                app = store.findApp(byTokenData: tokenData)
            }
        }

        guard let app = app else {
            logger.error("App not found in block list (\(store.loadAllApps().count) apps in store)")
            completionHandler(.close)
            return
        }

        // Check if opens are available
        guard app.opensRemaining > 0 else {
            logger.info("No opens remaining for \(app.displayName)")
            completionHandler(.close)
            return
        }

        // Consume one open
        guard let updatedApp = store.consumeOpen(for: app.id) else {
            logger.error("Failed to consume open for \(app.displayName)")
            completionHandler(.close)
            return
        }

        logger.info("Open consumed for \(updatedApp.displayName): \(updatedApp.opensUsedToday)/\(updatedApp.opensPerDay)")

        // Remove the shield for this app (unblock it)
        ShieldManager.shared.removeShield(for: applicationToken)

        // Schedule notifications for the open window
        NotificationManager.shared.scheduleOpenWindowNotifications(
            appID: updatedApp.id,
            appName: updatedApp.displayName,
            duration: updatedApp.timeLimitPerOpen
        )

        // Schedule a DeviceActivity to re-apply the shield at expiry
        scheduleRelockActivity(appID: updatedApp.id, duration: updatedApp.timeLimitPerOpen)

        // Close the shield view — the app is now unblocked
        completionHandler(.close)
    }

    // MARK: - Relock Scheduling

    /// Schedules a one-shot DeviceActivity whose `intervalDidStart` fires at
    /// the moment the open window expires, triggering the DeviceActivityMonitor
    /// extension to re-apply the shield.
    private func scheduleRelockActivity(appID: UUID, duration: TimeInterval) {
        let expiryDate = Date().addingTimeInterval(duration)
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: expiryDate)

        // The interval must be at least the DeviceActivity minimum (15 min),
        // otherwise `startMonitoring` throws `intervalTooShort`. A fixed end of
        // 23:59:59 broke every open whose window expired after ~23:45. The end
        // may wrap past midnight, which DeviceActivity handles as an overnight
        // interval.
        let endDate = expiryDate.addingTimeInterval(
            TimeInterval((AppConstants.minimumScheduleIntervalMinutes + 1) * 60)
        )
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)

        let activityName = DeviceActivityName(
            AppConstants.relockActivityPrefix + appID.uuidString
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        let center = DeviceActivityCenter()
        do {
            try center.startMonitoring(activityName, during: schedule)
            logger.info("Scheduled relock activity for \(appID) at \(startComponents)")
        } catch {
            logger.error("Failed to schedule relock activity: \(error.localizedDescription)")
        }
    }
}
