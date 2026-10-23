import SwiftUI

/// Settings → TMDB: paste, verify and store the user's TMDB API Read Access Token.
@MainActor
struct TMDBSettingsView: View {
    @State private var account = TMDBAccount.shared
    @State private var tokenInput = ""
    @State private var status: Status = .idle
    @State private var isConfirmingRemoval = false

    private enum Status: Equatable {
        case idle, checking, valid, invalid(String)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accent)
                    Text(verbatim: "TMDB")
                        .font(.display(.title2))
                    Text("Your TMDB key unlocks streaming platforms and Arabic titles and synopses.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.s)
            }
            .listRowBackground(Color.clear)

            if account.isConnected {
                connectedSection
            } else {
                entrySection
            }

            statusSection

            Section {
                Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                    Label("Get a free key from TMDB", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("Sign in at themoviedb.org, open Settings → API, and copy the “API Read Access Token” (the long one). It's stored only in this iPhone's Keychain.")
            }
        }
        .navigationTitle(Text(verbatim: "TMDB"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove TMDB key?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                account.remove()
                status = .idle
            }
        }
        .sensoryFeedback(.success, trigger: status) { _, new in new == .valid }
        .sensoryFeedback(.error, trigger: status) { _, new in
            if case .invalid = new { return true }
            return false
        }
        .animation(Theme.Motion.spring, value: status)
        .animation(Theme.Motion.spring, value: account.isConnected)
    }

    private var entrySection: some View {
        Section {
            SecureField("API Read Access Token", text: $tokenInput)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)

            Button {
                Task { await verify(tokenInput, saveIfValid: true) }
            } label: {
                HStack {
                    Text("Verify & Save")
                        .fontWeight(.semibold)
                    Spacer()
                    if status == .checking { ProgressView() }
                }
            }
            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .checking)
        }
    }

    private var connectedSection: some View {
        Section {
            LabeledContent {
                Text(verbatim: masked(account.token ?? ""))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            } label: {
                Label("Key saved", systemImage: "key.fill")
            }

            Button {
                Task { await verify(account.token ?? "", saveIfValid: false) }
            } label: {
                HStack {
                    Label("Verify", systemImage: "checkmark.shield")
                    Spacer()
                    if status == .checking { ProgressView() }
                }
            }
            .disabled(status == .checking)

            Button("Remove Key", role: .destructive) {
                isConfirmingRemoval = true
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch status {
        case .valid:
            Section {
                Label("The key works.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .invalid(let message):
            Section {
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        case .idle, .checking:
            EmptyView()
        }
    }

    private func verify(_ token: String, saveIfValid: Bool) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        status = .checking
        do {
            try await TMDBClient(token: trimmed).validate()
            if saveIfValid {
                account.save(trimmed)
                tokenInput = ""
            }
            status = .valid
        } catch {
            status = .invalid(error.localizedDescription)
        }
    }

    private func masked(_ token: String) -> String {
        guard token.count > 10 else { return "••••••" }
        return String(token.prefix(4)) + " •••••• " + String(token.suffix(4))
    }
}
