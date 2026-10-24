import SwiftUI

/// Settings → Ratings: paste, verify and store the user's MDBList API key.
@MainActor
struct MDBListSettingsView: View {
    @State private var account = MDBListAccount.shared
    @State private var keyInput = ""
    @State private var status: Status = .idle
    @State private var isConfirmingRemoval = false

    private enum Status: Equatable {
        case idle, checking, valid, invalid(String)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "star.leadinghalf.filled")
                        .font(.system(size: 52, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accent)
                    Text("Ratings")
                        .font(.display(.title2))
                    Text("An MDBList key adds IMDb, Rotten Tomatoes, Metacritic and Letterboxd scores to every title. Without one, TMDB's score is shown.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.s)
            }
            .listRowBackground(Color.clear)

            if account.isConnected {
                Section {
                    LabeledContent {
                        Text(verbatim: masked(account.apiKey ?? ""))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .environment(\.layoutDirection, .leftToRight)
                    } label: {
                        Label("Key saved", systemImage: "key.fill")
                    }
                    Button {
                        Task { await verify(account.apiKey ?? "", saveIfValid: false) }
                    } label: {
                        HStack {
                            Label("Verify", systemImage: "checkmark.shield")
                            Spacer()
                            if status == .checking { ProgressView() }
                        }
                    }
                    .disabled(status == .checking)
                    Button("Remove Key", role: .destructive) { isConfirmingRemoval = true }
                }
            } else {
                Section {
                    SecureField("MDBList API Key", text: $keyInput)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                    Button {
                        Task { await verify(keyInput, saveIfValid: true) }
                    } label: {
                        HStack {
                            Text("Verify & Save").fontWeight(.semibold)
                            Spacer()
                            if status == .checking { ProgressView() }
                        }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .checking)
                }
            }

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

            Section {
                Link(destination: URL(string: "https://mdblist.com/preferences/")!) {
                    Label("Get a free key from MDBList", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("Sign in at mdblist.com, open Preferences, and copy your API key. It's stored only in this iPhone's Keychain.")
            }
        }
        .navigationTitle("Ratings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove MDBList key?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                account.remove()
                status = .idle
            }
        }
        .sensoryFeedback(.success, trigger: status) { _, new in new == .valid }
        .animation(Theme.Motion.spring, value: status)
        .animation(Theme.Motion.spring, value: account.isConnected)
    }

    private func verify(_ key: String, saveIfValid: Bool) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        status = .checking
        do {
            try await MDBListClient(apiKey: trimmed).validate()
            if saveIfValid {
                account.save(trimmed)
                keyInput = ""
            }
            status = .valid
        } catch MDBListClient.Failure.invalidKey {
            status = .invalid(localized("MDBList didn't accept this key."))
        } catch {
            status = .invalid(localized("Couldn't reach MDBList. Check your connection and try again."))
        }
    }

    private func masked(_ key: String) -> String {
        guard key.count > 8 else { return "••••••" }
        return String(key.prefix(3)) + " •••••• " + String(key.suffix(3))
    }
}
