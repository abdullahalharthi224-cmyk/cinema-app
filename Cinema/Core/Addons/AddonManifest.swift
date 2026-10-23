import Foundation

/// A Stremio addon manifest (`{base}/manifest.json`).
/// Spec: https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/manifest.md
struct AddonManifest: Codable, Hashable, Sendable {
    var id: String
    var version: String
    var name: String
    var description: String?
    var logo: String?
    var background: String?
    var types: [String]
    var catalogs: [CatalogDescriptor]
    var resources: [ResourceDescriptor]
    var idPrefixes: [String]?
    var behaviorHints: BehaviorHints?

    init(
        id: String,
        version: String = "1.0.0",
        name: String,
        description: String? = nil,
        logo: String? = nil,
        background: String? = nil,
        types: [String] = [],
        catalogs: [CatalogDescriptor] = [],
        resources: [ResourceDescriptor] = [],
        idPrefixes: [String]? = nil,
        behaviorHints: BehaviorHints? = nil
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.description = description
        self.logo = logo
        self.background = background
        self.types = types
        self.catalogs = catalogs
        self.resources = resources
        self.idPrefixes = idPrefixes
        self.behaviorHints = behaviorHints
    }

    enum CodingKeys: String, CodingKey {
        case id, version, name, description, logo, background, types, catalogs, resources, idPrefixes, behaviorHints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenient(String.self, forKey: .id), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "Manifest is missing its id"
            )
        }
        self.id = id
        version = c.flexibleString(forKey: .version) ?? "0.0.0"
        name = c.lenient(String.self, forKey: .name) ?? id
        description = c.lenient(String.self, forKey: .description)
        logo = c.lenient(String.self, forKey: .logo)
        background = c.lenient(String.self, forKey: .background)
        types = c.lossyArray(String.self, forKey: .types) ?? []
        catalogs = c.lossyArray(CatalogDescriptor.self, forKey: .catalogs) ?? []
        resources = c.lossyArray(ResourceDescriptor.self, forKey: .resources) ?? []
        idPrefixes = c.lossyArray(String.self, forKey: .idPrefixes)
        behaviorHints = c.lenient(BehaviorHints.self, forKey: .behaviorHints)
    }

    var logoURL: URL? { logo.flatMap(URL.init(string:)) }

    var resourceNames: [String] { resources.map(\.name) }

    var searchableCatalogs: [CatalogDescriptor] { catalogs.filter(\.supportsSearch) }

    /// Mirrors stremio-core's rules for deciding whether an addon should be
    /// asked for a given resource (`stream`, `meta`, `subtitles`, ...).
    func supports(resource: String, type: String, id: String? = nil) -> Bool {
        guard let descriptor = resources.first(where: { $0.name == resource }) else { return false }

        let types: [String]
        let prefixes: [String]?
        if descriptor.isShortForm {
            types = self.types
            prefixes = idPrefixes
        } else {
            types = descriptor.types ?? self.types
            prefixes = descriptor.idPrefixes
        }

        guard types.contains(type) else { return false }
        if let id, let prefixes, !prefixes.isEmpty {
            return prefixes.contains { id.hasPrefix($0) }
        }
        return true
    }
}

/// A resource entry can be a plain string (`"stream"`) or an object
/// (`{"name": "stream", "types": ["movie"], "idPrefixes": ["tt"]}`).
struct ResourceDescriptor: Codable, Hashable, Sendable {
    var name: String
    var types: [String]?
    var idPrefixes: [String]?

    var isShortForm: Bool { types == nil && idPrefixes == nil }

    init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
        self.name = name
        self.types = types
        self.idPrefixes = idPrefixes
    }

    enum CodingKeys: String, CodingKey { case name, types, idPrefixes }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self.init(name: name)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decode(String.self, forKey: .name),
            types: c.lossyArray(String.self, forKey: .types),
            idPrefixes: c.lossyArray(String.self, forKey: .idPrefixes)
        )
    }

    func encode(to encoder: Encoder) throws {
        if isShortForm {
            var single = encoder.singleValueContainer()
            try single.encode(name)
        } else {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(types, forKey: .types)
            try c.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
        }
    }
}

