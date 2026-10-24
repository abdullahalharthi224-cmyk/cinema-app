import SwiftUI

/// The passcode screen: four dots and a round keypad, like the iPhone's own.
/// Unlocks with Face ID or the passcode, or creates a new passcode.
struct PasscodeView: View {
    enum Mode: Equatable {
        /// Enter the existing passcode. Face ID is offered first when allowed.
        case unlock(allowsBiometrics: Bool)
        /// Choose a new passcode (entered twice).
        case create
    }

    var mode: Mode
    var title: LocalizedStringKey? = nil
    var message: LocalizedStringKey? = nil
    var onCancel: (() -> Void)? = nil
    var onSuccess: () -> Void

    @State private var entered = ""
    @State private var firstEntry: String?
    @State private var isResetting = false
    @State private var shakes = 0
    @State private var failure = 0
    @State private var success = 0
    @State private var showsNoBiometrics = false

    private var isCreating: Bool { mode == .create || isResetting }

    private var allowsBiometrics: Bool {
        if case .unlock(let allowed) = mode {
            return allowed && SecuritySettings.shared.useBiometrics && Biometrics.isAvailable && !isResetting
        }
        return false
    }

    private var heading: LocalizedStringKey {
        if isCreating {
            return firstEntry == nil ? (isResetting ? "Choose a New Passcode" : "Create a Passcode") : "Confirm Passcode"
        }
        return title ?? "Enter Passcode"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .fontWeight(.medium)
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, Theme.Spacing.l)

            Spacer(minLength: Theme.Spacing.l)

            Image(systemName: isCreating ? "key.fill" : "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: success)
                .padding(.bottom, Theme.Spacing.l)

            Text(heading)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)

            Group {
                if isCreating {
                    Text("Four digits you'll remember. It's never included in backups.")
                } else if let message {
                    Text(message)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, Theme.Spacing.s)
            .padding(.horizontal, Theme.Spacing.xxl)

            dots
                .padding(.top, Theme.Spacing.xl)
                .modifier(Shake(animatableData: CGFloat(shakes)))

            Spacer(minLength: Theme.Spacing.xl)

            keypad
                .padding(.bottom, Theme.Spacing.l)

            if !isCreating {
                Button("Forgot Passcode?") { forgot() }
                    .font(.footnote.weight(.medium))
                    .padding(.bottom, Theme.Spacing.l)
            } else {
                Color.clear.frame(height: 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.error, trigger: failure)
        .sensoryFeedback(.success, trigger: success)
        .sensoryFeedback(.selection, trigger: entered.count)
        .task {
            if allowsBiometrics { await tryBiometrics() }
        }
        .alert("Face ID Isn't Available", isPresented: $showsNoBiometrics) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The passcode can only be reset with Face ID. Turn on Face ID for this iPhone in the Settings app, then try again.")
        }
    }

    private var dots: some View {
        HStack(spacing: 22) {
            ForEach(0..<Passcode.length, id: \.self) { index in
                Circle()
                    .fill(index < entered.count ? Color.primary : Color.clear)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5))
                    .frame(width: 14, height: 14)
                    .scaleEffect(index < entered.count ? 1.1 : 1)
                    .animation(.snappy(duration: 0.15), value: entered.count)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(entered.count) of \(Passcode.length) digits entered"))
    }

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        return VStack(spacing: 16) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(row, id: \.self) { digit in key(digit) }
                }
            }
            HStack(spacing: 24) {
                if allowsBiometrics {
                    Button {
                        Task { await tryBiometrics() }
                    } label: {
                        Image(systemName: Biometrics.symbol)
                            .font(.system(size: 30, weight: .regular))
                            .frame(width: 78, height: 78)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Use Face ID")
                } else {
                    Color.clear.frame(width: 78, height: 78)
                }
                key("0")
                Button {
                    if !entered.isEmpty { entered.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 24, weight: .regular))
                        .frame(width: 78, height: 78)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(entered.isEmpty ? 0 : 1)
                .disabled(entered.isEmpty)
                .accessibilityLabel("Delete")
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func key(_ digit: String) -> some View {
        Button {
            press(digit)
        } label: {
            Text(verbatim: digit)
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 78, height: 78)
                .background(Color.primary.opacity(0.09), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(KeyPressStyle())
    }

    private func press(_ digit: String) {
        guard entered.count < Passcode.length else { return }
        entered.append(digit)
        guard entered.count == Passcode.length else { return }
        let code = entered
        Task {
            // Let the last dot fill before reacting.
            try? await Task.sleep(for: .milliseconds(140))
            complete(code)
        }
    }

    private func complete(_ code: String) {
        if isCreating {
            if let firstEntry {
                if firstEntry == code {
                    SecuritySettings.shared.setPasscode(code)
                    success += 1
                    onSuccess()
                } else {
                    self.firstEntry = nil
                    reject()
                }
            } else {
                withAnimation(Theme.Motion.spring) { firstEntry = code }
                entered = ""
            }
        } else if Passcode.verify(code) {
            success += 1
            onSuccess()
        } else {
            reject()
        }
    }

    private func reject() {
        failure += 1
        withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        entered = ""
    }

    private func tryBiometrics() async {
        if await Biometrics.authenticate(reason: localized("Unlock Cinema")) {
            success += 1
            onSuccess()
        }
    }

    /// Resetting a forgotten passcode needs Face ID, then a new passcode.
    private func forgot() {
        guard Biometrics.isAvailable else {
            showsNoBiometrics = true
            return
        }
        Task {
            guard await Biometrics.authenticate(reason: localized("Reset your Cinema passcode")) else { return }
            withAnimation(Theme.Motion.spring) {
                entered = ""
                firstEntry = nil
                isResetting = true
            }
        }
    }
}

/// Horizontal shake for a wrong passcode.
struct Shake: GeometryEffect {
    var amount: CGFloat = 10
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 4), y: 0))
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.25 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
