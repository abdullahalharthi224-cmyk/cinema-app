import SwiftUI

/// Settings → Downloads.
struct DownloadSettingsView: View {
    @State private var settings = DownloadSettings.shared
    @State private var isConfirmingDeleteAll = false
    @State private var usedBytes = DownloadFiles.usedBytes()

    var body: some View {
        Form {
            Section {
                Toggle("Download over Wi-Fi Only", isOn: $settings.wifiOnly)
                Toggle("Delete Episodes After Watching", isOn: $settings.deleteWatched)
            } footer: {
                Text("Downloads keep going in the background, two at a time. Expired links are renewed automatically.")
            }

            Section {
                LabeledContent("Used by Downloads") {
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file))
                }
                LabeledContent("Free on This iPhone") {
                    Text(verbatim: DownloadFiles.availableBytes().map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                }
                Button("Delete All Downloads", role: .destructive) {
                    isConfirmingDeleteAll = true
                }
                .disabled(usedBytes == 0 && DownloadManager.shared.allItems().isEmpty)
            } header: {
                Text("Storage")
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all downloads?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                DownloadManager.shared.deleteAll()
                usedBytes = DownloadFiles.usedBytes()
            }
        }
    }
}
