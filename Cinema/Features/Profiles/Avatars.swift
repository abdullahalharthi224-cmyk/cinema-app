import PhotosUI
import SwiftUI
import UIKit

/// What a profile's picture is. Stored in `Profile.symbol` so older profiles (SF Symbols) keep working:
/// "emoji:🦁" is a character, "photo" a picture from the album, anything else an SF Symbol.
enum AvatarKind: Equatable {
    case symbol(String)
    case emoji(String)
    case photo

    static let photoTag = "photo"
    private static let emojiPrefix = "emoji:"

    init(_ raw: String) {
        if raw == Self.photoTag {
            self = .photo
        } else if raw.hasPrefix(Self.emojiPrefix) {
            self = .emoji(String(raw.dropFirst(Self.emojiPrefix.count)))
        } else {
            self = .symbol(raw)
        }
    }

    var raw: String {
        switch self {
        case .symbol(let name): return name
        case .emoji(let emoji): return Self.emojiPrefix + emoji
        case .photo: return Self.photoTag
        }
    }

    /// The characters to pick from: Apple's emoji, drawn large.
    static let characters = [
        "🦁", "🐼", "🦊", "🐯", "🐨", "🐸", "🐵", "🦄", "🐙", "🐧", "🐶", "🐱",
        "🐰", "🐻", "🐲", "🦖", "🐳", "🦉", "🐝", "🦋", "👾", "🤖", "👻", "🍿",
    ]

    /// Playful characters a kids profile starts with.
    static let kidsCharacters = ["🦄", "🐼", "🐸", "🐵", "🐙", "🦖"]
}

/// Two-colour backgrounds for avatars, named by their first colour (kept in `Profile.colorHex`).
enum AvatarBackground {
    static let gradients: [(String, String)] = [
        ("#F7B267", "#F25C54"), ("#FFD86F", "#FC6262"), ("#A1C4FD", "#5B7FE8"), ("#84FAB0", "#3FA9D6"),
        ("#FBC2EB", "#A18CD1"), ("#C9A962", "#6E5526"), ("#E0474C", "#7A1E22"), ("#9D7CFF", "#4B3399"),
        ("#3E9BFF", "#1B4D8C"), ("#3DBE8B", "#17644A"), ("#FF5FA2", "#A23B72"), ("#8E9AAF", "#4A5266"),
        // Colours from before gradients, so existing profiles get a partner too.
        ("#FF7A59", "#B23A1E"), ("#F2C14E", "#B9700E"), ("#2EC4B6", "#11706A"),
    ]

    /// The colours offered in the editor (the older ones are only kept for existing profiles).
    static var choices: [String] { gradients.prefix(12).map(\.0) }

    static func colors(for hex: String) -> [Color] {
        let first = Color(hex: hex) ?? Theme.accent
        guard let partner = gradients.first(where: { $0.0.caseInsensitiveCompare(hex) == .orderedSame })?.1,
              let second = Color(hex: partner)
        else { return [first, first.opacity(0.55)] }
        return [first, second]
    }
}

/// Pictures chosen from the album, cropped round and saved small, one per profile.
@MainActor
enum AvatarStore {
    private static var cache: [UUID: UIImage] = [:]

    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Avatars", directoryHint: .isDirectory)
    }

    static func url(for id: UUID) -> URL { folder.appending(path: "\(id.uuidString).jpg") }

    static func image(for id: UUID) -> UIImage? {
        if let cached = cache[id] { return cached }
        guard let data = try? Data(contentsOf: url(for: id)), let image = UIImage(data: data) else { return nil }
        cache[id] = image
        return image
    }

    static func save(_ image: UIImage, for id: UUID) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url(for: id), options: .atomic)
        cache[id] = image
    }

    static func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
        cache[id] = nil
    }
}

