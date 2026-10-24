import Foundation

/// A search site the user has configured. Providers are data, not code: HTML rules use the same JSON
/// schema as TorrDroid's remote `siteSettings` (REPORT.md §2.6, §5a).
public struct ProviderDefinition: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var html: HTMLSiteRules?
    public var json: JSONAPIRules?

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, html: HTMLSiteRules? = nil, json: JSONAPIRules? = nil) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.html = html
        self.json = json
    }

    public var kindLabel: String { html != nil ? "HTML scraper" : "JSON API" }
}

/// Search URLs per content type. `{query}` (or TorrDroid's `%s`) is replaced by the encoded query.
public struct URLTemplates: Codable, Hashable, Sendable {
    public var `default`: String
    public var audio: String?
    public var video: String?
    public var ebook: String?
    public var software: String?

    public init(default: String, audio: String? = nil, video: String? = nil, ebook: String? = nil, software: String? = nil) {
        self.default = `default`
        self.audio = audio
        self.video = video
        self.ebook = ebook
        self.software = software
    }

    public func url(for type: ContentType, query: String) -> URL? {
        let specific: String? = switch type {
        case .audio: audio
        case .video: video
        case .ebook: ebook
        case .software: software
        }
        let template = specific ?? `default`
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?/#")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        let filled = template
            .replacingOccurrences(of: "{query}", with: encoded)
            .replacingOccurrences(of: "%s", with: encoded)
        return URL(string: filled)
    }
}

/// Category patterns used to check a result's category against the requested type (TorrDroid `kb.d`).
public struct TypeValidation: Codable, Hashable, Sendable {
    public var video: String?
    public var audio: String?
    public var ebook: String?
    public var software: String?
    public var mature: String?

    public init(video: String? = nil, audio: String? = nil, ebook: String? = nil, software: String? = nil, mature: String? = nil) {
        self.video = video
        self.audio = audio
        self.ebook = ebook
        self.software = software
        self.mature = mature
    }

    public func matches(category: String?, type: ContentType) -> Bool {
        guard let category = category?.lowercased(), !category.isEmpty else { return true }
        let pattern = switch type {
        case .video: video ?? ".*(video|movie|t(ele)?v|film|anime|porn|xxx).*"
        case .audio: audio ?? ".*(music|audio|songs).*"
        case .ebook: ebook ?? ".*(book|tutorial).*"
        case .software: software ?? "^(?=.*(app|game|other|software))(?!.*(book|tutorial|movie|t(ele)?v|film|porn|xxx|video|audio|music)).*$"
        }
        guard let regex = try? Regex(pattern) else { return true }
        return category.wholeMatch(of: regex) != nil
    }
}

/// How to read one value from an HTML element: a CSS selector (jsoup syntax, e.g. `td:eq(1) > a`)
/// whose text is used, or `{ "qs": selector, "access": "href" }` to read an attribute.
public struct FieldRule: Codable, Hashable, Sendable {
    public var selector: String
    /// `nil` or "text" means the element's text; anything else is an attribute name.
    public var access: String?

    public init(selector: String, access: String? = nil) {
        self.selector = selector
        self.access = access
    }

    enum CodingKeys: String, CodingKey {
        case qs, access
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            selector = text
            access = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selector = try container.decode(String.self, forKey: .qs)
        access = try container.decodeIfPresent(String.self, forKey: .access)
    }

    public func encode(to encoder: Encoder) throws {
        if access == nil || access == "text" {
            var single = encoder.singleValueContainer()
            try single.encode(selector)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(selector, forKey: .qs)
            try container.encode(access, forKey: .access)
        }
    }
}

/// TorrDroid's "more": follow a link in the row and read fields from the detail page.
public struct DetailPageRule: Codable, Hashable, Sendable {
    public struct Page: Codable, Hashable, Sendable {
        public var magnet: FieldRule?
        public var hash: FieldRule?
        public var type: FieldRule?
        public var size: FieldRule?
        public var torrent: FieldRule?
        public var trackers: FieldRule?
    }

