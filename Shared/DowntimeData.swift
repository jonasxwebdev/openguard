import Foundation
import ManagedSettings

// MARK: - DowntimeWindow

/// Represents a single downtime window during which all apps are blocked
/// except those on the exclusion list.
struct DowntimeWindow: Codable, Identifiable, Equatable {
    let id: UUID

    /// Start time — hour component (0–23).
    var startHour: Int
    /// Start time — minute component (0–59).
    var startMinute: Int

    /// End time — hour component (0–23).
    var endHour: Int
    /// End time — minute component (0–59).
    var endMinute: Int

    /// Days of the week this window is active (Calendar weekday: 1=Sun…7=Sat).
    /// Empty means every day.
    var activeDays: Set<Int>

    /// Whether this window is currently enabled.
    var isEnabled: Bool

    /// Encoded `ApplicationToken` data for apps excluded from this downtime.
    var excludedAppTokensData: [Data]

    /// Display names for excluded apps (parallel array with `excludedAppTokensData`).
    var excludedAppNames: [String]

    // MARK: - Computed

    /// Whether this window applies every day (no specific days selected).
    var isEveryDay: Bool {
        activeDays.isEmpty
    }

    /// Whether this window applies on the given Calendar weekday (1=Sun…7=Sat).
    func appliesOn(_ weekday: Int) -> Bool {
        isEveryDay || activeDays.contains(weekday)
    }

    /// `DateComponents` for the start time.
    var startDateComponents: DateComponents {
        DateComponents(hour: startHour, minute: startMinute)
    }

    /// `DateComponents` for the end time.
    var endDateComponents: DateComponents {
        DateComponents(hour: endHour, minute: endMinute)
    }

    /// Formatted time string, e.g. "7:00 – 8:30".
    var formattedTimeRange: String {
        let start = String(format: "%d:%02d", startHour, startMinute)
        let end = String(format: "%d:%02d", endHour, endMinute)
        return "\(start) – \(end)"
    }

    /// Human-readable days summary.
    var formattedDays: String {
        if isEveryDay { return "Every Day" }

        let weekdaySymbols = Calendar.current.shortWeekdaySymbols // ["Sun","Mon",...]
        let sorted = activeDays.sorted()

        // Check common presets
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let weekend: Set<Int> = [1, 7]
        if activeDays == weekdays { return "Weekdays" }
        if activeDays == weekend { return "Weekends" }

        return sorted.map { weekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }

    /// Start time expressed as minutes since midnight.
    var startTotalMinutes: Int { startHour * 60 + startMinute }

    /// End time expressed as minutes since midnight.
    var endTotalMinutes: Int { endHour * 60 + endMinute }

    /// Length of the window in minutes, accounting for windows that cross midnight.
    /// A window whose start equals its end has a duration of 0.
    var durationMinutes: Int {
        (endTotalMinutes - startTotalMinutes + 24 * 60) % (24 * 60)
    }

    /// Whether the window crosses midnight (e.g. 22:00 – 6:00).
    var isOvernight: Bool {
        endTotalMinutes < startTotalMinutes
    }

    /// Whether this window is active at the given date.
    ///
    /// For overnight windows, the portion after midnight belongs to the day the
    /// window *started* on, so e.g. a Friday-only 22:00 – 6:00 window is active
    /// on Saturday at 2:00, but not on Friday at 2:00.
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, durationMinutes > 0 else { return false }

        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)

        if !isOvernight {
            return appliesOn(weekday)
                && minutes >= startTotalMinutes
                && minutes < endTotalMinutes
        }

        // Before midnight: belongs to today.
        if minutes >= startTotalMinutes && appliesOn(weekday) {
            return true
        }
        // After midnight: belongs to the previous day.
        let previousWeekday = weekday == 1 ? 7 : weekday - 1
        return minutes < endTotalMinutes && appliesOn(previousWeekday)
    }

    /// Whether the given application token is on this window's allow list.
    func isExcluded(_ token: ApplicationToken) -> Bool {
        excludedTokens().contains(token)
    }

    /// Decodes excluded app tokens.
    func excludedTokens() -> Set<ApplicationToken> {
        var tokens = Set<ApplicationToken>()
        for data in excludedAppTokensData {
            if let token = try? JSONDecoder().decode(ApplicationToken.self, from: data) {
                tokens.insert(token)
            }
        }
        return tokens
    }

    /// Creates a default new window (e.g. 7:00 – 8:30, every day, enabled).
    static func makeDefault() -> DowntimeWindow {
        DowntimeWindow(
            id: UUID(),
            startHour: 7,
            startMinute: 0,
            endHour: 8,
            endMinute: 30,
            activeDays: [],
            isEnabled: true,
            excludedAppTokensData: [],
            excludedAppNames: []
        )
    }
}

// MARK: - DowntimeData

/// Top-level wrapper for all downtime windows, persisted to shared storage.
struct DowntimeData: Codable {
    var windows: [DowntimeWindow]

    static var empty: DowntimeData {
        DowntimeData(windows: [])
    }

    /// Returns the first enabled window that is active at the given date,
    /// optionally ignoring a specific window (e.g. one that is just ending).
    func activeWindow(at date: Date = Date(), excluding excludedID: UUID? = nil) -> DowntimeWindow? {
        windows.first { window in
            window.id != excludedID && window.isActive(at: date)
        }
    }
}