/// A profile's picture: a character, a photo or a symbol, on its gradient. The same everywhere
/// (Home, Settings, the profile picker, the lock screen and the widget).
struct ProfileAvatar: View {
    let symbol: String
    let colorHex: String
    var size: CGFloat = 96
    /// The album picture, for `AvatarKind.photo`.
    var photo: UIImage? = nil

    private var kind: AvatarKind { AvatarKind(symbol) }
    private var colors: [Color] { AvatarBackground.colors(for: colorHex) }

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                // A soft highlight across the top, like glass.
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                    .padding(size * 0.04)
            }
            .overlay { content }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: max(0.75, size / 120)))
            .frame(width: size, height: size)
            .shadow(color: colors[0].opacity(0.35), radius: size * 0.15, y: size * 0.06)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .emoji(let emoji):
            Text(verbatim: emoji)
                .font(.system(size: size * 0.58))
                .shadow(color: .black.opacity(0.18), radius: size * 0.03, y: size * 0.02)
                .offset(y: size * 0.02)
        case .photo:
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                symbolImage("person.fill")
            }
        case .symbol(let name):
            symbolImage(name)
        }
    }

    private func symbolImage(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

extension ProfileAvatar {
    @MainActor
    init(profile: Profile, size: CGFloat = 96) {
        let photo = AvatarKind(profile.symbol) == .photo ? AvatarStore.image(for: profile.id) : nil
        self.init(symbol: profile.symbol, colorHex: profile.colorHex, size: size, photo: photo)
    }
}

/// Crop a picture to a circle: drag to move it, pinch to zoom.
struct CircularCropView: View {
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) - 48
                let fit = side / max(1, min(image.size.width, image.size.height))
                let shown = CGSize(width: image.size.width * fit * scale, height: image.size.height * fit * scale)
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(offset)
                    // Everything outside the circle is dimmed.
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .mask {
                            Rectangle()
                                .overlay(Circle().frame(width: side, height: side).blendMode(.destinationOut))
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                    Circle()
                        .strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                        .frame(width: side, height: side)
                        .allowsHitTesting(false)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = Self.clamped(
                                CGSize(width: dragStart.width + value.translation.width, height: dragStart.height + value.translation.height),
                                shown: shown, side: side
                            )
                        }
                        .onEnded { _ in dragStart = offset }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { value in
                                scale = min(5, max(1, scaleStart * value.magnification))
                                let resized = CGSize(width: image.size.width * fit * scale, height: image.size.height * fit * scale)
                                offset = Self.clamped(offset, shown: resized, side: side)
                            }
                            .onEnded { _ in
                                scaleStart = scale
                                dragStart = offset
                            })
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Choose") {
                            onDone(Self.crop(image, side: side, scale: fit * scale, offset: offset))
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Move and Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Keeps the picture covering the whole circle.
    static func clamped(_ offset: CGSize, shown: CGSize, side: CGFloat) -> CGSize {
        let limitX = max(0, (shown.width - side) / 2), limitY = max(0, (shown.height - side) / 2)
        return CGSize(width: min(limitX, max(-limitX, offset.width)), height: min(limitY, max(-limitY, offset.height)))
    }

    /// The part of `image` inside the circle, as a 512-point square. `scale` is screen points per image point.
    static func crop(_ image: UIImage, side: CGFloat, scale: CGFloat, offset: CGSize) -> UIImage {
        let originX = (side - image.size.width * scale) / 2 + offset.width
        let originY = (side - image.size.height * scale) / 2 + offset.height
        let rect = CGRect(x: -originX / scale, y: -originY / scale, width: side / scale, height: side / scale)
        let output: CGFloat = 512
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: output, height: output), format: format).image { _ in
            let k = output / rect.width
            image.draw(in: CGRect(x: -rect.minX * k, y: -rect.minY * k, width: image.size.width * k, height: image.size.height * k))
        }
    }

    /// Big photos are shrunk before cropping, to keep memory low.
    static func prepared(_ image: UIImage, longest: CGFloat = 1600) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > longest else { return image }
        let k = longest / largest
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
