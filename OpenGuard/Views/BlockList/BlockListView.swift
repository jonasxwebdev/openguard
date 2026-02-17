import SwiftUI
import FamilyControls

/// Main screen showing all blocked apps with their open status.
struct BlockListView: View {
    @EnvironmentObject var blockListStore: BlockListStore
    @State private var showingPicker = false
    @State private var activitySelection = FamilyActivitySelection()

    var body: some View {
        Group {
            if blockListStore.apps.isEmpty {
                emptyState
            } else {
                appList
            }
        }
        .navigationTitle("OpenGuard")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(destination: DowntimeListView()) {
                    Image(systemName: "moon.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .familyActivityPicker(
            isPresented: $showingPicker,
            selection: $activitySelection
        )
        .onChange(of: activitySelection) { _, newValue in
            blockListStore.addApps(from: newValue)
            // Reset selection so the picker starts fresh next time
            activitySelection = FamilyActivitySelection()
        }
        .onAppear {
            blockListStore.reload()
        }
    }

    // MARK: - App List

    private var appList: some View {
        List {
            ForEach(blockListStore.apps) { app in
                NavigationLink(destination: AppSettingsView(app: app)) {
                    BlockedAppRow(app: app)
                }
            }
            .onDelete { offsets in
                blockListStore.removeApps(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            blockListStore.reload()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "shield.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Apps Blocked")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the **+** button to select apps you want to restrict with a daily open allowance.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showingPicker = true
            } label: {
                Label("Add Apps", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        BlockListView()
            .environmentObject(BlockListStore.shared)
    }
}
