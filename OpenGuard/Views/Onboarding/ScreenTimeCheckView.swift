import SwiftUI

/// Step 2: Instructs the user to disable iCloud Screen Time sync.
/// There is no public API to detect this — we use a manual checklist approach.
struct ScreenTimeCheckView: View {
    let onNext: () -> Void

    @State private var hasConfirmed = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "icloud.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Important Setup Step")
                .font(.title)
                .fontWeight(.bold)

            Text("For OpenGuard to work correctly, you need to disable **iCloud Screen Time sync**.\n\nIf enabled, your shields may not apply properly.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(number: 1, text: "Open **Settings**")
                InstructionRow(number: 2, text: "Tap **Screen Time**")
                InstructionRow(number: 3, text: "Tap **Share Across Devices**")
                InstructionRow(number: 4, text: "Turn the toggle **Off**")
            }
            .padding(.horizontal, 32)

            // Deep link to Settings
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .padding(.top, 8)

            Spacer()

            // Confirmation toggle
            Toggle(isOn: $hasConfirmed) {
                Text("I've disabled Share Across Devices (or it was already off)")
                    .font(.footnote)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 24)

            Button(action: onNext) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(hasConfirmed ? .green : .gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!hasConfirmed)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Instruction Row

private struct InstructionRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.green)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Checkbox Toggle Style

private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(configuration.isOn ? .green : .secondary)
                .onTapGesture { configuration.isOn.toggle() }

            configuration.label
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

#Preview {
    ScreenTimeCheckView(onNext: {})
}
