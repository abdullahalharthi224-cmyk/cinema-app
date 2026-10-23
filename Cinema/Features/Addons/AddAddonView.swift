import SwiftData
import SwiftUI

/// Sheet for installing a single addon from a pasted manifest link.
@MainActor
struct AddAddonView: View {
    var onInstalled: (InstalledAddon) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var link = ""
    @State private var preview: (url: URL, manifest: AddonManifest)?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool

    private var store: AddonStore { AddonStore(context: context) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 56, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.accent)
                        Text("Add by Link")
                            .font(.title2.weight(.bold))
                        Text("Paste the link to an addon's manifest. stremio:// links work too.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.s)
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField(text: $link, axis: .vertical) {
                        Text(verbatim: "https://…/manifest.json")
                    }
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)
                    .focused($isFieldFocused)
                    .environment(\.layoutDirection, .leftToRight)

                    PasteButton(payloadType: String.self) { strings in
                        guard let first = strings.first else { return }
                        Task { @MainActor in
                            link = first
                            await check()
                        }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
                }
                .disabled(isLoading)

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .symbolRenderingMode(.multicolor)
                    }
                }

                if let preview {
                    Section("Preview") {
                        ManifestSummaryView(manifest: preview.manifest)
                    }
                }

                Section {
                    Button {
                        Task { await primaryAction() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(preview == nil ? LocalizedStringKey("Check Addon") : "Install Addon")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isLoading || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .animation(.snappy, value: preview?.url)
            .animation(.snappy, value: errorMessage)
            .navigationTitle("Add Addon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: link) {
                if preview?.url.absoluteString != (try? AddonURL.normalizedManifestURL(from: link))?.absoluteString {
                    preview = nil
                }
            }
            .onAppear { isFieldFocused = true }
        }
        .interactiveDismissDisabled(isLoading)
        .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
    }

    private func primaryAction() async {
        if let preview {
            install(preview)
        } else {
            await check()
        }
    }

    private func check() async {
        isFieldFocused = false
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            preview = try await store.previewManifest(for: link)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func install(_ preview: (url: URL, manifest: AddonManifest)) {
        do {
            let addon = try store.install(manifest: preview.manifest, from: preview.url)
            onInstalled(addon)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
