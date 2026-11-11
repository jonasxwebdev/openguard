import SwiftUI

/// Main downtime list showing all configured downtime windows.
struct DowntimeListView: View {
    @EnvironmentObject var downtimeStore: DowntimeStore
    @State private var newWindow: DowntimeWindow?
    @State private var navigateToNew = false

    var body: some View {
        Group {
            if downtimeStore.windows.isEmpty {
                emptyState
            } else {
                windowList
            }
        }
        .navigationTitle("Downtime")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addNewWindow()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(isPresented: $navigateToNew) {
            if let window = newWindow {
                DowntimeDetailView(window: window, isNew: true)
            }
        }
        .onAppear {
            downtimeStore.reload()
        }
    }

    // MARK: - Window List

    private var windowList: some View {
        List {
            Section {
                ForEach(downtimeStore.windows) { window in
                    NavigationLink(destination: DowntimeDetailView(window: window)) {
                        DowntimeWindowRow(window: window) {
                            downtimeStore.toggleWindow(window)
                        }
                    }
                }
                .onDelete { offsets in
                    downtimeStore.removeWindows(at: offsets)
                }
            } footer: {
                Text("During downtime, all apps will be blocked except those you allow. Tap a window to edit its schedule and allowed apps.")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Downtime Set")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Schedule times when all apps should be blocked. You can allow specific important apps to remain accessible.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                addNewWindow()
            } label: {
                Label("Add Downtime", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func addNewWindow() {
        // Don't persist yet — the window is only saved when the user taps Save,
        // so backing out of the editor doesn't leave a stray default window.
        newWindow = DowntimeWindow.makeDefault()
        navigateToNew = true
    }
}

#Preview {
    NavigationStack {
        DowntimeListView()
            .environmentObject(DowntimeStore.shared)
    }
}
