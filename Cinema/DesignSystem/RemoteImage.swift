import SwiftUI
import UIKit

/// Downloads and caches images: decoded images in memory, raw data on disk
/// (through a dedicated `URLCache`), and concurrent requests are coalesced.
actor ImagePipeline {
    static let shared = ImagePipeline()

    /// `NSCache` is thread-safe, so the memory cache can be read synchronously from views.
    private final class MemoryCache: @unchecked Sendable {
        let storage = NSCache<NSURL, UIImage>()
    }

    private nonisolated let memoryCache = MemoryCache()
    private nonisolated var memory: NSCache<NSURL, UIImage> { memoryCache.storage }
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memoryCache.storage.totalCostLimit = 120 * 1024 * 1024
    }

    nonisolated func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task<UIImage?, Never> { [session] in
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = UIImage(data: data)
            else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }
}

/// An image loaded from the network with a shimmering placeholder and a fade-in.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImagePipeline.shared.cachedImage(for: $0) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ImagePipeline.shared.cachedImage(for: url) {
                image = cached
                return
            }
            let loaded = await ImagePipeline.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

extension RemoteImage where Placeholder == ShimmerPlaceholder {
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) { ShimmerPlaceholder() }
    }
}

extension String {
    var asURL: URL? {
        guard !isEmpty else { return nil }
        return URL(string: self)
    }
}
