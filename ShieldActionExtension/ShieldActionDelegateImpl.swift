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

        // Safety reset check
        store.resetIfNewDay()

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

        let activityName = DeviceActivityName(
            AppConstants.relockActivityPrefix + appID.uuidString
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
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
