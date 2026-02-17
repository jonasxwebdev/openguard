import Foundation
import ManagedSettings
import FamilyControls
import os.log

/// Manages shield application/removal via `ManagedSettingsStore`.
/// Used by the main app, Shield Action extension, and Device Activity Monitor extension.
///
/// Uses a single unnamed `ManagedSettingsStore` — the shield.applications set
/// is dynamically adjusted to add/remove individual apps during open windows.
final class ShieldManager {

    static let shared = ShieldManager()

    private let store = ManagedSettingsStore()
    private let logger = Logger(subsystem: "com.jonasreidel.openguard", category: "ShieldManager")

    private init() {}

    // MARK: - Apply Shields

    /// Applies shields to all apps currently in the block list.
    /// Called on app launch, after daily reset, and after open window expiry.
    func applyAllShields() {
        let apps = SharedDataStore.shared.loadAllApps()
        let tokens = resolveTokens(from: apps, excludeOpenWindows: true)

        if tokens.isEmpty {
            store.shield.applications = nil
        } else {
            store.shield.applications = tokens
        }

        logger.info("Applied shields to \(tokens.count) app(s)")
    }

    /// Applies shields to a specific set of application tokens.
    func applyShields(for tokens: Set<ApplicationToken>) {
        if tokens.isEmpty {
            store.shield.applications = nil
        } else {
            // Merge with any existing shields
            var current = store.shield.applications ?? Set<ApplicationToken>()
            current.formUnion(tokens)
            store.shield.applications = current
        }
    }

    /// Adds a single app's shield.
    func addShield(for token: ApplicationToken) {
        var current = store.shield.applications ?? Set<ApplicationToken>()
        current.insert(token)
        store.shield.applications = current
        logger.info("Added shield for 1 app")
    }

    // MARK: - Remove Shields

    /// Removes the shield for a single app (during an open window).
    func removeShield(for token: ApplicationToken) {
        guard var current = store.shield.applications else { return }
        current.remove(token)
        store.shield.applications = current.isEmpty ? nil : current
        logger.info("Removed shield for 1 app (open window)")
    }

    /// Removes all shields (e.g., on authorization revocation).
    func removeAllShields() {
        store.shield.applications = nil
        logger.info("Removed all shields")
    }

    // MARK: - Downtime Shields

    /// Separate store for downtime shields so they don't interfere with per-app block list shields.
    private let downtimeStore = ManagedSettingsStore(named: .init("downtime"))

    /// Applies downtime shields — blocks ALL app categories except excluded tokens.
    /// Uses `shield.applicationCategories` with `.all(except:)` to block everything.
    func applyDowntimeShields(excluding excludedTokens: Set<ApplicationToken>) {
        if excludedTokens.isEmpty {
            downtimeStore.shield.applicationCategories = .all()
        } else {
            downtimeStore.shield.applicationCategories = .all(except: excludedTokens)
        }
        downtimeStore.shield.webDomainCategories = .all()
        logger.info("Applied downtime shields (excluding \(excludedTokens.count) app(s))")
    }

    /// Removes all downtime shields — called when a downtime window ends.
    func removeDowntimeShields() {
        downtimeStore.shield.applicationCategories = nil
        downtimeStore.shield.webDomainCategories = nil
        logger.info("Removed downtime shields")
    }

    /// Checks if any downtime window is currently active and re-applies shields if needed.
    /// Called when one window ends but another may still be active.
    func reapplyDowntimeIfNeeded() {
        let downtimeData = SharedDataStore.shared.loadDowntime()
        let now = Date()
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: now)
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTotalMinutes = currentHour * 60 + currentMinute

        for window in downtimeData.windows where window.isEnabled && window.appliesOn(currentWeekday) {
            let startTotal = window.startHour * 60 + window.startMinute
            let endTotal = window.endHour * 60 + window.endMinute

            let isActive: Bool
            if startTotal <= endTotal {
                // Same-day window (e.g. 7:00–8:30)
                isActive = currentTotalMinutes >= startTotal && currentTotalMinutes < endTotal
            } else {
                // Overnight window (e.g. 22:00–6:00)
                isActive = currentTotalMinutes >= startTotal || currentTotalMinutes < endTotal
            }

            if isActive {
                // Another window is still active — re-apply its shields
                applyDowntimeShields(excluding: window.excludedTokens())
                return
            }
        }

        // No active windows — remove shields
        removeDowntimeShields()
    }

    // MARK: - Re-shield After Open Window

    /// Re-applies the shield for a specific app after its open window expires.
    func reapplyShield(for app: BlockedApp) {
        guard let token = app.applicationToken() else {
            logger.error("Could not decode token for app \(app.displayName)")
            return
        }
        addShield(for: token)
    }

    /// Checks for expired open windows and re-applies shields.
    /// Called by the ticker in the Device Activity Monitor extension.
    func reapplyExpiredShields() {
        let expired = SharedDataStore.shared.expireOpenWindows()
        for app in expired {
            reapplyShield(for: app)
        }
        if !expired.isEmpty {
            logger.info("Re-applied shields for \(expired.count) expired window(s)")
        }
    }

    // MARK: - Helpers

    /// Resolves `ApplicationToken`s from a list of `BlockedApp`s.
    /// Optionally excludes apps that are currently in an active open window.
    private func resolveTokens(
        from apps: [BlockedApp],
        excludeOpenWindows: Bool = false
    ) -> Set<ApplicationToken> {
        var tokens = Set<ApplicationToken>()
        for app in apps {
            if excludeOpenWindows && app.isInOpenWindow {
                continue
            }
            if let token = app.applicationToken() {
                tokens.insert(token)
            }
        }
        return tokens
    }
}
