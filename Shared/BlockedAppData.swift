import Foundation
import FamilyControls
import ManagedSettings

// MARK: - BlockedApp

/// Represents a single app the user has added to their block list.
/// Persisted as JSON in the shared App Group container.
struct BlockedApp: Codable, Identifiable, Equatable {
    /// Unique identifier for this block entry.
    let id: UUID

    /// The encoded `ApplicationToken` from FamilyControls.
    /// Serialized via JSONEncoder so it can be stored in JSON.
    let applicationTokenData: Data

    /// User-facing display name for the app.
    var displayName: String

    /// How many times per day the user can unblock this app.
    var opensPerDay: Int

    /// Duration of each unblock window in seconds.
    var timeLimitPerOpen: TimeInterval

    /// How many opens have been consumed today (resets at midnight).
    var opensUsedToday: Int

    /// If non-nil, the app is currently in an open window that expires at this date.
    var currentOpenExpiresAt: Date?

    // MARK: - Computed

    /// Number of opens remaining today.
    var opensRemaining: Int {
        max(0, opensPerDay - opensUsedToday)
    }

    /// Whether the user has used all opens for today.
    var isExhausted: Bool {
        opensRemaining <= 0
    }

    /// Whether the app is currently in an active (unexpired) open window.
    var isInOpenWindow: Bool {
        guard let expiresAt = currentOpenExpiresAt else { return false }
        return Date() < expiresAt
    }

    // MARK: - Token Helpers

    /// Decodes the stored token data back to an `ApplicationToken`.
    func applicationToken() -> ApplicationToken? {
        try? JSONDecoder().decode(ApplicationToken.self, from: applicationTokenData)
    }

    /// Creates a `BlockedApp` from an `ApplicationToken`.
    static func create(
        from token: ApplicationToken,
        displayName: String,
        opensPerDay: Int = AppConstants.defaultOpensPerDay,
        timeLimitPerOpen: TimeInterval = AppConstants.defaultTimeLimitPerOpen
    ) -> BlockedApp? {
        guard let tokenData = try? JSONEncoder().encode(token) else { return nil }
        return BlockedApp(
            id: UUID(),
            applicationTokenData: tokenData,
            displayName: displayName,
            opensPerDay: opensPerDay,
            timeLimitPerOpen: timeLimitPerOpen,
            opensUsedToday: 0,
            currentOpenExpiresAt: nil
        )
    }
}

// MARK: - BlockListData

/// Top-level wrapper for the persisted block list.
/// This is the object serialized to/from the shared JSON file.
struct BlockListData: Codable {
    var apps: [BlockedApp]
    var lastResetDate: Date  // Tracks the last midnight reset

    static var empty: BlockListData {
        BlockListData(apps: [], lastResetDate: Date())
    }
}
