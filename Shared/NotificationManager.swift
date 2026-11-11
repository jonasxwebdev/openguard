import Foundation
import UserNotifications
import os.log

/// Manages local notifications for open window events.
/// Used by the Shield Action extension and the main app.
final class NotificationManager {

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.jonasreidel.openguard", category: "Notifications")

    private init() {}

    // MARK: - Permission

    /// Requests notification authorization. Call from the main app during onboarding.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Notification auth error: \(error.localizedDescription)")
            return false
        }
    }

    /// Whether notifications are currently authorized.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    // MARK: - Open Window Notifications

    /// Schedules the three notifications for an open window:
    /// 1. Immediate: "App unlocked! You have X minutes."
    /// 2. 30 seconds before expiry: "App will be blocked again in 30 seconds."
    /// 3. At expiry: "App is now blocked again."
    func scheduleOpenWindowNotifications(
        appID: UUID,
        appName: String,
        duration: TimeInterval
    ) {
        let identifier = appID.uuidString

        // 1. Immediate notification
        let immediateContent = UNMutableNotificationContent()
        immediateContent.title = "🔓 \(appName) Unlocked"
        let minutes = Int(duration / 60)
        immediateContent.body = "You have \(minutes) minute\(minutes == 1 ? "" : "s")."
        immediateContent.sound = .default

        let immediateTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let immediateRequest = UNNotificationRequest(
            identifier: identifier + AppConstants.notificationUnlockedSuffix,
            content: immediateContent,
            trigger: immediateTrigger
        )

        // 2. Warning notification (30 seconds before expiry)
        let warningContent = UNMutableNotificationContent()
        warningContent.title = "⏳ \(appName)"
        warningContent.body = "Will be blocked again in 30 seconds."
        warningContent.sound = .default

        let warningInterval = max(1, duration - 30)
        let warningTrigger = UNTimeIntervalNotificationTrigger(timeInterval: warningInterval, repeats: false)
        let warningRequest = UNNotificationRequest(
            identifier: identifier + AppConstants.notificationWarningSuffix,
            content: warningContent,
            trigger: warningTrigger
        )

        // 3. Blocked notification (at expiry)
        let blockedContent = UNMutableNotificationContent()
        blockedContent.title = "🔒 \(appName)"
        blockedContent.body = "This app is now blocked again."
        blockedContent.sound = .default

        let blockedTrigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        let blockedRequest = UNNotificationRequest(
            identifier: identifier + AppConstants.notificationBlockedSuffix,
            content: blockedContent,
            trigger: blockedTrigger
        )

        // Schedule all three
        center.add(immediateRequest) { [weak self] error in
            if let error { self?.logger.error("Failed to schedule unlock notification: \(error.localizedDescription)") }
        }
        center.add(warningRequest) { [weak self] error in
            if let error { self?.logger.error("Failed to schedule warning notification: \(error.localizedDescription)") }
        }
        center.add(blockedRequest) { [weak self] error in
            if let error { self?.logger.error("Failed to schedule blocked notification: \(error.localizedDescription)") }
        }

        logger.info("Scheduled 3 notifications for \(appName) (duration: \(minutes)m)")
    }

    // MARK: - Cancel

    /// Cancels all pending notifications for a specific app.
    func cancelNotifications(for appID: UUID) {
        let identifier = appID.uuidString
        let ids = [
            identifier + AppConstants.notificationUnlockedSuffix,
            identifier + AppConstants.notificationWarningSuffix,
            identifier + AppConstants.notificationBlockedSuffix
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        logger.info("Cancelled notifications for app \(appID)")
    }

    // MARK: - Downtime Notifications

    /// Sends a notification when a downtime window starts.
    func scheduleDowntimeStartNotification(windowID: UUID, timeRange: String) {
        let content = UNMutableNotificationContent()
        content.title = "🌙 Downtime Started"
        content.body = "All apps are now blocked (\(timeRange)). Only your allowed apps remain accessible."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: windowID.uuidString + AppConstants.notificationDowntimeStartSuffix,
            content: content,
            trigger: trigger
        )

        center.add(request) { [weak self] error in
            if let error { self?.logger.error("Failed to schedule downtime start notification: \(error.localizedDescription)") }
        }

        logger.info("Scheduled downtime start notification for \(timeRange)")
    }

    /// Sends a notification when a downtime window ends.
    func scheduleDowntimeEndNotification(windowID: UUID, timeRange: String) {
        let content = UNMutableNotificationContent()
        content.title = "☀️ Downtime Ended"
        content.body = "The downtime window (\(timeRange)) has ended. All apps are accessible again."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: windowID.uuidString + AppConstants.notificationDowntimeEndSuffix,
            content: content,
            trigger: trigger
        )

        center.add(request) { [weak self] error in
            if let error { self?.logger.error("Failed to schedule downtime end notification: \(error.localizedDescription)") }
        }

        logger.info("Scheduled downtime end notification for \(timeRange)")
    }

    /// Cancels downtime notifications for a specific window.
    func cancelDowntimeNotifications(for windowID: UUID) {
        let ids = [
            windowID.uuidString + AppConstants.notificationDowntimeStartSuffix,
            windowID.uuidString + AppConstants.notificationDowntimeEndSuffix
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Cancels all pending OpenGuard notifications.
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
