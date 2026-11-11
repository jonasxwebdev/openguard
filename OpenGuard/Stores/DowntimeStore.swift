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

    /// Persists a new downtime window (called when the user saves a new window).
    func addWindow(_ window: DowntimeWindow) {
        var data = SharedDataStore.shared.loadDowntime()
        guard !data.windows.contains(where: { $0.id == window.id }) else {
            updateWindow(window)
            return
        }
        data.windows.append(window)
        SharedDataStore.shared.saveDowntime(data)
        reload()
        scheduleAllActivities()
        syncToCloud()
        ShieldManager.shared.reapplyDowntimeIfNeeded()
        logger.info("Added downtime window \(window.id)")
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

        // Re-evaluate shields: removes them if the deleted window was the
        // active one, keeps them if another window is still active.
        ShieldManager.shared.reapplyDowntimeIfNeeded()

        logger.info("Removed downtime window \(window.id)")
    }

    /// Removes windows at the given index set (for List swipe-to-delete).
    func removeWindows(at offsets: IndexSet) {
        // Resolve windows first: `removeWindow` reloads `windows`, which would
        // shift the remaining indices.
        let windowsToRemove = offsets.compactMap { windows.indices.contains($0) ? windows[$0] : nil }
        for window in windowsToRemove {
            removeWindow(window)
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

        // Apply/remove/refresh shields if the change affects a window that is
        // active right now (time, days, allowed apps or enabled state changed).
        ShieldManager.shared.reapplyDowntimeIfNeeded()
        logger.info("Updated downtime window \(window.id)")
    }

    /// Toggles a window's enabled state.
    func toggleWindow(_ window: DowntimeWindow) {
        // Use the latest stored copy so the toggle doesn't overwrite other edits.
        var updated = windows.first(where: { $0.id == window.id }) ?? window
        updated.isEnabled.toggle()
        updateWindow(updated)
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
