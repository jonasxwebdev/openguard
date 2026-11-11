import SwiftUI
import FamilyControls
import ManagedSettings

/// Detail/edit view for a single downtime window.
struct DowntimeDetailView: View {
    @EnvironmentObject var downtimeStore: DowntimeStore
    @Environment(\.dismiss) private var dismiss

    @State var window: DowntimeWindow
    let isNew: Bool

    @State private var isEveryDay: Bool
    @State private var selectedDays: Set<Int>
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var showingExclusionPicker = false
    @State private var exclusionSelection = FamilyActivitySelection()

    private var weekdays: [(Int, String)] {
        let symbols = Calendar.current.weekdaySymbols // Sunday first
        // Reorder to Monday first for display
        let reordered = Array(2...7) + [1]
        return reordered.map { ($0, symbols[$0 - 1]) }
    }

    init(window: DowntimeWindow, isNew: Bool = false) {
        _window = State(initialValue: window)
        self.isNew = isNew
        _isEveryDay = State(initialValue: window.isEveryDay)
        _selectedDays = State(initialValue: window.activeDays)
        _showingExclusionPicker = State(initialValue: false)
        _exclusionSelection = State(initialValue: FamilyActivitySelection())

        // Convert hour/minute to Date for DatePicker
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _startTime = State(initialValue: calendar.date(bySettingHour: window.startHour, minute: window.startMinute, second: 0, of: today) ?? today)
        _endTime = State(initialValue: calendar.date(bySettingHour: window.endHour, minute: window.endMinute, second: 0, of: today) ?? today)
    }

    var body: some View {
        Form {
            // MARK: - Time
            Section {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
            } header: {
                Text("Time")
            } footer: {
                if durationMinutes < AppConstants.minimumScheduleIntervalMinutes {
                    Text("Downtime must last at least \(AppConstants.minimumScheduleIntervalMinutes) minutes.")
                        .foregroundStyle(.red)
                }
            }

            // MARK: - Repeat
            Section {
                Toggle("Every Day", isOn: $isEveryDay)

                if !isEveryDay {
                    ForEach(weekdays, id: \.0) { weekday, name in
                        Button {
                            if selectedDays.contains(weekday) {
                                selectedDays.remove(weekday)
                            } else {
                                selectedDays.insert(weekday)
                            }
                        } label: {
                            HStack {
                                Text(name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedDays.contains(weekday) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Repeat")
            } footer: {
                if !isEveryDay && selectedDays.isEmpty {
                    Text("Select at least one day.")
                        .foregroundStyle(.red)
                }
            }

            // MARK: - Allowed Apps (Exclusions)
            Section {
                if window.excludedAppTokensData.isEmpty {
                    Text("All apps will be blocked during this time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(window.excludedAppTokensData.enumerated()), id: \.offset) { index, tokenData in
                        HStack {
                            if let token = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) {
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .font(.body)
                                    .lineLimit(1)
                            } else {
                                Label(window.excludedAppNames.indices.contains(index) ? window.excludedAppNames[index] : "Unknown App", systemImage: "app.fill")
                                    .font(.body)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                removeExcludedApp(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    showingExclusionPicker = true
                } label: {
                    Label("Add Allowed App", systemImage: "plus.circle")
                }
            } header: {
                Text("Allowed Apps")
            } footer: {
                Text("These apps will remain accessible during this downtime window.")
            }
        }
        .navigationTitle(isNew ? "New Downtime" : "Edit Downtime")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(!isValid)
            }

            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // New windows aren't persisted until saved — nothing to clean up
                        dismiss()
                    }
                }
            }
        }
        .familyActivityPicker(
            isPresented: $showingExclusionPicker,
            selection: $exclusionSelection
        )
        .onChange(of: exclusionSelection) { _, newValue in
            // Resetting the selection below re-triggers onChange with an empty value
            guard !newValue.applicationTokens.isEmpty else { return }
            addExcludedApps(from: newValue)
            exclusionSelection = FamilyActivitySelection()
        }
    }

    // MARK: - Validation

    /// Length of the edited window in minutes (handles windows crossing midnight).
    private var durationMinutes: Int {
        let calendar = Calendar.current
        let start = calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
        let end = calendar.component(.hour, from: endTime) * 60 + calendar.component(.minute, from: endTime)
        return (end - start + 24 * 60) % (24 * 60)
    }

    /// DeviceActivity rejects schedules shorter than 15 minutes, and an empty
    /// day selection would silently turn into "every day".
    private var isValid: Bool {
        durationMinutes >= AppConstants.minimumScheduleIntervalMinutes
            && (isEveryDay || !selectedDays.isEmpty)
    }

    // MARK: - Actions

    private func save() {
        guard isValid else { return }
        let calendar = Calendar.current
        window.startHour = calendar.component(.hour, from: startTime)
        window.startMinute = calendar.component(.minute, from: startTime)
        window.endHour = calendar.component(.hour, from: endTime)
        window.endMinute = calendar.component(.minute, from: endTime)
        window.activeDays = isEveryDay ? [] : selectedDays

        if isNew {
            downtimeStore.addWindow(window)
        } else {
            // Keep the enabled state the user may have toggled in the list
            // while this editor was open.
            if let stored = downtimeStore.windows.first(where: { $0.id == window.id }) {
                window.isEnabled = stored.isEnabled
            }
            downtimeStore.updateWindow(window)
        }
        dismiss()
    }

    private func addExcludedApps(from selection: FamilyActivitySelection) {
        for token in selection.applicationTokens {
            guard let tokenData = try? JSONEncoder().encode(token) else { continue }

            // Skip duplicates (compare decoded tokens — encoded bytes may differ)
            if window.excludedAppTokensData.contains(tokenData) || window.excludedTokens().contains(token) { continue }

            window.excludedAppTokensData.append(tokenData)
            window.excludedAppNames.append("App") // Generic name — token renders as label in shield
        }
    }

    private func removeExcludedApp(at index: Int) {
        guard window.excludedAppTokensData.indices.contains(index) else { return }
        window.excludedAppTokensData.remove(at: index)
        // Names are a parallel array that may be shorter (e.g. older data)
        if window.excludedAppNames.indices.contains(index) {
            window.excludedAppNames.remove(at: index)
        }
    }
}

#Preview {
    NavigationStack {
        DowntimeDetailView(window: DowntimeWindow.makeDefault(), isNew: true)
            .environmentObject(DowntimeStore.shared)
    }
}
