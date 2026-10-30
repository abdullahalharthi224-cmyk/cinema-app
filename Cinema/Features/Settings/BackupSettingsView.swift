import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The exported file, for the system's "save to Files" sheet.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Settings → Backup & Restore: one file with everything, saved to Files or
/// iCloud Drive, and restored after a reinstall.
struct BackupSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(BackupService.lastBackupKey) private var lastBackup: Double = 0
    @State private var includeSecrets = false
    @State private var document: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingRestore: CinemaBackup?
    @State private var message: Message?

    struct Message: Identifiable {
        let title: LocalizedStringKey
        let body: String
        var id: String { body }
    }

    private var fileName: String {
        "Cinema Backup " + Date.now.formatted(.iso8601.year().month().day())
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "externaldrive.fill.badge.timemachine")
                        .font(.system(size: 50, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accent)
                    Text("Backup & Restore")
                        .font(.display(.title2))
                    Text("Keep your profiles, library, My List, Continue Watching, addons and settings safe in one file, ready for when you reinstall Cinema.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.s)
            }
            .listRowBackground(Color.clear)

            Section {
                Toggle("Include Secret Keys", isOn: $includeSecrets)
                if includeSecrets {
                    Label("Your TMDB, MDBList and Stremio keys will be inside the file in plain text. Anyone with the file can use them. Keep it private.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button {
                    export()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Export")
            } footer: {
                Group {
                    if lastBackup > 0 {
                        Text("Last backup: \(AppFormat.date(Date(timeIntervalSince1970: lastBackup), date: .abbreviated, time: .shortened))")
                    } else {
                        Text("No backup yet.")
                    }
                }
                .settingsFooter()
            }

            Section {
                Button {
                    isImporting = true
                } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Restoring replaces your current profiles, library, addons and settings with the ones in the file.")
                    .settingsFooter()
            }
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Theme.Motion.spring, value: includeSecrets)
        .fileExporter(isPresented: $isExporting, document: document, contentType: .json, defaultFilename: fileName) { result in
            switch result {
            case .success:
                lastBackup = Date.now.timeIntervalSince1970
                message = Message(title: "Backup Saved", body: localized("Keep the file somewhere safe, like iCloud Drive."))
            case .failure(let error):
                message = Message(title: "Couldn't Save", body: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                read(url)
            case .failure(let error):
                message = Message(title: "Couldn't Open", body: error.localizedDescription)
            }
        }
        .confirmationDialog(
            "Replace everything with this backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let backup = pendingRestore { restore(backup) }
            }
        } message: {
            if let backup = pendingRestore {
                Text("From \(AppFormat.date(backup.createdAt, date: .abbreviated, time: .shortened)): \(backup.profiles.count) profiles, \(backup.addons.count) addons, \(backup.history.count) titles watched.")
            }
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(verbatim: message.body), dismissButton: .default(Text("OK")))
        }
    }

    private func export() {
        do {
            let backup = BackupService.makeBackup(includeSecrets: includeSecrets, context: context)
            document = BackupDocument(data: try BackupService.encode(backup))
            isExporting = true
        } catch {
            message = Message(title: "Couldn't Save", body: error.localizedDescription)
        }
    }

    private func read(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingRestore = try BackupService.decode(try Data(contentsOf: url))
        } catch {
            message = Message(title: "Not a Cinema Backup", body: localized("This file couldn't be read as a Cinema backup."))
        }
    }

    private func restore(_ backup: CinemaBackup) {
        do {
            try BackupService.restore(backup, context: context)
            message = Message(title: "Restored", body: localized("Everything is back. Some settings apply fully the next time you open Cinema."))
        } catch {
            message = Message(title: "Couldn't Restore", body: error.localizedDescription)
        }
    }
}
