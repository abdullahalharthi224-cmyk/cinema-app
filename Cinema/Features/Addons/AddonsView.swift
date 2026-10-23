import SwiftData
import SwiftUI

/// Settings → Addons: the list of installed addons and the entry points to add more.
@MainActor
struct AddonsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \InstalledAddon.sortIndex) private var addons: [InstalledAddon]
    @AppStorage(StremioDefaults.emailKey) private var stremioEmail = ""

    @State private var sheet: AddonsSheet?
    @State private var isSyncing = false
    @State private var isConfirmingSignOut = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    private var store: AddonStore { AddonStore(context: context) }
    private var isConnected: Bool { !stremioEmail.isEmpty }

    var body: some View {
        List {
            if isConnected {
                accountSection
            }

            if !addons.isEmpty {
                Section {
                    Button {
                        sheet = .healthAll
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            SettingsIcon(systemName: "stethoscope", color: .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Check All Addons")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("See which addons work and why others don't.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                installedSection
            } else if isConnected {
                Section {
                    Text("Your Stremio account has no addons that work on iPhone yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if addons.isEmpty && !isConnected {
                emptyState
            }
        }
        .overlay {
            if isSyncing {
                LoadingOverlay(title: "Syncing with Stremio…")
            }
        }
        .animation(.snappy, value: isSyncing)
        .navigationTitle("Addons")
        .toolbar { toolbar }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .stremio:
                StremioImportView()
            case .manual:
                AddAddonView { addon in
                    toastMessage = localized("%@ installed", addon.name)
                }
            case .healthAll:
                AddonHealthReportView()
            case .healthOne(let addon):
                AddonSingleCheckView(addon: addon)
            }
        }
        .confirmationDialog(
            "Sign out of Stremio?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                store.signOutOfStremio()
            }
        } message: {
            Text("Your installed addons will stay. You can sign in again any time to re-sync.")
        }
        .toast($toastMessage)
        .errorAlert($errorMessage)
        .sensoryFeedback(.success, trigger: toastMessage) { _, new in new != nil }
    }

    // MARK: Sections

    private var accountSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.m) {
                SettingsIcon(systemName: "person.crop.circle.fill", color: .indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stremio")
                        .font(.body.weight(.semibold))
                    Text(stremioEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task { await resync() }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(isSyncing)
            }

            Button("Sign Out of Stremio", role: .destructive) {
                isConfirmingSignOut = true
            }
        } header: {
            Text("Account")
        }
    }

    private var installedSection: some View {
        Section {
            ForEach(addons) { addon in
                AddonRow(addon: addon) {
                    router.settingsPath.append(.addon(addon))
                } onToggle: { isOn in
                    perform { try store.setEnabled(addon, isOn) }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        sheet = .healthOne(addon)
                    } label: {
                        Label("Check", systemImage: "stethoscope")
                    }
                    .tint(.green)
                }
                .contextMenu {
                    Button {
                        sheet = .healthOne(addon)
                    } label: {
                        Label("Check", systemImage: "stethoscope")
                    }
                }
            }
            .onMove { source, destination in
                perform { try store.move(addons, fromOffsets: source, toOffset: destination) }
            }
            .onDelete { offsets in
                let targets = offsets.map { addons[$0] }
                perform { try store.remove(targets) }
            }
        } header: {
            Text("Installed")
        } footer: {
            Text("Tap Edit to reorder or remove. Addons higher in the list are asked first.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Addons Yet", systemImage: "puzzlepiece.extension")
        } description: {
            Text("Bring over the addons from your Stremio account, or paste a link to a single addon.")
        } actions: {
            VStack(spacing: Theme.Spacing.m) {
                Button {
                    sheet = .stremio
                } label: {
                    Label("Import from Stremio", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    sheet = .manual
                } label: {
                    Label("Add by Link", systemImage: "link")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !addons.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    sheet = .stremio
                } label: {
                    Label(
                        isConnected ? LocalizedStringKey("Switch Stremio Account") : "Import from Stremio",
                        systemImage: "arrow.down.circle"
                    )
                }
                Button {
                    sheet = .manual
                } label: {
                    Label("Add by Link", systemImage: "link")
                }
            } label: {
                Image(systemName: "plus")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Add Addon")
        }
    }

    // MARK: Actions

    private func resync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let summary = try await store.resyncStremio()
            toastMessage = localized("Synced %lld addons", summary.imported)
        } catch {
            errorMessage = error.localizedDescription
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

enum AddonsSheet: Identifiable {
    case stremio, manual, healthAll
    case healthOne(InstalledAddon)

    var id: String {
        switch self {
        case .stremio: return "stremio"
        case .manual: return "manual"
        case .healthAll: return "healthAll"
        case .healthOne(let addon): return "health:" + addon.transportUrl
        }
    }
}

private struct AddonRow: View {
    let addon: InstalledAddon
    var onOpen: () -> Void
    var onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: onOpen) {
                HStack(spacing: Theme.Spacing.m) {
                    AddonLogoView(url: addon.manifest?.logoURL, name: addon.name)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(addon.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(verbatim: "v\(addon.manifest?.version ?? "–")")
                            Text(verbatim: "·")
                            Text(addon.source == .stremio ? LocalizedStringKey("From Stremio") : "Added by link")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(addon.isEnabled ? 1 : 0.5)

            Toggle(
                "Enabled",
                isOn: Binding(get: { addon.isEnabled }, set: onToggle)
            )
            .labelsHidden()
        }
        .padding(.vertical, 2)
        .animation(.snappy, value: addon.isEnabled)
    }
}
