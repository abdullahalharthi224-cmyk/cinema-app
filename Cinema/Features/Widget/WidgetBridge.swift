import Foundation
import UIKit
import WidgetKit

/// Keeps the Home Screen widget up to date: the active profile's Continue
/// Watching (titles in the app's language, artwork saved small) and today's
/// new episodes, written to the App Group container.
@MainActor
enum WidgetBridge {
    /// False when the signing removed the App Group, so the widget can't see the app's data.
    static var isAvailable: Bool { WidgetShared.containerURL != nil }

    private static var lastSignature = ""

    static func update(history: [WatchHistoryItem], newToday: [TasteModel.EpisodeEntry]) async {
        guard let imagesURL = WidgetShared.imagesURL else { return }
        let recent = Array(history.prefix(3))
        let signature = (recent.map { "\($0.key)|\(Int($0.progress * 20))" } + newToday.map(\.id)).joined(separator: ",")
            + "|\(Appearance.shared.language.rawValue)"
        guard signature != lastSignature else { return }
        lastSignature = signature

        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        var used = Set<String>()
        var items: [WidgetSnapshot.Item] = []
        for item in recent {
            let localized = await localizedTitle(id: item.metaID, name: item.name)
            let poster = await saveImage(
                from: Artwork.posters(id: item.metaID, provided: item.poster?.asURL),
                name: "poster-\(safeName(item.metaID)).jpg", width: 360, into: imagesURL
            )
            let backdrop = await saveImage(
                from: [Artwork.background(id: item.metaID, provided: item.background)].compactMap { $0 },
                name: "backdrop-\(safeName(item.metaID)).jpg", width: 900, into: imagesURL
            )
            used.formUnion([poster, backdrop].compactMap { $0 })
            items.append(WidgetSnapshot.Item(
                id: item.key,
                title: localized ?? item.name,
                subtitle: item.displayEpisodeLabel,
                progress: item.progress,
                posterFile: poster,
                backdropFile: backdrop,
                link: WidgetShared.continueLink(key: item.key)
            ))
        }

        let episodes = newToday.prefix(2).map { entry in
            WidgetSnapshot.Item(
                id: entry.id,
                title: entry.schedule.name,
                subtitle: localized("S%lld E%lld", entry.episode.season, entry.episode.episode),
                progress: 0,
                posterFile: nil,
                backdropFile: nil,
                link: WidgetShared.homeLink
            )
        }

        let snapshot = WidgetSnapshot(
            items: items,
            newToday: Array(episodes),
            rightToLeft: Appearance.shared.language.isRightToLeft,
            labels: .init(
                continueWatching: localized("Continue Watching"),
                newToday: localized("New Today"),
                startWatching: localized("Start Watching")
            ),
            updatedAt: .now
        )
        try? snapshot.save()
        removeUnused(in: imagesURL, keeping: used)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.kind)
    }

    private static func localizedTitle(id: String, name: String) async -> String? {
        guard let language = TitleLocalizer.lookupLanguage(for: name), let client = TMDBAccount.shared.client else { return nil }
        return await TitleLocalizer.shared.localize(
            id: id, wantsLogo: false, client: client, language: language
        )?.title
    }

    /// Downloads the first image that works, shrinks it and saves it as JPEG. Reuses a saved copy.
    private static func saveImage(from urls: [URL], name: String, width: CGFloat, into folder: URL) async -> String? {
        let destination = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { return name }
        for url in urls {
            guard let result = try? await URLSession.shared.data(from: url),
                  ((result.1 as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                  let image = UIImage(data: result.0)
            else { continue }
            let scale = min(1, width / max(image.size.width, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { continue }
            try? jpeg.write(to: destination, options: .atomic)
            return name
        }
        return nil
    }

    private static func removeUnused(in folder: URL, keeping used: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !used.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    private static func safeName(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}
