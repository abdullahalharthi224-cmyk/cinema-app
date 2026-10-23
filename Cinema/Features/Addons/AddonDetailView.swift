import SwiftData
import SwiftUI
import UIKit

/// Everything about one installed addon, plus enable/update/remove actions.
@MainActor
struct AddonDetailView: View {
    let addon: InstalledAddon

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    @State private var isRefreshing = false
    @State private var isConfirmingRemoval = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    private var store: AddonStore { AddonStore(context: context) }

    var body: some View {
        List {
            if let manifest = addon.manifest {
                Section {
                    ManifestSummaryView(manifest: manifest, logoSize: 72)
                }

                Section {
                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { addon.isEnabled },
                            set: { isOn in perform { try store.setEnabled(addon, isOn) } }
                        )
                    )
                } footer: {
                    Text("Disabled addons are kept but never asked for content.")
                }

                if !manifest.catalogs.isEmpty {
                    Section("Catalogs") {
                        ForEach(manifest.catalogs, id: \.identity) { catalog in
                            HStack(spacing: Theme.Spacing.s) {
                                Text(catalog.displayName)
                                    .lineLimit(1)
                                Spacer(minLength: Theme.Spacing.s)
                                if catalog.supportsSearch {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Searchable")
                                }
                                TagChip(text: catalog.type.localizedContentType)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Can't Read This Addon",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Try checking for updates to download its details again.")
                )
            }

            Section {
                Text(addon.transportUrl)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight)
                Button {
                    UIPasteboard.general.string = addon.transportUrl
                    toastMessage = String(localized: "Link copied")
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Link")
            } footer: {
                Text(addon.source == .stremio ? LocalizedStringKey("Imported from your Stremio account.") : "Added by link.")
            }

            Section {
                Button {
                    Task { await refresh() }
                } label: {
                    HStack {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshing)

                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Label("Remove Addon", systemImage: "trash")
                }
            }
        }
        .navigationTitle(addon.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove \(addon.name)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: remove)
        }
        .toast($toastMessage)
        .errorAlert($errorMessage)
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await store.refreshManifest(of: addon)
            toastMessage = String(localized: "Addon is up to date")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        let target = addon
        if !router.settingsPath.isEmpty {
            router.settingsPath.removeLast()
        }
        // Delete after the pop animation so this screen never renders a deleted model.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            perform { try store.remove([target]) }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
