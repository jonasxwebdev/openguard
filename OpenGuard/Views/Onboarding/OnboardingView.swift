import SwiftUI

/// Multi-step onboarding flow shown on first launch.
struct OnboardingView: View {
    @EnvironmentObject var cloudSync: CloudSyncManager
    @State private var currentStep = 0

    var body: some View {
        TabView(selection: $currentStep) {
            WelcomeStepView(onNext: { currentStep = 1 })
                .tag(0)

            ScreenTimeCheckView(onNext: { currentStep = 2 })
                .tag(1)

            PermissionsView(onComplete: completeOnboarding)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .ignoresSafeArea()
    }

    private func completeOnboarding() {
        cloudSync.setOnboardingCompleted()
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStepView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Welcome to OpenGuard")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Take control of your screen time with a daily \"open\" allowance system.\n\nBlock the apps that distract you, and only access them when you consciously choose to.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(CloudSyncManager.shared)
}
