import Foundation
import Testing
@testable import TorrlyCore

struct TextNormalizerTests {
    @Test(arguments: [
        ("The Office Season 2 Episode 5", "the office s02e05"),
        ("the office 2x5", "the office s02e05"),
        ("The Office S2 E5", "the office s02e05"),
    ])
    func videoEpisodesAreNormalised(input: String, expected: String) {
        #expect(TextNormalizer.query(input, type: .video) == expected)
    }

    @Test func nonVideoKeepsNumbers() {
        #expect(TextNormalizer.query("Ubuntu 24.04 (desktop)!", type: .software) == "ubuntu 24 04 desktop")
    }

    @Test func siteQueryDropsNoiseWords() {
        #expect(TextNormalizer.siteQuery("inception full movie download") == "inception")
        #expect(TextNormalizer.siteQuery("dark side of the moon mp3") == "dark side of the moon")
    }

    @Test(arguments: [("5.7 GB", Int64(6_120_328_396)), ("700 MB", Int64(734_003_200)), ("512 KiB", Int64(524_288)), ("1,024", Int64(1024))])
    func parsesSizes(text: String, bytes: Int64) {
        #expect(TextNormalizer.size(text) == bytes)
    }

    @Test func episodeMatching() {
        #expect(TextNormalizer.episodeMatches(query: "the office s02e05", title: "the office s02e05 720p"))
        #expect(!TextNormalizer.episodeMatches(query: "the office s02e05", title: "the office s02e06 720p"))
        #expect(TextNormalizer.episodeMatches(query: "the office", title: "the office s02e06"))
    }
}

struct RankingTests {
    let filter = ResultFilter(query: "ubuntu desktop", contentType: .software)

    @Test func matchDistanceCountsSkippedWords() {
        #expect(filter.matchDistance(query: "ubuntu desktop", title: "ubuntu desktop amd64") == 0)
        #expect(filter.matchDistance(query: "ubuntu desktop", title: "ubuntu 24 04 desktop") == 2)
        #expect(filter.matchDistance(query: "ubuntu desktop", title: "ubuntu server") == 100)
        #expect(filter.matchDistance(query: "ubuntu desktop", title: "debian netinst") == .max)
    }

    @Test func rejectsUnrelatedOversizedAndAdult() {
        let sized = ResultFilter(query: "ubuntu", contentType: .software, maxSizeBytes: 2_000_000)
        #expect(sized.verdict(for: result("Ubuntu desktop", size: 3_000_000)) == .reject)
        #expect(sized.verdict(for: result("Ubuntu desktop", size: 1_000_000)) == .keep)
        #expect(filter.verdict(for: result("Debian netinst")) == .reject)
        #expect(filter.verdict(for: result("ubuntu desktop xxx edition")) == .rejectAdult)
        let unsafe = ResultFilter(query: "ubuntu desktop", contentType: .software, safeSearch: false)
        #expect(unsafe.verdict(for: result("ubuntu desktop xxx edition")) == .keep)
    }

    @Test func softwareNeedsTenSeeders() {
        #expect(filter.verdict(for: result("ubuntu desktop", seeds: 3)) == .reject)
        #expect(filter.verdict(for: result("ubuntu desktop", seeds: nil)) == .keep)
    }

    @Test func videoDropsTrailersUnlessAsked() {
        let video = ResultFilter(query: "dune", contentType: .video)
        #expect(video.verdict(for: result("Dune official trailer")) == .reject)
        #expect(ResultFilter(query: "dune trailer", contentType: .video).verdict(for: result("Dune official trailer")) == .keep)
    }

    @Test func ordersByQualityThenMatchThenSeeds() {
        let video = ResultFilter(query: "big buck bunny", contentType: .video)
        let ranked = ResultFilter.ranked([
            video.annotate(result("Big Buck Bunny 480p", seeds: 500)),
            video.annotate(result("Big Buck Bunny 1080p", seeds: 20)),
            video.annotate(result("Big Buck Bunny HDCAM 1080p", seeds: 900)),
            video.annotate(result("Big remastered Buck Bunny 1080p", seeds: 80)),
        ])
        #expect(ranked.map(\.title) == [
            "Big Buck Bunny 1080p", "Big remastered Buck Bunny 1080p", "Big Buck Bunny 480p", "Big Buck Bunny HDCAM 1080p",
        ])
    }

    @Test func scoreWeightsSeeders() {
        #expect(filter.annotate(result("ubuntu desktop", seeds: 10, leechers: 5)).score == 85)
        #expect(filter.annotate(result("ubuntu desktop", seeds: 10, leechers: 0)).score == 10)
    }
}

