import SwiftUI

/// Root view — routes between onboarding and the main block list.
struct ContentView: View {
    @EnvironmentObject var cloudSync: CloudSyncManager
    @EnvironmentObject var blockListStore: BlockListStore

    var body: some View {
        if cloudSync.isOnboardingCompleted {
            NavigationStack {
                BlockListView()
            }
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BlockListStore.shared)
        .environmentObject(CloudSyncManager.shared)
}
