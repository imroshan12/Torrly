import Foundation
import SwiftSoup

public struct ProviderQuery: Sendable {
    public var text: String
    public var contentType: ContentType

    public init(text: String, contentType: ContentType) {
        self.text = text
        self.contentType = contentType
    }
}

public enum ProviderError: LocalizedError, Sendable {
    case badURL
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .badURL: "The provider's search URL is invalid."
        case let .unreadable(detail): "Couldn't read the page: \(detail)"
        }
    }
}

public protocol SearchProvider: Sendable {
    var name: String { get }
    func search(_ query: ProviderQuery) async throws -> [SearchResult]
    /// Category check for a result of this provider.
    func categoryMatches(_ result: SearchResult, type: ContentType) -> Bool
}

public extension ProviderDefinition {
    func makeProvider(http: HTTPClient) -> (any SearchProvider)? {
        if let html { return HTMLProvider(name: name, rules: html, http: http) }
        if let json { return JSONAPIProvider(name: name, rules: json, http: http) }
        return nil
    }
}

// MARK: - HTML

/// Generic scraper driven by `HTMLSiteRules` (TorrDroid `kb.g`).
public struct HTMLProvider: SearchProvider {
    public let name: String
    let rules: HTMLSiteRules
    let http: HTTPClient
    /// Detail pages fetched per search, at most (each costs a request).
    var detailPageLimit = 12

    public init(name: String, rules: HTMLSiteRules, http: HTTPClient) {
        self.name = name
        self.rules = rules
        self.http = http
    }

    public func categoryMatches(_ result: SearchResult, type: ContentType) -> Bool {
        guard let validation = rules.typeValidation else { return true }
        return validation.matches(category: result.category, type: type)
    }

    public func search(_ query: ProviderQuery) async throws -> [SearchResult] {
        guard let url = rules.request.url.url(for: query.contentType, query: query.text) else { throw ProviderError.badURL }
        let (data, finalURL) = try await http.get(url, referer: nil)
        let html = String(decoding: data, as: UTF8.self)
        var results = try parse(html: html, pageURL: finalURL)
        if let more = rules.more {
            results = try await withThrowingTaskGroup(of: (Int, SearchResult?).self) { group in
                for (index, pending) in results.enumerated().prefix(detailPageLimit) {
                    group.addTask { (index, try? await fillFromDetailPage(pending, rule: more)) }
                }
                var filled = [SearchResult?](repeating: nil, count: results.count)
                for try await (index, value) in group { filled[index] = value }
                return Self.numbered(filled.compactMap { $0 }.filter { !$0.downloadURL.isEmpty })
            }
        }
        return Self.numbered(results.filter { !$0.downloadURL.isEmpty })
    }

    /// Parses a result page. Rows without a magnet/torrent link keep their detail link in `downloadURL`
    /// with a `detail:` prefix until `fillFromDetailPage` resolves it.
    func parse(html: String, pageURL: URL) throws -> [SearchResult] {
        let document = try SwiftSoup.parse(html, pageURL.absoluteString)
        var results: [SearchResult] = []
        for row in try document.select(rules.rows) {
            guard let title = try Self.value(rules.name, in: row, base: pageURL), !title.isEmpty else { continue }
            let size = try rules.size.flatMap { try Self.value($0, in: row, base: pageURL) }.map(TextNormalizer.size) ?? 0
            let seeds = try rules.seeds.flatMap { try Self.value($0, in: row, base: pageURL) }.flatMap(TextNormalizer.integer)
            let leechers = try rules.leechers.flatMap { try Self.value($0, in: row, base: pageURL) }.flatMap(TextNormalizer.integer)
            let category = try rules.type.flatMap { try Self.value($0, in: row, base: pageURL) }
            let hash = try rules.hash.flatMap { try Self.value($0, in: row, base: pageURL) }
            var link = try rules.magnet.flatMap { try Self.value($0, in: row, base: pageURL) }
                ?? rules.torrent.flatMap { try Self.value($0, in: row, base: pageURL) }
            if link == nil, let hash, Magnet.isInfoHash(hash) {
                link = Magnet.link(infoHash: hash, name: title)
            }
            if link == nil, let more = rules.more,
               let detail = try Self.value(FieldRule(selector: more.qs, access: "href"), in: row, base: pageURL) {
                link = "detail:" + detail
            }
            guard let link, Self.isUsable(link) || link.hasPrefix("detail:") else { continue }
            results.append(SearchResult(title: title, size: size, seeds: seeds, leechers: leechers, downloadURL: link,
                                        infoHash: hash ?? Magnet.infoHash(of: link), source: name, category: category))
        }
        return results
    }