struct ModelTests {
    @Test func outcomePrecedence() {
        let a = result("a"), b = result("b")
        #expect(SearchOutcome.failed(.noTorrents).merged(with: .results([a])) == .results([a]))
        #expect(SearchOutcome.results([a]).merged(with: .results([b, a])) == .results([a, b]))
        #expect(SearchOutcome.results([a]).merged(with: .downloadStarted(title: "x")) == .downloadStarted(title: "x"))
        #expect(SearchOutcome.failed(.cantReachSites).merged(with: .failed(.noTorrents)) == .failed(.noTorrents))
        #expect(SearchOutcome.failed(.noTorrents).merged(with: .failed(.adultFiltered)) == .failed(.adultFiltered))
        #expect(SearchOutcome.failed(.adultFiltered).merged(with: .failed(.cantReachSites)) == .failed(.adultFiltered))
    }

    @Test func retriesUntilLimitThenDeactivates() {
        let start = Date(timeIntervalSince1970: 0)
        var item = SearchItem(keyword: "x", contentType: .software, retryInterval: .oneHour, autoDownload: false, createdAt: start)
        #expect(item.isDue(at: start))
        item.record(.failed(.noTorrents), at: start, maxRetries: 2)
        #expect(item.isActive)
        #expect(item.nextRunDate == start.addingTimeInterval(3600))
        #expect(!item.isDue(at: start.addingTimeInterval(1800)))
        item.record(.failed(.noTorrents), at: start.addingTimeInterval(3600), maxRetries: 2)
        #expect(item.isActive)
        item.record(.failed(.noTorrents), at: start.addingTimeInterval(7200), maxRetries: 2)
        #expect(!item.isActive)
        #expect(item.attempts == 3)
    }

    @Test func successAndNoRetryDeactivate() {
        var once = SearchItem(keyword: "x", contentType: .audio, retryInterval: .never, autoDownload: false)
        once.record(.failed(.noTorrents), at: Date(), maxRetries: 5)
        #expect(!once.isActive)
        var found = SearchItem(keyword: "x", contentType: .audio, retryInterval: .oneDay, autoDownload: false)
        found.record(.results([result("x")]), at: Date(), maxRetries: 5)
        #expect(!found.isActive)
    }

    @Test func magnetHelpers() {
        let link = Magnet.link(infoHash: "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD", name: "Linux Mint 22", trackers: ["udp://t.example:80/announce"])
        #expect(link == "magnet:?xt=urn:btih:abcdefabcdefabcdefabcdefabcdefabcdefabcd&dn=Linux%20Mint%2022&tr=udp%3A%2F%2Ft.example%3A80%2Fannounce")
        #expect(Magnet.infoHash(of: link) == "abcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(Magnet.displayName(of: link) == "Linux Mint 22")
        #expect(Magnet.isInfoHash("abcdefabcdefabcdefabcdefabcdefabcdefabcd"))
        #expect(!Magnet.isInfoHash("not-a-hash"))
    }

    @Test func formats() {
        #expect(Format.bytes(512) == "512 B")
        #expect(Format.bytes(1_572_864) == "1.5 MB")
        #expect(Format.duration(90061) == "1d 1h")
        #expect(Format.duration(3725) == "1h 2m")
        #expect(Format.eta(remaining: 100, rate: 0) == "∞")
    }
}

struct ProviderOrderTests {
    @Test func keepsProviderOrderWithoutSwarmData() {
        var big = result("Ubuntu collection", seeds: nil, leechers: nil, size: 60_000_000_000, source: "ia")
        big.providerRank = 3
        var popular = result("Ubuntu desktop", seeds: nil, leechers: nil, size: 5_000_000_000, source: "ia")
        popular.providerRank = 0
        #expect(ResultFilter.ranked([big, popular]).map(\.title) == ["Ubuntu desktop", "Ubuntu collection"])
    }
}

struct SearchSuggestionTests {
    @Test func parsesChromeSuggestReply() {
        let reply = Data(#"["ubun",["ubuntu","ubuntu 24.04","Ubuntu","ubuntu server"],["","",""],[],{"google:suggesttype":["QUERY"]}]"#.utf8)
        #expect(SearchSuggestions.parse(reply) == ["ubuntu", "ubuntu 24.04", "ubuntu server"])
        #expect(SearchSuggestions.parse(Data("not json".utf8)).isEmpty)
    }

    @Test func asksOnlyFromThreeCharacters() async {
        let http = MockHTTPClient()
        http.serve("https://suggestqueries.google.com/", Data(#"["deb",["debian","debian 13"]]"#.utf8))
        let suggestions = SearchSuggestions(http: http)
        #expect(await suggestions.suggestions(for: "de").isEmpty)
        #expect(http.requested.isEmpty)
        #expect(await suggestions.suggestions(for: "deb") == ["debian", "debian 13"])
        #expect(http.requested.first?.absoluteString == "https://suggestqueries.google.com/complete/search?client=chrome&q=deb")
    }
}
