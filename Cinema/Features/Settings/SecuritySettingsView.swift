import SwiftUI

/// Settings → Passcode & Face ID: the passcode, locking the whole app, and Face ID.
struct SecuritySettingsView: View {
    @State private var security = SecuritySettings.shared
    @State private var isUnlocked = false
    @State private var sheet: Sheet?
    @State private var isConfirmingRemoval = false

    enum Sheet: String, Identifiable {
        case unlock, create, change
        var id: String { rawValue }
    }

    private var biometricsName: LocalizedStringKey {
        switch Biometrics.kind {
        case .touchID: return "Use Touch ID"
        case .opticID: return "Use Optic ID"
        default: return "Use Face ID"
        }
    }

    var body: some View {
        List {
            if !security.hasPasscode {
                Section {
                    Button {
                        sheet = .create
                    } label: {
                        Label("Turn Passcode On", systemImage: "lock.fill")
                    }
                } footer: {
                    Text("A 4-digit passcode, with Face ID, to lock Cinema itself. Locked and kids profiles each have their own passcode, set in Who's Watching → Edit.")
                }
            } else if !isUnlocked {
                Section {
                    Button {
                        sheet = .unlock
                    } label: {
                        Label("Unlock to Change", systemImage: "lock.open.fill")
                    }
                }
            } else {
                Section {
                    Toggle(isOn: $security.lockApp) {
                        Label {
                            Text("Lock Cinema")
                        } icon: {
                            SettingsIcon(systemName: "lock.shield.fill", color: .gray)
                        }
                    }
                    if Biometrics.isAvailable {
                        Toggle(isOn: $security.useBiometrics) {
                            Label {
                                Text(biometricsName)
                            } icon: {
                                SettingsIcon(systemName: Biometrics.symbol, color: .green)
                            }
                        }
                    }
                } footer: {
                    Text("When Cinema is locked, it asks for this passcode every time it opens. Locked and kids profiles use their own passcodes, set in Who's Watching → Edit.")
                }

                Section {
                    Button("Change Passcode") { sheet = .change }
                    Button("Turn Passcode Off", role: .destructive) { isConfirmingRemoval = true }
                }
            }
        }
        .navigationTitle("Passcode & Face ID")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if security.hasPasscode && !isUnlocked { sheet = .unlock }
        }
        .sheet(item: $sheet) { which in
            Group {
                switch which {
                case .unlock:
                    PasscodeView(mode: .unlock(allowsBiometrics: true), onCancel: { sheet = nil }) {
                        sheet = nil
                        withAnimation(Theme.Motion.spring) { isUnlocked = true }
                    }
                case .create, .change:
                    PasscodeView(mode: .create, onCancel: { sheet = nil }) {
                        sheet = nil
                        withAnimation(Theme.Motion.spring) { isUnlocked = true }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
        .confirmationDialog("Turn the passcode off?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Turn Passcode Off", role: .destructive) {
                withAnimation(Theme.Motion.spring) { security.removePasscode() }
            }
        } message: {
            Text("Cinema will open without asking. Locked and kids profiles keep their own passcodes.")
        }
        .sensoryFeedback(.selection, trigger: security.lockApp)
    }
}
