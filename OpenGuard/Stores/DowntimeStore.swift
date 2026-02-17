import Foundation
import DeviceActivity
import ManagedSettings
import FamilyControls
import Combine
import os.log

/// Observable store for downtime windows. Drives the SwiftUI views
/// and manages DeviceActivity schedule registration.
@MainActor
final class DowntimeStore: ObservableObject {

    static let shared = DowntimeStore()

    @Published var windows: [DowntimeWindow] = []

    private let logger = Logger(subsystem: "com.jonasreidel.openguard", category: "DowntimeStore")

    private init() {
        reload()
    }

    // MARK: - Data Access

    /// Reloads windows from the shared data store.
    func reload() {
        windows = SharedDataStore.shared.loadDowntime().windows
    }

    // MARK: - CRUD

    /// Adds a new default downtime window and returns it for editing.
    func addWindow() -> DowntimeWindow {
        let window = DowntimeWindow.makeDefault()
        var data = SharedDataStore.shared.loadDowntime()
        data.windows.append(window)
        SharedDataStore.shared.saveDowntime(data)
        reload()
        scheduleAllActivities()
        syncToCloud()
        logger.info("Added downtime window \(window.id)")
        return window
    }

    /// Removes a downtime window by ID.
    func removeWindow(_ window: DowntimeWindow) {
        var data = SharedDataStore.shared.loadDowntime()
        data.windows.removeAll { $0.id == window.id }
        SharedDataStore.shared.saveDowntime(data)

        // Stop monitoring this specific activity
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName(AppConstants.downtimeActivityPrefix + window.id.uuidString)
        center.stopMonitoring([activityName])

        reload()
        syncToCloud()

        // If no windows remain active, remove downtime shields
        if !windows.contains(where: { $0.isEnabled }) {
            ShieldManager.shared.removeDowntimeShields()
        }

        logger.info("Removed downtime window \(window.id)")
    }

    /// Removes windows at the given index set (for List swipe-to-delete).
    func removeWindows(at offsets: IndexSet) {
        for index in offsets {
            removeWindow(windows[index])
        }
    }

    /// Updates a downtime window in-place.
    func updateWindow(_ window: DowntimeWindow) {
        var data = SharedDataStore.shared.loadDowntime()
        guard let index = data.windows.firstIndex(where: { $0.id == window.id }) else { return }
        data.windows[index] = window
        SharedDataStore.shared.saveDowntime(data)
        reload()
        scheduleAllActivities()
        syncToCloud()
        logger.info("Updated downtime window \(window.id)")
    }

    /// Toggles a window's enabled state.
    func toggleWindow(_ window: DowntimeWindow) {
        var updated = window
        updated.isEnabled.toggle()
        updateWindow(updated)

        // If disabling and no other windows are active, clear shields
        if !updated.isEnabled && !windows.contains(where: { $0.isEnabled }) {
            ShieldManager.shared.removeDowntimeShields()
        }
    }

    // MARK: - DeviceActivity Scheduling

    /// Registers DeviceActivity schedules for all enabled downtime windows.
    func scheduleAllActivities() {
        let center = DeviceActivityCenter()

        // Stop all existing downtime activities first
        let existingActivities = center.activities.filter {
            $0.rawValue.hasPrefix(AppConstants.downtimeActivityPrefix)
        }
        if !existingActivities.isEmpty {
            center.stopMonitoring(existingActivities)
        }

        // Register a schedule for each enabled window
        for window in windows where window.isEnabled {
            let activityName = DeviceActivityName(AppConstants.downtimeActivityPrefix + window.id.uuidString)

            let schedule = DeviceActivitySchedule(
                intervalStart: window.startDateComponents,
                intervalEnd: window.endDateComponents,
                repeats: true
            )

            do {
                try center.startMonitoring(activityName, during: schedule)
                logger.info("Registered downtime schedule: \(window.formattedTimeRange)")
            } catch {
                logger.error("Failed to register downtime schedule: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cloud Sync

    private func syncToCloud() {
        CloudSyncManager.shared.uploadDowntimeToCloud()
    }
}
