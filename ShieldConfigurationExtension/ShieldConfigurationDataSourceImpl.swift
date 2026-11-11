import ManagedSettings
import ManagedSettingsUI
import FamilyControls
import UIKit
import os.log

/// Provides the custom shield UI shown over blocked apps.
/// This extension runs in a separate process — all data comes from
/// the shared App Group container via `SharedDataStore`.
class ShieldConfigurationDataSourceImpl: ShieldConfigurationDataSource {

    private let logger = Logger(
        subsystem: "com.jonasreidel.openguard",
        category: "ShieldConfig"
    )

    // MARK: - Application Shield

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        logger.info("Configuring shield for application")

        // Diagnostic: check App Group availability
        let containerAvailable = AppConstants.isAppGroupAvailable
        let fileURL = AppConstants.blockListFileURL
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        logger.info("App Group available: \(containerAvailable), file exists: \(fileExists), path: \(fileURL.path)")

        let store = SharedDataStore.shared

        // Safety reset check. Shields are not touched from this (render-only)
        // extension; apps whose open window this clears are re-shielded by the
        // relock / ticker activities, which re-shield every app outside an
        // active open window.
        store.resetIfNewDay()

        // During an active downtime window, opens can't unblock the app, so show
        // a downtime shield without an "Open" button.
        if let downtime = store.loadDowntime().activeWindow() {
            let isAllowed = application.token.map { downtime.isExcluded($0) } ?? false
            if !isAllowed {
                return buildDowntimeConfiguration(for: downtime)
            }
        }

        // Match using decoded ApplicationToken equality (robust across processes)
        var matchedApp: BlockedApp?
        if let token = application.token {
            matchedApp = store.findApp(byApplicationToken: token)
            if matchedApp == nil {
                logger.warning("Token matching failed for application, trying byte comparison")
                // Fallback: try raw byte comparison
                if let tokenData = try? JSONEncoder().encode(token) {
                    matchedApp = store.findApp(byTokenData: tokenData)
                }
            }
        } else {
            logger.warning("Application token is nil")
        }

        let apps = store.loadAllApps()
        logger.info("Shield config: matched=\(matchedApp != nil), total apps=\(apps.count)")

        if let app = matchedApp {
            return buildConfiguration(for: app, applicationName: application.localizedDisplayName)
        } else {
            // Fallback: show generic shield with open button as safety net
            return buildFallbackConfiguration(appCount: apps.count)
        }
    }

    // MARK: - Application Category Shield

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: application)
    }

    // MARK: - Web Domain Shield

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return webDomainConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return webDomainConfiguration()
    }

    /// Web domains are only ever shielded by downtime.
    private func webDomainConfiguration() -> ShieldConfiguration {
        if let downtime = SharedDataStore.shared.loadDowntime().activeWindow() {
            return buildDowntimeConfiguration(for: downtime)
        }
        return buildFallbackConfiguration()
    }

    // MARK: - Configuration Builders

    private func buildConfiguration(for app: BlockedApp, applicationName: String? = nil) -> ShieldConfiguration {
        let title = ShieldConfiguration.Label(
            text: "This app is currently blocked",
            color: .white
        )

        let opensRemaining = app.opensRemaining
        let name = applicationName ?? app.displayName

        let subtitle = ShieldConfiguration.Label(
            text: "\(name)\n\(opensRemaining)/\(app.opensPerDay) opens left",
            color: UIColor.lightGray
        )

        // Primary button: "Open" — only if opens remain
        let primaryButton: ShieldConfiguration.Label?
        if opensRemaining > 0 {
            primaryButton = ShieldConfiguration.Label(
                text: "Open",
                color: .white
            )
        } else {
            primaryButton = nil
        }

        // Secondary button: always shown
        let secondaryButton = ShieldConfiguration.Label(
            text: "Get Back to Reality",
            color: UIColor(red: 0.2, green: 0.404, blue: 0.231, alpha: 1.0)
        )

        let appLogo = loadAppLogo()

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.black.withAlphaComponent(0.85),
            icon: appLogo,
            title: title,
            subtitle: subtitle,
            primaryButtonLabel: primaryButton,
            primaryButtonBackgroundColor: opensRemaining > 0 ? UIColor(red: 1.0, green: 0.0, blue: 0.208, alpha: 1.0) : nil,
            secondaryButtonLabel: secondaryButton
        )
    }

    private func buildDowntimeConfiguration(for window: DowntimeWindow) -> ShieldConfiguration {
        let title = ShieldConfiguration.Label(
            text: "Downtime is active",
            color: .white
        )

        let subtitle = ShieldConfiguration.Label(
            text: "All apps are blocked until \(String(format: "%d:%02d", window.endHour, window.endMinute)).",
            color: UIColor.lightGray
        )

        let secondaryButton = ShieldConfiguration.Label(
            text: "Get Back to Reality",
            color: UIColor(red: 0.2, green: 0.404, blue: 0.231, alpha: 1.0)
        )

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.black.withAlphaComponent(0.85),
            icon: loadAppLogo(),
            title: title,
            subtitle: subtitle,
            primaryButtonLabel: nil,
            primaryButtonBackgroundColor: nil,
            secondaryButtonLabel: secondaryButton
        )
    }

    private func loadAppLogo() -> UIImage? {
        let bundle = Bundle(for: ShieldConfigurationDataSourceImpl.self)
        if let logoURL = bundle.url(forResource: "AppLogo", withExtension: "png") {
            return UIImage(contentsOfFile: logoURL.path)
        }
        return UIImage(systemName: "lock.shield.fill")
    }

    private func buildFallbackConfiguration(appCount: Int = 0) -> ShieldConfiguration {
        let title = ShieldConfiguration.Label(
            text: "This app is currently blocked",
            color: .white
        )

        let subtitle = ShieldConfiguration.Label(
            text: appCount == 0 ? "No block list data found" : "Could not identify app",
            color: UIColor.lightGray
        )

        // Always show the secondary button
        let secondaryButton = ShieldConfiguration.Label(
            text: "Get Back to Reality",
            color: UIColor(red: 0.2, green: 0.404, blue: 0.231, alpha: 1.0)
        )

        let appLogo = loadAppLogo()

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.black.withAlphaComponent(0.85),
            icon: appLogo,
            title: title,
            subtitle: subtitle,
            primaryButtonLabel: nil,
            primaryButtonBackgroundColor: nil,
            secondaryButtonLabel: secondaryButton
        )
    }
}
