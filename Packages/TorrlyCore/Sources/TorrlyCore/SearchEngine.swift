import Foundation

/// How providers are combined (TorrDroid `searchAlgoCode`, REPORT.md §2.8).
public enum SearchAlgorithm: String, Codable, CaseIterable, Sendable, Identifiable {
    /// One provider after another until one succeeds.
    case sequential
    /// All providers at once; the first success wins.
    case parallel
    /// The first provider; if it fails, the rest at once (TorrDroid's default "H").
    case hybrid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sequential: "One at a time"
        case .parallel: "All at once"
        case .hybrid: "First, then the rest"
        }
    }
}

/// Runs one search across the configured providers.
public struct SearchEngine: Sendable {
    public static let maxSuggestions = 8

    public var providers: [any SearchProvider]
    public var algorithm: SearchAlgorithm
    public var safeSearch: Bool

    public init(providers: [any SearchProvider], algorithm: SearchAlgorithm = .hybrid, safeSearch: Bool = true) {
        self.providers = providers
        self.algorithm = algorithm
        self.safeSearch = safeSearch
    }

    /// - Parameters:
    ///   - progress: live count of usable results found so far.
    ///   - startDownload: called for auto-download searches with the best reliable result; return true if it started.
    public func run(_ item: SearchItem,
                    progress: @escaping @Sendable (Int) -> Void = { _ in },
                    startDownload: @escaping @Sendable (SearchResult) async -> Bool = { _ in false }) async -> SearchOutcome {
        guard !providers.isEmpty else { return .failed(.noProviders) }
        let query = TextNormalizer.query(item.keyword, type: item.contentType)
        let filter = ResultFilter(query: query, contentType: item.contentType,
                                  maxSizeBytes: Int64(item.maxSizeMB) * 1024 * 1024, safeSearch: safeSearch)
        let siteQuery = ProviderQuery(text: TextNormalizer.siteQuery(query), contentType: item.contentType)
        let counter = ProgressCounter(report: progress)

        let attempt: @Sendable (any SearchProvider) async -> SearchOutcome = { provider in
            await Self.search(provider, query: siteQuery, filter: filter, autoDownload: item.autoDownload,
                              counter: counter, startDownload: startDownload)
        }

        var outcome: SearchOutcome
        switch algorithm {
        case .sequential:
            outcome = .failed(.cantReachSites)
            for provider in providers {
                outcome = outcome.merged(with: await attempt(provider))
                if outcome.isSuccess { break }
            }
        case .parallel:
            outcome = await Self.firstSuccess(of: providers, attempt: attempt)
        case .hybrid:
            outcome = await attempt(providers[0])
            if !outcome.isSuccess, providers.count > 1 {
                outcome = outcome.merged(with: await Self.firstSuccess(of: Array(providers.dropFirst()), attempt: attempt))
            }
        }
        if case let .results(results) = outcome {
            return .results(Array(ResultFilter.ranked(results).prefix(Self.maxSuggestions)))
        }
        return outcome
    }

    static func firstSuccess(of providers: [any SearchProvider],
                             attempt: @escaping @Sendable (any SearchProvider) async -> SearchOutcome) async -> SearchOutcome {
        await withTaskGroup(of: SearchOutcome.self) { group in
            for provider in providers {
                group.addTask { await attempt(provider) }
            }
            var merged = SearchOutcome.failed(.cantReachSites)
            for await outcome in group {
                merged = merged.merged(with: outcome)
                if outcome.isSuccess {
                    group.cancelAll()
                    return outcome
                }
            }
            return merged
        }
    }

    static func search(_ provider: any SearchProvider, query: ProviderQuery, filter: ResultFilter, autoDownload: Bool,
                       counter: ProgressCounter,
                       startDownload: @Sendable (SearchResult) async -> Bool) async -> SearchOutcome {
        let raw: [SearchResult]
        do {
            raw = try await provider.search(query)
        } catch {
            return .failed(.cantReachSites)
        }
        var kept: [SearchResult] = []
        var adultRemoved = false
        for result in raw {
            switch filter.verdict(for: result, categoryMatches: provider.categoryMatches(result, type: query.contentType)) {
            case .keep:
                kept.append(filter.annotate(result))
                counter.add(1)
            case .rejectAdult:
                adultRemoved = true
            case .reject:
                break
            }
        }
        let ranked = ResultFilter.ranked(kept)
        if autoDownload, let best = ranked.first(where: filter.isReliable), await startDownload(best) {
            return .downloadStarted(title: best.title)
        }
        if ranked.isEmpty { return .failed(adultRemoved ? .adultFiltered : .noTorrents) }
        return .results(Array(ranked.prefix(maxSuggestions)))
    }
}

final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let report: @Sendable (Int) -> Void

    init(report: @escaping @Sendable (Int) -> Void) {
        self.report = report
    }

    func add(_ n: Int) {
        let value = lock.withLock {
            count += n
            return count
        }
        report(value)
    }
}
