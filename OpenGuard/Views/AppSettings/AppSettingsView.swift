import SwiftUI
import FamilyControls
import ManagedSettings

/// Per-app settings: opens per day, time limit per open.
struct AppSettingsView: View {
    @EnvironmentObject var blockListStore: BlockListStore
    @Environment(\.dismiss) var dismiss

    @State var app: BlockedApp

    // Time limit options in seconds
    private let presets: [(label: String, value: TimeInterval)] = [
        ("5 min", 300),
        ("10 min", 600),
        ("15 min", 900),
    ]

    @State private var isCustomTime = false
    @State private var customMinutes: Int = 10

    var body: some View {
        Form {
            // MARK: - App Info
            Section {
                HStack {
                    if let token = app.applicationToken() {
                        Label(token)
                            .labelStyle(.titleAndIcon)
                            .font(.headline)
                    } else {
                        Label(app.displayName, systemImage: "app.fill")
                            .font(.headline)
                    }
                    Spacer()
                }
            }

            // MARK: - Today's Status
            Section("Today's Usage") {
                HStack {
                    Text("Opens Used")
                    Spacer()
                    Text("\(app.opensUsedToday) / \(app.opensPerDay)")
                        .foregroundStyle(app.isExhausted ? .red : .secondary)
                }

                if app.isInOpenWindow, let expiresAt = app.currentOpenExpiresAt {
                    HStack {
                        Text("Current Window Expires")
                        Spacer()
                        Text(expiresAt, style: .relative)
                            .foregroundStyle(.green)
                    }
                }
            }

            // MARK: - Opens Per Day
            Section("Opens Per Day") {
                Stepper(
                    "\(app.opensPerDay) open\(app.opensPerDay == 1 ? "" : "s") per day",
                    value: $app.opensPerDay,
                    in: 1...20
                )

                if app.opensPerDay < app.opensUsedToday {
                    Text("Already used \(app.opensUsedToday) opens today — app will stay blocked for the rest of the day.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // MARK: - Time Limit Per Open
            Section("Time Limit Per Open") {
                ForEach(presets, id: \.value) { preset in
                    Button {
                        isCustomTime = false
                        app.timeLimitPerOpen = preset.value
                    } label: {
                        HStack {
                            Text(preset.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if !isCustomTime && app.timeLimitPerOpen == preset.value {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                Button {
                    isCustomTime = true
                    customMinutes = Int(app.timeLimitPerOpen / 60)
                } label: {
                    HStack {
                        Text("Custom")
                            .foregroundStyle(.primary)
                        Spacer()
                        if isCustomTime {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }

                if isCustomTime {
                    Stepper(
                        "\(customMinutes) minute\(customMinutes == 1 ? "" : "s")",
                        value: $customMinutes,
                        in: 1...120
                    )
                    .onChange(of: customMinutes) { _, newValue in
                        app.timeLimitPerOpen = TimeInterval(newValue * 60)
                    }
                }
            }

            // MARK: - Note
            if app.isInOpenWindow {
                Section {
                    Label(
                        "Changes to time limit will apply to the next open, not the current window.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Determine if current time is a custom preset
            isCustomTime = !presets.contains { $0.value == app.timeLimitPerOpen }
            if isCustomTime {
                customMinutes = Int(app.timeLimitPerOpen / 60)
            }
        }
        .onDisappear {
            // Save changes when leaving the view
            blockListStore.updateApp(app)
        }
    }
}

#Preview {
    NavigationStack {
        AppSettingsView(app: BlockedApp(
            id: UUID(),
            applicationTokenData: Data(),
            displayName: "Instagram",
            opensPerDay: 5,
            timeLimitPerOpen: 600,
            opensUsedToday: 2,
            currentOpenExpiresAt: nil
        ))
        .environmentObject(BlockListStore.shared)
    }
}
