import Foundation

/// What the user is looking for. Raw values match TorrDroid's `fileType` codes.
public enum ContentType: Int, Codable, CaseIterable, Sendable, Identifiable {
    case audio = 1
    case video = 2
    case ebook = 3
    case software = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .audio: "audio"
        case .video: "video"
        case .ebook: "ebook"
        case .software: "software"
        }
    }
}

/// How long to wait before retrying a search that found nothing. Minutes match TorrDroid's `time_values`.
public enum RetryInterval: Int, Codable, CaseIterable, Sendable, Identifiable {
    case never = 0
    case fiveMinutes = 5
    case oneHour = 60
    case threeHours = 180
    case twelveHours = 720
    case oneDay = 1440

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    public var title: String {
        switch self {
        case .never: "Don't retry"
        case .fiveMinutes: "5 minutes"
        case .oneHour: "1 hour"
        case .threeHours: "3 hours"
        case .twelveHours: "12 hours"
        case .oneDay: "1 day"
        }
    }
}

/// One torrent found by a provider.
public struct SearchResult: Codable, Hashable, Sendable, Identifiable {
    public var id: String { downloadURL }
    /// The title as shown on the site.
    public var title: String
    /// Lower-cased, punctuation-free title used for matching.
    public var normalizedTitle: String
    public var size: Int64
    /// `nil` when the provider does not publish swarm counts.
    public var seeds: Int?
    public var leechers: Int?
    /// A magnet link or an http(s) URL of a .torrent file.
    public var downloadURL: String
    public var infoHash: String?
    /// Provider name.
    public var source: String
    public var category: String?
    /// Title contains one of the preferred quality words (1080p, bluray, …).
    public var preferredQuality: Bool = false
    /// Title looks like a low-quality camera or telesync rip.
    public var lowQuality: Bool = false
    /// Words skipped while matching the query in order; lower is better (`Int.max` = no match).
    public var matchDistance: Int = .max
    public var score: Int = 0
    /// Position in the provider's own result list (its relevance or popularity order).
    public var providerRank: Int = 0

    public init(title: String, size: Int64, seeds: Int?, leechers: Int?, downloadURL: String, infoHash: String? = nil,
                source: String, category: String? = nil) {
        self.title = title
        self.normalizedTitle = TextNormalizer.title(title)
        self.size = size
        self.seeds = seeds
        self.leechers = leechers
        self.downloadURL = downloadURL
        self.infoHash = infoHash
        self.source = source
        self.category = category
    }

    public static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.downloadURL == rhs.downloadURL }
    public func hash(into hasher: inout Hasher) { hasher.combine(downloadURL) }
}

/// Why a search produced nothing. Raw values follow TorrDroid's failure codes.
public enum SearchFailure: Int, Codable, Sendable {
    case cantReachSites = 1
    case noTorrents = 2
    case adultFiltered = 3
    case noProviders = 4

    public var message: String {
        switch self {
        case .cantReachSites:
            "Can't reach websites. Please check internet connection or try again later."
        case .noTorrents:
            "No reliable torrent to display. Please check the spelling of the keyword or edit it to contain fewer details."
        case .adultFiltered:
            "No reliable torrent to display. Results for adult content have been hidden as per settings."
        case .noProviders:
            "No search providers are enabled. Add or enable one in Settings › Search providers."
        }
    }

    /// When results from several providers are merged, the more useful failure wins (TorrDroid `jb.i.a`).
    func merged(with other: SearchFailure) -> SearchFailure {
        switch (self, other) {
        case (.cantReachSites, _): other
        case (.noTorrents, .adultFiltered), (.noTorrents, .noProviders): other
        case (.noProviders, .adultFiltered): other
        default: self
        }
    }
}

public enum SearchOutcome: Codable, Sendable, Equatable {
    case results([SearchResult])
    case downloadStarted(title: String)
    case failed(SearchFailure)

    public var isSuccess: Bool {
        if case .failed = self { return false }
        return true
    }

    /// Precedence: started download > results (unioned) > failure.
    public func merged(with other: SearchOutcome) -> SearchOutcome {
        switch (self, other) {
        case (.downloadStarted, _): self
        case (_, .downloadStarted): other
        case let (.results(a), .results(b)): .results(a + b.filter { !a.contains($0) })
        case (.results, .failed): self
        case (.failed, .results): other
        case let (.failed(a), .failed(b)): .failed(a.merged(with: b))
        }
    }
}

public enum SearchStatus: String, Codable, Sendable {
    case idle
    case queued
    case searching
}

/// A saved search. It is re-run on its retry interval until it succeeds or runs out of retries.
public struct SearchItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var keyword: String
    public var contentType: ContentType
    public var retryInterval: RetryInterval
    public var autoDownload: Bool
    /// Upper size limit in MB; 0 means no limit.
    public var maxSizeMB: Int
    public var isActive: Bool
    public var attempts: Int
    public var createdAt: Date
    public var lastRun: Date?
    public var outcome: SearchOutcome?
    public var status: SearchStatus
    /// Live count while a search is running.
    public var foundSoFar: Int

    public init(id: UUID = UUID(), keyword: String, contentType: ContentType, retryInterval: RetryInterval,
                autoDownload: Bool, maxSizeMB: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.keyword = keyword
        self.contentType = contentType
        self.retryInterval = retryInterval
        self.autoDownload = autoDownload
        self.maxSizeMB = maxSizeMB
        self.isActive = true
        self.attempts = 0
        self.createdAt = createdAt
        self.status = .queued
        self.foundSoFar = 0
    }

    /// When the search should run next, or nil if it is finished.
    public var nextRunDate: Date? {
        guard isActive else { return nil }
        guard let lastRun else { return createdAt }
        guard retryInterval != .never else { return nil }
        return lastRun.addingTimeInterval(retryInterval.seconds)
    }

    public func isDue(at date: Date) -> Bool {
        guard status != .searching, let next = nextRunDate else { return false }
        return next <= date
    }

    /// Records one finished attempt (TorrDroid `SearchService.k`).
    public mutating func record(_ outcome: SearchOutcome, at date: Date, maxRetries: Int) {
        self.outcome = outcome
        lastRun = date
        attempts += 1
        status = .idle
        foundSoFar = 0
        if outcome.isSuccess || retryInterval == .never || attempts > maxRetries {
            isActive = false
        }
    }
}