    func fillFromDetailPage(_ result: SearchResult, rule: DetailPageRule) async throws -> SearchResult? {
        guard result.downloadURL.hasPrefix("detail:") else { return result }
        guard let url = URL(string: String(result.downloadURL.dropFirst("detail:".count))) else { return nil }
        let (data, finalURL) = try await http.get(url, referer: nil)
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), finalURL.absoluteString)
        guard let body = document.body() else { return nil }
        var filled = result
        let page = rule.page
        if let hash = try page.hash.flatMap({ try Self.value($0, in: body, base: finalURL) }) {
            filled.infoHash = hash.lowercased()
        }
        if let category = try page.type.flatMap({ try Self.value($0, in: body, base: finalURL) }) {
            filled.category = category
        }
        if filled.size == 0, let size = try page.size.flatMap({ try Self.value($0, in: body, base: finalURL) }) {
            filled.size = TextNormalizer.size(size)
        }
        var trackers: [String] = []
        if let trackerRule = page.trackers {
            trackers = try body.select(trackerRule.selector).array().map { try $0.text() }.filter { $0.contains("://") }
        }
        if let magnet = try page.magnet.flatMap({ try Self.value($0, in: body, base: finalURL) }), Self.isUsable(magnet) {
            filled.downloadURL = magnet
        } else if let torrent = try page.torrent.flatMap({ try Self.value($0, in: body, base: finalURL) }), Self.isUsable(torrent) {
            filled.downloadURL = torrent
        } else if let hash = filled.infoHash, Magnet.isInfoHash(hash) {
            filled.downloadURL = Magnet.link(infoHash: hash, name: result.title, trackers: trackers.isEmpty ? Magnet.defaultTrackers : trackers)
        } else {
            return nil
        }
        filled.infoHash = filled.infoHash ?? Magnet.infoHash(of: filled.downloadURL)
        return filled
    }

    static func value(_ rule: FieldRule, in element: Element, base: URL) throws -> String? {
        guard let target = try element.select(rule.selector).first() else { return nil }
        let access = rule.access ?? "text"
        let raw: String
        if access == "text" {
            raw = try target.text()
        } else if access == "href" || access == "src" {
            raw = try target.attr("abs:" + access).nonEmpty ?? target.attr(access)
        } else {
            raw = try target.attr(access)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func numbered(_ results: [SearchResult]) -> [SearchResult] {
        results.enumerated().map { index, result in
            var numbered = result
            numbered.providerRank = index
            return numbered
        }
    }

    static func isUsable(_ link: String) -> Bool {
        link.hasPrefix("magnet:") || ((link.hasPrefix("http://") || link.hasPrefix("https://")) && link.lowercased().contains(".torrent"))
            || link.lowercased().hasSuffix(".torrent")
    }
}

// MARK: - JSON

public struct JSONAPIProvider: SearchProvider {
    public let name: String
    let rules: JSONAPIRules
    let http: HTTPClient

    public init(name: String, rules: JSONAPIRules, http: HTTPClient) {
        self.name = name
        self.rules = rules
        self.http = http
    }

    public func categoryMatches(_ result: SearchResult, type: ContentType) -> Bool {
        guard let validation = rules.typeValidation else { return true }
        return validation.matches(category: result.category, type: type)
    }

    public func search(_ query: ProviderQuery) async throws -> [SearchResult] {
        guard let url = rules.url.url(for: query.contentType, query: query.text) else { throw ProviderError.badURL }
        let (data, _) = try await http.get(url, referer: nil)
        return try parse(data)
    }

    func parse(_ data: Data) throws -> [SearchResult] {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProviderError.unreadable("not JSON")
        }
        let path = rules.resultsPath ?? ""
        let container: Any? = path.isEmpty ? root : Self.lookup(path, in: root)
        guard let items = container as? [[String: Any]] else {
            throw ProviderError.unreadable("no results array at '\(path)'")
        }
        return HTMLProvider.numbered(items.compactMap(result(from:)))
    }

    func result(from item: [String: Any]) -> SearchResult? {
        if let skip = rules.skipWhen, skip.contains(where: { Self.string(Self.lookup($0.key, in: item)) == $0.value }) {
            return nil
        }
        guard let title = Self.string(Self.lookup(rules.name, in: item)), !title.isEmpty else { return nil }
        let sizeValue = rules.size.flatMap { Self.lookup($0, in: item) }
        let size: Int64 = if let number = sizeValue as? NSNumber {
            number.int64Value
        } else if let text = Self.string(sizeValue) {
            Int64(text) ?? TextNormalizer.size(text)
        } else {
            0
        }
        let seeds = rules.seeds.flatMap { Self.string(Self.lookup($0, in: item)) }.flatMap(TextNormalizer.integer)
        let leechers = rules.leechers.flatMap { Self.string(Self.lookup($0, in: item)) }.flatMap(TextNormalizer.integer)
        let hash = rules.infoHash.flatMap { Self.string(Self.lookup($0, in: item)) }?.lowercased()
        let category = rules.category.flatMap { Self.string(Self.lookup($0, in: item)) }

        var link: String?
        if let field = rules.magnet, let magnet = Self.string(Self.lookup(field, in: item)), magnet.hasPrefix("magnet:") {
            link = magnet
        } else if let hash, Magnet.isInfoHash(hash) {
            link = Magnet.link(infoHash: hash, name: title)
        } else if let template = rules.torrentURL {
            link = Self.fill(template, from: item)
        }
        guard let link else { return nil }
        return SearchResult(title: title, size: size, seeds: seeds, leechers: leechers, downloadURL: link,
                            infoHash: hash ?? Magnet.infoHash(of: link), source: name, category: category)
    }

    static func lookup(_ path: String, in object: Any) -> Any? {
        var current: Any? = object
        for key in path.split(separator: ".") {
            if let dict = current as? [String: Any] {
                current = dict[String(key)]
            } else if let array = current as? [Any], let index = Int(key), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        case let array as [Any]: array.first.flatMap { string($0) }
        default: nil
        }
    }

    static func fill(_ template: String, from item: [String: Any]) -> String? {
        var result = template
        for match in template.matches(of: /\{([A-Za-z0-9_.]+)\}/) {
            guard let value = string(lookup(String(match.output.1), in: item)),
                  let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
            result = result.replacingOccurrences(of: String(match.output.0), with: encoded)
        }
        return result
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
