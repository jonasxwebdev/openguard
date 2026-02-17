import SwiftUI
import FamilyControls

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

    private let weekdays: [(Int, String)] = {
        let symbols = Calendar.current.weekdaySymbols // Sunday first
        // Reorder to Monday first for display
        let reordered = Array(2...7) + [1]
        return reordered.map { ($0, symbols[$0 - 1]) }
    }()

    init(window: DowntimeWindow, isNew: Bool = false) {
        _window = State(initialValue: window)
        _isEveryDay = State(initialValue: window.isEveryDay)
        _selectedDays = State(initialValue: window.activeDays)

        // Convert hour/minute to Date for DatePicker
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _startTime = State(initialValue: calendar.date(bySettingHour: window.startHour, minute: window.startMinute, second: 0, of: today) ?? today)
        _endTime = State(initialValue: calendar.date(bySettingHour: window.endHour, minute: window.endMinute, second: 0, of: today) ?? today)
    }

    var body: some View {
        Form {
            // MARK: - Time
            Section("Time") {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
            }

            // MARK: - Repeat
            Section("Repeat") {
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
            }

            // MARK: - Allowed Apps (Exclusions)
            Section {
                if window.excludedAppNames.isEmpty {
                    Text("All apps will be blocked during this time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(zip(window.excludedAppNames, window.excludedAppNames.indices)), id: \.1) { name, index in
                        HStack {
                            Text(name)
                            Spacer()
                            Button {
                                removeExcludedApp(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
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
            }

            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Remove the window that was pre-added
                        downtimeStore.removeWindow(window)
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
            addExcludedApps(from: newValue)
            exclusionSelection = FamilyActivitySelection()
        }
    }

    // MARK: - Actions

    private func save() {
        let calendar = Calendar.current
        window.startHour = calendar.component(.hour, from: startTime)
        window.startMinute = calendar.component(.minute, from: startTime)
        window.endHour = calendar.component(.hour, from: endTime)
        window.endMinute = calendar.component(.minute, from: endTime)
        window.activeDays = isEveryDay ? [] : selectedDays

        downtimeStore.updateWindow(window)
        dismiss()
    }

    private func addExcludedApps(from selection: FamilyActivitySelection) {
        for token in selection.applicationTokens {
            guard let tokenData = try? JSONEncoder().encode(token) else { continue }

            // Skip duplicates
            if window.excludedAppTokensData.contains(tokenData) { continue }

            window.excludedAppTokensData.append(tokenData)
            window.excludedAppNames.append("App") // Generic name — token renders as label in shield
        }
    }

    private func removeExcludedApp(at index: Int) {
        guard index < window.excludedAppTokensData.count else { return }
        window.excludedAppTokensData.remove(at: index)
        window.excludedAppNames.remove(at: index)
    }
}

#Preview {
    NavigationStack {
        DowntimeDetailView(window: DowntimeWindow.makeDefault(), isNew: true)
            .environmentObject(DowntimeStore.shared)
    }
}
