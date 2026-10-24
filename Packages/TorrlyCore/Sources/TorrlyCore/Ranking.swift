import Foundation

/// Filtering and ordering of results (REPORT.md §2.9).
public struct ResultFilter: Sendable {
    public var query: String
    public var contentType: ContentType
    /// 0 = no limit.
    public var maxSizeBytes: Int64
    public var safeSearch: Bool

    /// Preferred quality words (TorrDroid `type_options`).
    public static let preferredWords = ["hdtv", "bdrip", "brrip", "1080p", "bluray", "hdrip", "dvdrip", "720p", "webrip"]
    public static func isMature(_ text: String) -> Bool { text.wholeMatch(of: /.*(porn|xxx|hentai|adult).*/) != nil }
    static func isLowQuality(_ text: String) -> Bool {
        text.wholeMatch(of: /.*(\W|_)(ts|cam(rip)?|hdts|hdcam|predvd)((\W|_).*|$)/) != nil
    }

    static func isTrailer(_ text: String) -> Bool { text.wholeMatch(of: /.*(teaser|trailer).*/) != nil }

    public init(query: String, contentType: ContentType, maxSizeBytes: Int64 = 0, safeSearch: Bool = true) {
        self.query = query
        self.contentType = contentType
        self.maxSizeBytes = maxSizeBytes
        self.safeSearch = safeSearch
    }

    public enum Verdict: Equatable, Sendable {
        case keep
        case reject
        case rejectAdult
    }

    /// Decides whether a result fits the search.
    public func verdict(for result: SearchResult, categoryMatches: Bool = true) -> Verdict {
        let title = result.normalizedTitle
        let category = result.category?.lowercased() ?? ""
        if safeSearch, Self.isMature(title) || Self.isMature(category) {
            return .rejectAdult
        }
        guard categoryMatches else { return .reject }
        if maxSizeBytes > 0, result.size > maxSizeBytes { return .reject }
        if TextNormalizer.isEpisodic(query), !TextNormalizer.episodeMatches(query: query, title: title) { return .reject }
        if contentType == .video, Self.isTrailer(title), !Self.isTrailer(query) {
            return .reject
        }
        if contentType == .software, let seeds = result.seeds, seeds < 10 { return .reject }
        return matchDistance(query: TextNormalizer.withoutEpisode(query), title: title) == .max ? .reject : .keep
    }

    /// Adds the ranking fields to a kept result.
    public func annotate(_ result: SearchResult) -> SearchResult {
        var r = result
        r.matchDistance = matchDistance(query: TextNormalizer.withoutEpisode(query), title: r.normalizedTitle)
        r.lowQuality = Self.isLowQuality(r.normalizedTitle)
        r.preferredQuality = contentType == .video && !r.lowQuality && Self.preferredWords.contains { r.normalizedTitle.contains($0) }
        let seeds = r.seeds ?? 0
        let leechers = r.leechers ?? 0
        r.score = leechers == 0 ? seeds : seeds * 8 + leechers
        return r
    }

    /// Title words skipped while matching the query words in order (TorrDroid `ab.p2` constructor).
    /// Out-of-order words cost 1 (not allowed for video), each missing word costs 100,
    /// and `Int.max` means no query word appears at all.
    public func matchDistance(query: String, title: String) -> Int {
        let queryWords = query.split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init)
        let titleWords = title.split(separator: " ").map(String.init)
        guard !queryWords.isEmpty else { return .max }
        var skipped = 0
        var missing = 0
        var position = 0
        for word in queryWords {
            if position < titleWords.count, let index = titleWords[position...].firstIndex(of: word) {
                skipped += index - position
                position = index + 1
            } else if contentType != .video, titleWords.contains(word) {
                skipped += 1
            } else {
                missing += 1
            }
        }
        return missing == queryWords.count ? .max : skipped + missing * 100
    }

    /// TorrDroid `jb.n`: preferred quality, then title match, seeders, leechers, size (bigger first), score.
    public static func ranked(_ results: [SearchResult]) -> [SearchResult] {
        results.sorted { a, b in
            if a.preferredQuality != b.preferredQuality { return a.preferredQuality }
            if a.lowQuality != b.lowQuality { return !a.lowQuality }
            if a.matchDistance != b.matchDistance { return a.matchDistance < b.matchDistance }
            if a.seeds == nil, b.seeds == nil, a.source == b.source, a.providerRank != b.providerRank {
                // No swarm data: keep the provider's own popularity order.
                return a.providerRank < b.providerRank
            }
            if (a.seeds ?? -1) != (b.seeds ?? -1) { return (a.seeds ?? -1) > (b.seeds ?? -1) }
            if (a.leechers ?? -1) != (b.leechers ?? -1) { return (a.leechers ?? -1) > (b.leechers ?? -1) }
            if a.size != b.size { return a.size > b.size }
            if a.score != b.score { return a.score > b.score }
            return a.title < b.title
        }
    }

    /// Whether a result is good enough to download without asking.
    public func isReliable(_ result: SearchResult) -> Bool {
        guard !result.lowQuality, result.matchDistance <= 3 else { return false }
        if let seeds = result.seeds { return seeds > 0 }
        return true
    }
}
