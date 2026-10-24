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

    private var colors: [URL: UIColor] = [:]

    /// The most characterful colour of an image, used to tint backgrounds.
    func dominantColor(for url: URL) async -> UIColor? {
        if let color = colors[url] { return color }
        guard let image = await image(for: url), let color = image.dominantColor() else { return nil }
        colors[url] = color
        return color
    }
}

extension UIImage {
    /// The average brightness (0…1) of the visible pixels, ignoring transparent ones.
    func averageOpaqueLuminance() -> Double? {
        guard let cgImage else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0, weight = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.3 else { continue }
            // Un-premultiply, then perceived luminance.
            let r = Double(pixels[index]) / 255 / alpha
            let g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha
            total += (0.2126 * r + 0.7152 * g + 0.0722 * b) * alpha
            weight += alpha
        }
        return weight > 0 ? total / weight : nil
    }

    /// Averages a tiny thumbnail, favouring saturated, mid-bright pixels so the
    /// result is a rich colour rather than a muddy grey.
    func dominantColor() -> UIColor? {
        guard let cgImage else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var red = 0.0, green = 0.0, blue = 0.0, totalWeight = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let maxValue = max(r, g, b), minValue = min(r, g, b)
            let saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue
            // Penalise near-black and blown-out pixels.
            let brightnessWeight = 1 - abs(maxValue - 0.6) / 0.6
            let weight = 0.05 + saturation * max(brightnessWeight, 0)
            red += r * weight
            green += g * weight
            blue += b * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        return UIColor(red: red / totalWeight, green: green / totalWeight, blue: blue / totalWeight, alpha: 1)
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

/// Tries each URL in turn (then, optionally, one more found on demand) and
/// shows `failure` instead of an endless placeholder when none loads.
struct FallbackImage<Placeholder: View, Failure: View>: View {
    let urls: [URL]
    var contentMode: ContentMode = .fill
    /// Asked once every URL has failed, e.g. to look the artwork up on TMDB.
    var resolveMore: (@Sendable () async -> URL?)?
    var placeholder: () -> Placeholder
    var failure: () -> Failure

    @State private var image: UIImage?
    @State private var failed = false

    init(
        urls: [URL], contentMode: ContentMode = .fill, resolveMore: (@Sendable () async -> URL?)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder, @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.urls = urls
        self.contentMode = contentMode
        self.resolveMore = resolveMore
        self.placeholder = placeholder
        self.failure = failure
        _image = State(initialValue: urls.first.flatMap { ImagePipeline.shared.cachedImage(for: $0) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                failure()
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: urls) {
            failed = false
            for url in urls {
                if let cached = ImagePipeline.shared.cachedImage(for: url) {
                    image = cached
                    return
                }
                if let loaded = await ImagePipeline.shared.image(for: url) {
                    withAnimation(.easeOut(duration: 0.25)) { image = loaded }
                    return
                }
                guard !Task.isCancelled else { return }
            }
            if let resolveMore, let url = await resolveMore(), let loaded = await ImagePipeline.shared.image(for: url) {
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
                return
            }
            guard !Task.isCancelled else { return }
            image = nil
            withAnimation(.easeOut(duration: 0.25)) { failed = true }
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
