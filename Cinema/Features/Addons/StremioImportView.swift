import SwiftData
import SwiftUI

/// Sheet that signs in to Stremio and imports the account's addon collection.
@MainActor
struct StremioImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var email = ""
    @State private var password = ""
    @State private var phase: Phase = .form
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Phase: Equatable {
        case form
        case working
        case done(StremioImportSummary)
    }

    private enum Field { case email, password }

    private var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    private var canSubmit: Bool {
        phase == .form && email.contains("@") && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if case .done(let summary) = phase {
                    successView(summary)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    form
                }
            }
            .animation(.smooth, value: phase)
            .navigationTitle("Stremio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(phase == .working)
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase == .working)
        .sensoryFeedback(.success, trigger: isDone) { _, new in new }
        .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accent)
                    Text("Import from Stremio")
                        .font(.title2.weight(.bold))
                    Text("Sign in to bring over every addon from your Stremio account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.s)
            }
            .listRowBackground(Color.clear)

            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(signIn)
            } footer: {
                Label(
                    "Your password is only used to sign in and is never saved. Cinema keeps a secure session key in the Keychain.",
                    systemImage: "lock.fill"
                )
            }
            .disabled(phase == .working)

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .symbolRenderingMode(.multicolor)
                }
            }

            Section {
                Button(action: signIn) {
                    HStack {
                        Spacer()
                        if phase == .working {
                            ProgressView()
                        } else {
                            Text("Sign In & Import")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .onAppear { focusedField = .email }
    }

    // MARK: Success

    private func successView(_ summary: StremioImportSummary) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: summary)

            Text("All Set")
                .font(.largeTitle.weight(.bold))

            Text("Imported \(summary.imported) addons from your Stremio account.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if summary.skipped > 0 {
                Text("\(summary.skipped) desktop-only addons were skipped because they can't work on iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: Actions

    private func signIn() {
        guard canSubmit else { return }
        focusedField = nil
        errorMessage = nil
        phase = .working

        Task {
            do {
                let store = AddonStore(context: context)
                let summary = try await store.importFromStremio(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
                password = ""
                phase = .done(summary)
            } catch {
                errorMessage = error.localizedDescription
                phase = .form
            }
        }
    }
}