    /// Selector of the link to follow (its `href` is used).
    public var qs: String
    public var page: Page
}

public struct HTMLSiteRules: Codable, Hashable, Sendable {
    public struct Request: Codable, Hashable, Sendable {
        public var type: String?
        public var url: URLTemplates

        public init(type: String? = "GET", url: URLTemplates) {
            self.type = type
            self.url = url
        }
    }

    public var request: Request
    /// Selects one element per result.
    public var rows: String
    public var name: FieldRule
    public var size: FieldRule?
    public var seeds: FieldRule?
    public var leechers: FieldRule?
    public var type: FieldRule?
    public var hash: FieldRule?
    public var magnet: FieldRule?
    /// Link to a .torrent file in the row.
    public var torrent: FieldRule?
    public var more: DetailPageRule?
    public var typeValidation: TypeValidation?

    public init(request: Request, rows: String, name: FieldRule, size: FieldRule? = nil, seeds: FieldRule? = nil,
                leechers: FieldRule? = nil, type: FieldRule? = nil, hash: FieldRule? = nil, magnet: FieldRule? = nil,
                torrent: FieldRule? = nil, more: DetailPageRule? = nil, typeValidation: TypeValidation? = nil) {
        self.request = request
        self.rows = rows
        self.name = name
        self.size = size
        self.seeds = seeds
        self.leechers = leechers
        self.type = type
        self.hash = hash
        self.magnet = magnet
        self.torrent = torrent
        self.more = more
        self.typeValidation = typeValidation
    }
}

/// A site with a JSON search API. Field names are dot paths into each result object.
public struct JSONAPIRules: Codable, Hashable, Sendable {
    public var url: URLTemplates
    /// Dot path to the results array; empty means the response itself is the array.
    public var resultsPath: String?
    public var name: String
    public var size: String?
    public var seeds: String?
    public var leechers: String?
    public var infoHash: String?
    public var magnet: String?
    /// URL of the .torrent file; `{field}` placeholders are filled from the result object.
    public var torrentURL: String?
    public var category: String?
    /// Results where `field` equals the given value are skipped (e.g. a "no results" placeholder row).
    public var skipWhen: [String: String]?
    public var typeValidation: TypeValidation?

    public init(url: URLTemplates, resultsPath: String? = nil, name: String, size: String? = nil, seeds: String? = nil,
                leechers: String? = nil, infoHash: String? = nil, magnet: String? = nil, torrentURL: String? = nil,
                category: String? = nil, skipWhen: [String: String]? = nil, typeValidation: TypeValidation? = nil) {
        self.url = url
        self.resultsPath = resultsPath
        self.name = name
        self.size = size
        self.seeds = seeds
        self.leechers = leechers
        self.infoHash = infoHash
        self.magnet = magnet
        self.torrentURL = torrentURL
        self.category = category
        self.skipWhen = skipWhen
        self.typeValidation = typeValidation
    }
}

public enum ProviderImport {
    public enum ImportError: LocalizedError {
        case unrecognized

        public var errorDescription: String? {
            "Expected a provider, a list of providers, or a TorrDroid-style siteSettings object."
        }
    }

    /// Accepts a Torrly provider, an array of them, or a TorrDroid `siteSettings` map (`{ "https://site": rules }`).
    public static func providers(from data: Data) throws -> [ProviderDefinition] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([ProviderDefinition].self, from: data) { return list }
        if let single = try? decoder.decode(ProviderDefinition.self, from: data) { return [single] }
        if let map = try? decoder.decode([String: HTMLSiteRules].self, from: data), !map.isEmpty {
            return map.keys.sorted().compactMap { key in
                guard let rules = map[key] else { return nil }
                let name = URL(string: key)?.host() ?? key
                return ProviderDefinition(name: name, html: rules)
            }
        }
        throw ImportError.unrecognized
    }
}
