import SwiftUI
import FamilyControls
import DeviceActivity
import os.log

@main
struct OpenGuardApp: App {
    @StateObject private var blockListStore = BlockListStore.shared
    @StateObject private var cloudSync = CloudSyncManager.shared
    @StateObject private var downtimeStore = DowntimeStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private let logger = Logger(subsystem: "com.jonasreidel.openguard", category: "App")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(blockListStore)
                .environmentObject(cloudSync)
                .environmentObject(downtimeStore)
                .task {
                    await initialize()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The extensions update state (opens consumed, windows expired,
            // daily reset) while the app is in the background. Refresh when
            // returning to the foreground so the UI isn't stale.
            // (Returning from the background goes background → inactive → active,
            // so check only the new phase.)
            if newPhase == .active {
                refreshOnForeground()
            }
        }
    }

    private func refreshOnForeground() {
        ShieldManager.shared.resetIfNewDayAndReshield()
        ShieldManager.shared.reapplyExpiredShields()
        blockListStore.reload()
        downtimeStore.reload()
    }

    private func initialize() async {
        logger.info("OpenGuard initializing...")

        // Safety reset if a new day has started
        SharedDataStore.shared.resetIfNewDay()

        // Attempt iCloud restore on first launch after reinstall
        cloudSync.restoreFromCloudIfNeeded()
        cloudSync.restoreDowntimeFromCloudIfNeeded()

        // Reload from disk
        blockListStore.reload()
        downtimeStore.reload()

        // Register device activity schedules
        registerSchedules()
        downtimeStore.scheduleAllActivities()

        // Re-apply shields (ensures consistency after reboot/reinstall)
        ShieldManager.shared.applyAllShields()

        // Check if we're currently inside a downtime window
        ShieldManager.shared.reapplyDowntimeIfNeeded()

        logger.info("OpenGuard initialized with \(blockListStore.apps.count) blocked app(s), \(downtimeStore.windows.count) downtime window(s)")
    }

    /// Registers the daily reset and ticker device activity schedules.
    private func registerSchedules() {
        let center = DeviceActivityCenter()

        // Daily reset: midnight to 23:59, repeating
        let dailyResetSchedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )

        do {
            try center.startMonitoring(
                DeviceActivityName(AppConstants.dailyResetActivityName),
                during: dailyResetSchedule
            )
            logger.info("Registered daily reset schedule")
        } catch {
            logger.error("Failed to register daily reset: \(error.localizedDescription)")
        }

        // Ticker: repeating short interval to check for expired open windows
        // Using a 15-minute interval (known safe minimum for DeviceActivitySchedule)
        // with a fallback approach
        registerTickerSchedule(center: center)
    }

    private func registerTickerSchedule(center: DeviceActivityCenter) {
        // Attempt progressively longer intervals until one is accepted
        let intervals: [(start: DateComponents, end: DateComponents)] = [
            // Try 1-minute intervals first (using alternating minute marks)
            (DateComponents(hour: 0, minute: 0, second: 0),
             DateComponents(hour: 0, minute: 14, second: 59)),
        ]

        for interval in intervals {
            let schedule = DeviceActivitySchedule(
                intervalStart: interval.start,
                intervalEnd: interval.end,
                repeats: true
            )

            do {
                try center.startMonitoring(
                    DeviceActivityName(AppConstants.tickerActivityName),
                    during: schedule
                )
                logger.info("Registered ticker schedule")
                return
            } catch {
                logger.warning("Ticker schedule rejected: \(error.localizedDescription)")
            }
        }

        logger.error("Could not register any ticker schedule — open windows may not auto-expire on time")
    }
}
