import SwiftUI

/// A compact card describing an addon: logo, name, version, description and what it provides.
struct ManifestSummaryView: View {
    let manifest: AddonManifest
    var logoSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                AddonLogoView(url: manifest.logoURL, name: manifest.name, size: logoSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manifest.name)
                        .font(.headline)
                    Text("Version \(manifest.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let description = manifest.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            FlowLayout {
                ForEach(manifest.resourceNames, id: \.self) { resource in
                    TagChip(text: resource.localizedResource, systemImage: resource.resourceSymbol, tint: Theme.accent)
                }
                ForEach(manifest.types, id: \.self) { type in
                    TagChip(text: type.localizedContentType)
                }
            }

            if manifest.behaviorHints?.configurationRequired == true {
                Label("This addon needs to be configured on its website first.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

extension String {
    var localizedResource: LocalizedStringKey {
        switch self {
        case "catalog": return "Catalogs"
        case "meta": return "Details"
        case "stream": return "Streams"
        case "subtitles": return "Subtitles"
        case "addon_catalog": return "Addon Catalogs"
        default: return LocalizedStringKey(self)
        }
    }

    var resourceSymbol: String {
        switch self {
        case "catalog": return "square.grid.2x2.fill"
        case "meta": return "info.circle.fill"
        case "stream": return "play.fill"
        case "subtitles": return "captions.bubble.fill"
        default: return "puzzlepiece.fill"
        }
    }
}
