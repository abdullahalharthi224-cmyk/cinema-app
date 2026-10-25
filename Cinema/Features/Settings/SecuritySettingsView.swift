import SwiftData
import SwiftUI

/// Settings → Passcode & Face ID, for the profile that's open now: its own
/// passcode, whether it's locked, and Face ID. Other profiles set their own.
struct SecuritySettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.sortIndex) private var profiles: [Profile]
    @State private var security = SecuritySettings.shared
    @State private var isUnlocked = false
    @State private var sheet: Sheet?
    @State private var isConfirmingRemoval = false

    enum Sheet: String, Identifiable {
        case unlock, create
        var id: String { rawValue }
    }

    private var profile: Profile? {
        profiles.first { $0.id == ProfileSession.shared.activeID } ?? profiles.first
    }

    private var scope: PasscodeScope? { profile.map { .profile($0.id) } }

    private var hasPasscode: Bool {
        _ = security.revision
        return scope.map { Passcode.isSet($0) } ?? false
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
            if let profile {
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        ProfileAvatar(profile: profile, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: profile.name).font(.headline)
                            Text(hasPasscode ? LocalizedStringKey("Has its own passcode") : "No passcode yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("This passcode belongs only to this profile. Every profile can set its own from here while it's open.")
                }

                if !hasPasscode {
                    Section {
                        Button {
                            sheet = .create
                        } label: {
                            Label("Create a Passcode for This Profile", systemImage: "lock.fill")
                        }
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
                        Toggle(isOn: Binding(
                            get: { profile.isLocked },
                            set: { on in
                                profile.isLocked = on
                                try? context.save()
                            }
                        )) {
                            Label {
                                Text("Lock This Profile")
                            } icon: {
                                SettingsIcon(systemName: "lock.shield.fill", color: .gray)
                            }
                        }
                        if Biometrics.isAvailable {
                            Toggle(isOn: Binding(
                                get: { security.usesBiometrics(for: .profile(profile.id)) },
                                set: { security.setBiometrics($0, for: profile.id) }
                            )) {
                                Label {
                                    Text(biometricsName)
                                } icon: {
                                    SettingsIcon(systemName: Biometrics.symbol, color: .green)
                                }
                            }
                        }
                    } footer: {
                        Text("When this profile is locked, opening it, or coming back to Cinema while it's open, needs Face ID or its passcode.")
                    }

                    Section {
                        Button("Change Passcode") { sheet = .create }
                        Button("Remove Passcode", role: .destructive) { isConfirmingRemoval = true }
                    }
                }
            }
        }
        .navigationTitle("Passcode & Face ID")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if hasPasscode && !isUnlocked { sheet = .unlock }
        }
        .sheet(item: $sheet) { which in
            Group {
                if let scope {
                    switch which {
                    case .unlock:
                        PasscodeView(mode: .unlock(allowsBiometrics: true), scope: scope, onCancel: { sheet = nil }) {
                            sheet = nil
                            withAnimation(Theme.Motion.spring) { isUnlocked = true }
                        }
                    case .create:
                        PasscodeView(mode: .create, scope: scope, onCancel: { sheet = nil }) {
                            sheet = nil
                            withAnimation(Theme.Motion.spring) { isUnlocked = true }
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
        .confirmationDialog("Remove this profile's passcode?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove Passcode", role: .destructive) {
                guard let profile else { return }
                withAnimation(Theme.Motion.spring) {
                    profile.isLocked = false
                    try? context.save()
                    security.removePasscode(.profile(profile.id))
                }
            }
        } message: {
            Text("This profile will open without asking. Other profiles keep their own passcodes.")
        }
    }
}