struct CatalogDescriptor: Codable, Hashable, Sendable {
    var type: String
    var id: String
    var name: String?
    var extra: [ExtraDescriptor]
    /// Legacy (pre-`extra`) way of declaring supported/required extras.
    var extraSupported: [String]?
    var extraRequired: [String]?

    var identity: String { "\(type)/\(id)" }
    var displayName: String { name ?? id }

    init(
        type: String,
        id: String,
        name: String? = nil,
        extra: [ExtraDescriptor] = [],
        extraSupported: [String]? = nil,
        extraRequired: [String]? = nil
    ) {
        self.type = type
        self.id = id
        self.name = name
        self.extra = extra
        self.extraSupported = extraSupported
        self.extraRequired = extraRequired
    }

    enum CodingKeys: String, CodingKey { case type, id, name, extra, extraSupported, extraRequired }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            type: try c.decode(String.self, forKey: .type),
            id: try c.decode(String.self, forKey: .id),
            name: c.lenient(String.self, forKey: .name),
            extra: c.lossyArray(ExtraDescriptor.self, forKey: .extra) ?? [],
            extraSupported: c.lossyArray(String.self, forKey: .extraSupported),
            extraRequired: c.lossyArray(String.self, forKey: .extraRequired)
        )
    }

    /// Every extra this catalog understands, merging the modern and legacy forms.
    var supportedExtraNames: Set<String> {
        Set(extra.map(\.name)).union(extraSupported ?? []).union(extraRequired ?? [])
    }

    var requiredExtraNames: Set<String> {
        Set(extra.filter(\.isRequired).map(\.name)).union(extraRequired ?? [])
    }

    var supportsSearch: Bool { supportedExtraNames.contains(ExtraName.search) }
    var supportsSkip: Bool { supportedExtraNames.contains(ExtraName.skip) }
    var supportsGenre: Bool { supportedExtraNames.contains(ExtraName.genre) }

    /// A catalog can be shown as a Home row only if it needs no input from the user.
    var isBrowsable: Bool { requiredExtraNames.isEmpty }

    var genreOptions: [String] {
        extra.first(where: { $0.name == ExtraName.genre })?.options ?? []
    }
}

struct ExtraDescriptor: Codable, Hashable, Sendable {
    var name: String
    var isRequired: Bool
    var options: [String]?
    var optionsLimit: Int?

    init(name: String, isRequired: Bool = false, options: [String]? = nil, optionsLimit: Int? = nil) {
        self.name = name
        self.isRequired = isRequired
        self.options = options
        self.optionsLimit = optionsLimit
    }

    enum CodingKeys: String, CodingKey { case name, isRequired, options, optionsLimit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decode(String.self, forKey: .name),
            isRequired: c.flexibleBool(forKey: .isRequired) ?? false,
            options: c.lossyArray(String.self, forKey: .options),
            optionsLimit: c.lenient(Int.self, forKey: .optionsLimit)
        )
    }
}

struct BehaviorHints: Codable, Hashable, Sendable {
    var adult: Bool?
    var p2p: Bool?
    var configurable: Bool?
    var configurationRequired: Bool?

    enum CodingKeys: String, CodingKey { case adult, p2p, configurable, configurationRequired }

    init(adult: Bool? = nil, p2p: Bool? = nil, configurable: Bool? = nil, configurationRequired: Bool? = nil) {
        self.adult = adult
        self.p2p = p2p
        self.configurable = configurable
        self.configurationRequired = configurationRequired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        adult = c.flexibleBool(forKey: .adult)
        p2p = c.flexibleBool(forKey: .p2p)
        configurable = c.flexibleBool(forKey: .configurable)
        configurationRequired = c.flexibleBool(forKey: .configurationRequired)
    }
}

/// Well-known extra names from the Stremio protocol.
enum ExtraName {
    static let search = "search"
    static let skip = "skip"
    static let genre = "genre"
}
