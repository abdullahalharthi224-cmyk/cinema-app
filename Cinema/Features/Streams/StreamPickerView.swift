import SwiftData
import SwiftUI
import UIKit

/// Sheet listing every stream the enabled addons offer for a movie or episode,
/// grouped by addon and loaded progressively.
@MainActor
struct StreamPickerView: View {
    let request: StreamRequest

    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var results: [String: StreamGroup] = [:]
    @State private var filter: QualityFilter = .all
    @State private var selected: ParsedStream?
    @State private var toastMessage: String?
    @State private var errorMessage: String?

    private let service = ContentService()

    private var candidates: [AddonSource] {
        addons.sources.filter { $0.supports(.stream, type: request.type, id: request.videoID) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Stream Addons",
                        systemImage: "play.slash",
                        description: Text("None of your enabled addons provide streams for this title.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await loadAll() }
        .confirmationDialog(
            "Play With",
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            titleVisibility: .visible,
            presenting: selected
        ) { stream in
            if case .direct(let url) = stream.stream.kind {
                ForEach(ExternalPlayer.allCases) { player in
                    Button(player.name) { open(url, in: player) }
                }
                Button("Copy Link") {
                    UIPasteboard.general.url = url
                    toastMessage = String(localized: "Link copied")
                }
            }
        } message: { _ in
            Text("Cinema's own player arrives in the next update. For now, you can open this stream in another player app.")
        }
        .toast($toastMessage)
        .errorAlert($errorMessage)
        .sensoryFeedback(.selection, trigger: filter)
    }

    // MARK: List

    private var list: some View {
        List {
            Section {
                if let subtitle = request.subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Picker("Quality", selection: $filter) {
                    ForEach(QualityFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            ForEach(candidates) { addon in
                Section {
                    groupContent(for: addon)
                } header: {
                    HStack {
                        Text(addon.name)
                        Spacer()
                        if case .success(let streams)? = results[addon.id]?.result {
                            Text(streams.filter { filter.matches($0.info) }.count, format: .number)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.smooth, value: filter)
    }

    @ViewBuilder
    private func groupContent(for addon: AddonSource) -> some View {
        switch results[addon.id]?.result {
        case nil:
            HStack(spacing: Theme.Spacing.m) {
                ProgressView()
                Text("Looking for streams…")
                    .foregroundStyle(.secondary)
            }

        case .success(let streams)?:
            let filtered = streams.filter { filter.matches($0.info) }
            if filtered.isEmpty {
                Text(streams.isEmpty ? LocalizedStringKey("No streams found.") : "No streams match this quality.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { stream in
                    Button {
                        select(stream)
                    } label: {
                        StreamRow(stream: stream)
                    }
                    .disabled(!stream.stream.isSupported)
                }
            }

        case .failure(let error)?:
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.s)
                Button("Retry") {
                    Task { await load(addon) }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
    }

    // MARK: Actions

    private func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            for addon in candidates {
                group.addTask { await load(addon) }
            }
        }
    }

    private func load(_ addon: AddonSource) async {
        results[addon.id] = nil
        let groups = await service.streams(type: request.type, id: request.videoID, addons: [addon])
        if let group = groups.first {
            withAnimation(.smooth) { results[addon.id] = group }
        }
    }

    private func select(_ stream: ParsedStream) {
        switch stream.stream.kind {
        case .direct:
            selected = stream
        case .youtube(let id):
            if let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { openURL(url) }
        case .external(let url):
            openURL(url)
        case .torrent, .unknown:
            break
        }
    }

    private func open(_ url: URL, in player: ExternalPlayer) {
        guard let target = player.url(for: url) else { return }
        openURL(target) { accepted in
            if !accepted {
                errorMessage = String(localized: "Couldn't open \(player.name). Make sure it's installed.")
            }
        }
    }
}

// MARK: - Supporting types

enum QualityFilter: String, CaseIterable, Identifiable {
    case all, uhd, fullHD, hd

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .uhd: return "4K"
        case .fullHD: return "1080p"
        case .hd: return "720p & Lower"
        }
    }

    func matches(_ info: StreamInfo) -> Bool {
        switch self {
        case .all: return true
        case .uhd: return info.resolution == .uhd4k
        case .fullHD: return info.resolution == .p1080 || info.resolution == .p1440
        case .hd: return (info.resolution ?? .sd) <= .p720
        }
    }
}

/// Third-party players the stream can be handed to until the built-in player ships.
enum ExternalPlayer: String, CaseIterable, Identifiable {
    case infuse, vlc, outplayer

    var id: String { rawValue }

    var name: String {
        switch self {
        case .infuse: return "Infuse"
        case .vlc: return "VLC"
        case .outplayer: return "Outplayer"
        }
    }

    func url(for stream: URL) -> URL? {
        let encoded = AddonURL.encodeComponent(stream.absoluteString)
        switch self {
        case .infuse: return URL(string: "infuse://x-callback-url/play?url=\(encoded)")
        case .vlc: return URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encoded)")
        case .outplayer: return URL(string: "outplayer://\(stream.absoluteString)")
        }
    }
}

private struct StreamRow: View {
    let stream: ParsedStream

    private var info: StreamInfo { stream.info }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            qualityBadge

            VStack(alignment: .leading, spacing: 6) {
                let tags = featureTags
                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            Text(verbatim: tag)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12), in: .continuous(4))
                        }
                    }
                    .foregroundStyle(.primary)
                }

                ForEach(Array(info.details.prefix(3).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                let facts = factLine
                if !facts.isEmpty {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(facts, id: \.text) { fact in
                            Label(fact.text, systemImage: fact.symbol)
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
                }

                if !stream.stream.isSupported {
                    Label(unsupportedReason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
        .opacity(stream.stream.isSupported ? 1 : 0.55)
        .contentShape(Rectangle())
    }

    private var qualityBadge: some View {
        let label = info.resolution?.label ?? "—"
        let isPremium = info.resolution == .uhd4k
        return Text(verbatim: label)
            .font(.system(.footnote, design: .rounded, weight: .heavy))
            .foregroundStyle(isPremium ? Color.black : Color.primary)
            .frame(width: 54, height: 30)
            .background(
                isPremium ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color.white.opacity(0.1)),
                in: .continuous(Theme.Radius.small)
            )
    }

    private var featureTags: [String] {
        var tags: [String] = []
        if info.isDolbyVision { tags.append("DV") }
        if info.isHDR { tags.append("HDR") }
        if info.isRemux { tags.append("REMUX") }
        if let source = info.source, !info.isRemux || source != "BluRay" { tags.append(source) }
        if info.isHEVC { tags.append("HEVC") }
        tags.append(contentsOf: info.audio.prefix(2))
        return tags
    }

    private var factLine: [(text: String, symbol: String)] {
        var facts: [(text: String, symbol: String)] = []
        if let size = info.sizeBytes {
            facts.append((ByteCountFormatter.string(fromByteCount: size, countStyle: .binary), "internaldrive"))
        }
        if let seeders = info.seeders {
            facts.append((seeders.formatted(), "person.2.fill"))
        }
        return facts
    }

    private var unsupportedReason: LocalizedStringKey {
        if case .torrent = stream.stream.kind {
            return "Torrent streams aren't supported. Use a debrid-enabled addon for direct links."
        }
        return "This stream type isn't supported."
    }
}
