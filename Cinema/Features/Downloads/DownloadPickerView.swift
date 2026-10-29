import SwiftData
import SwiftUI

/// Choose which link to download: every link with its size, the recommended
/// 1080p on top, and links that can't be saved (like torrents) marked clearly.
struct DownloadPickerView: View {
    let request: DownloadRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<InstalledAddon> { $0.isEnabled }, sort: \InstalledAddon.sortIndex)
    private var addons: [InstalledAddon]

    @State private var streams: [ParsedStream] = []
    @State private var recommendedID: String?
    @State private var addonNames: [String: String] = [:]
    @State private var isLoading = true
    /// Every addon failed (usually no connection), rather than simply having no links.
    @State private var failedEverywhere = false
    @State private var spaceWarning: SpaceWarning?
    @State private var added = false

    struct SpaceWarning: Identifiable {
        let needed: Int64
        let available: Int64
        let stream: ParsedStream
        var id: String { stream.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: Theme.Spacing.m) {
                        ProgressView().controlSize(.large)
                        Text("Finding links…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if streams.isEmpty && failedEverywhere {
                    RetryErrorView(message: localized("Couldn't reach your addons. Check your internet connection and try again.")) {
                        isLoading = true
                        Task { await load() }
                    }
                } else if streams.isEmpty {
                    ContentUnavailableView(
                        "No Links Found",
                        systemImage: "arrow.down.circle.dotted",
                        description: Text("None of your addons returned a link for this title.")
                    )
                } else {
                    List {
                        if let recommended = streams.first(where: { $0.id == recommendedID }) {
                            Section {
                                row(recommended, isRecommended: true)
                            } header: {
                                Text("Recommended")
                            } footer: {
                                Text("A good 1080p file at a sensible size. 4K files can be several times larger.")
                                    .settingsFooter()
                            }
                        }
                        Section("All Links") {
                            ForEach(streams.filter { $0.id != recommendedID }) { stream in
                                row(stream, isRecommended: false)
                            }
                        }
                        Section {
                            storageFooter
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(item: $spaceWarning) { warning in
                Alert(
                    title: Text("Not Enough Space"),
                    message: Text("This download needs \(format(warning.needed)), but only \(format(warning.available)) is free on this iPhone. Free up space or choose a smaller link."),
                    dismissButton: .cancel(Text("OK"))
                )
            }
            .sensoryFeedback(.success, trigger: added)
        }
        .task { await load() }
    }

    private func row(_ stream: ParsedStream, isRecommended: Bool) -> some View {
        let downloadable = DownloadPlanner.isDownloadable(stream)
        return Button {
            choose(stream)
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                QualityCapsule(text: stream.info.resolution?.label ?? "—", highlighted: isRecommended)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: stream.info.sizeBytes.map(format) ?? localized("Unknown size"))
                            .font(.headline)
                            .monospacedDigit()
                        if stream.info.isCached {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    if let detail = stream.info.cleanDetails.first {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(verbatim: Bidi.join([addonNames[stream.addonID], stream.info.provider].compactMap { $0 }))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    if !downloadable {
                        Label("Can't be downloaded (torrent or external link)", systemImage: "nosign")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if stream.info.isUncached {
                        Label("Not cached yet — may not download", systemImage: "hourglass")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: downloadable ? "arrow.down.circle.fill" : "xmark.circle")
                    .font(.title2)
                    .foregroundStyle(downloadable ? Theme.accent : Color.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!downloadable)
        .opacity(downloadable ? 1 : 0.5)
    }

    private var storageFooter: some View {
        let free = DownloadFiles.availableBytes()
        return HStack {
            Image(systemName: "internaldrive")
            Text("Free on this iPhone: \(free.map(format) ?? "—")")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        let sources = addons.sources
        addonNames = Dictionary(sources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let groups = await ContentService().streams(type: request.type, id: request.videoID, addons: sources)
        failedEverywhere = !groups.isEmpty && groups.allSatisfy { if case .failure = $0.result { true } else { false } }
        streams = DownloadPlanner.ranked(groups)
        recommendedID = DownloadPlanner.recommended(in: groups)?.id
        withAnimation(Theme.Motion.spring) { isLoading = false }
    }

    private func choose(_ stream: ParsedStream) {
        let available = DownloadFiles.availableBytes()
        if !DownloadPlanner.fits(needed: stream.info.sizeBytes, available: available),
           let needed = stream.info.sizeBytes, let available {
            spaceWarning = SpaceWarning(needed: needed, available: available, stream: stream)
            return
        }
        DownloadManager.shared.enqueue(request, stream: stream)
        added = true
        dismiss()
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
