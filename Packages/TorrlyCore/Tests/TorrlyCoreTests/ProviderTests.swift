import Foundation
import Testing
@testable import TorrlyCore

struct ProviderTests {
    func importedRules() throws -> [String: ProviderDefinition] {
        let providers = try ProviderImport.providers(from: fixture("table-site-rules.json"))
        return Dictionary(uniqueKeysWithValues: providers.map { ($0.name, $0) })
    }

    @Test func importsTorrDroidSiteSettings() throws {
        let providers = try importedRules()
        #expect(providers.keys.sorted() == ["detail.example", "table.example"])
        let table = try #require(providers["table.example"]?.html)
        #expect(table.name.selector == "td:eq(1) > a:eq(0)")
        #expect(table.magnet == FieldRule(selector: "td:eq(1) > a:eq(0)", access: "href"))
        #expect(table.typeValidation?.software == ".*software.*")
    }

    @Test func providersRoundTripThroughJSON() throws {
        let providers = Array(try importedRules().values)
        let data = try JSONEncoder().encode(providers)
        let decoded = try ProviderImport.providers(from: data)
        #expect(Set(decoded) == Set(providers))
    }

    @Test func scrapesTableRows() async throws {
        let http = MockHTTPClient()
        http.serve("https://table.example/search/", fixture("table-site.html"))
        let provider = try #require(try importedRules()["table.example"]?.makeProvider(http: http))
        let results = try await provider.search(ProviderQuery(text: "ubuntu desktop", contentType: .software))
        #expect(http.requested.first?.absoluteString == "https://table.example/search/ubuntu%20desktop/0/1/seeders")
        #expect(results.count == 4)
        let first = try #require(results.first)
        #expect(first.title == "Ubuntu 24.04 Desktop amd64")
        #expect(first.seeds == 1204)
        #expect(first.leechers == 33)
        #expect(first.size == TextNormalizer.size("5.7 GB"))
        #expect(first.category == "Software")
        #expect(first.infoHash == String(repeating: "a", count: 40))
        #expect(provider.categoryMatches(first, type: .software))
        #expect(!provider.categoryMatches(results[2], type: .software))
    }

    @Test func followsDetailPagesForMagnets() async throws {
        let http = MockHTTPClient()
        http.serve("https://detail.example/search", fixture("detail-search.html"))
        let page = { (hash: String) in
            Data("""
            <html><body><div class="torrentinfo"><table><tbody><tr><td>Hash</td><td>\(hash)</td></tr></tbody></table></div>
            <div class="download_magnet"><a href="magnet:?xt=urn:btih:\(hash)">Magnet</a></div></body></html>
            """.utf8)
        }
        http.serve("https://detail.example/torrent/fedora-40", page(String(repeating: "4", count: 40)))
        http.fail("https://detail.example/torrent/fedora-39")
        let provider = try #require(try importedRules()["detail.example"]?.makeProvider(http: http))
        let results = try await provider.search(ProviderQuery(text: "fedora", contentType: .software))
        #expect(results.count == 1)
        #expect(results.first?.title == "Fedora 40 Workstation Live")
        #expect(results.first?.downloadURL == "magnet:?xt=urn:btih:" + String(repeating: "4", count: 40))
        #expect(results.first?.seeds == 512)
    }

    @Test func readsJSONAPIWithTorrentURLTemplate() async throws {
        let http = MockHTTPClient()
        http.serve("https://archive.org/advancedsearch.php", fixture("archive-search.json"))
        let provider = try #require(DefaultProviders.load().first?.makeProvider(http: http))
        let results = try await provider.search(ProviderQuery(text: "ubuntu", contentType: .software))
        #expect(http.requested.first?.absoluteString.contains("title%3A%28ubuntu%29%20AND%20mediatype%3Asoftware") == true)
        #expect(results.count == 2)
        #expect(results[0].downloadURL == "https://archive.org/download/ubuntu-20.04-arm64-utm/ubuntu-20.04-arm64-utm_archive.torrent")
        #expect(results[0].size == 3_870_948_735)
        #expect(results[0].seeds == nil)
        #expect(provider.categoryMatches(results[0], type: .software))
        #expect(!provider.categoryMatches(results[0], type: .video))
    }

    @Test func readsHashAPIAndSkipsPlaceholderRows() async throws {
        let rules = JSONAPIRules(url: URLTemplates(default: "https://api.example/q.php?q={query}"), name: "name", size: "size",
                                 seeds: "seeders", leechers: "leechers", infoHash: "info_hash", category: "category",
                                 skipWhen: ["id": "0"])
        let http = MockHTTPClient()
        http.serve("https://api.example/q.php?q=linux%20mint", fixture("hash-api.json"))
        http.serve("https://api.example/q.php?q=nothing", fixture("hash-api-empty.json"))
        let provider = JSONAPIProvider(name: "api", rules: rules, http: http)
        let results = try await provider.search(ProviderQuery(text: "linux mint", contentType: .software))
        #expect(results.count == 2)
        #expect(results[0].infoHash == "abcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(results[0].downloadURL.hasPrefix("magnet:?xt=urn:btih:abcdefabcdefabcdefabcdefabcdefabcdefabcd&dn=Linux%20Mint%2022"))
        #expect(results[0].seeds == 340)
        let empty = try await provider.search(ProviderQuery(text: "nothing", contentType: .software))
        #expect(empty.isEmpty)
    }
}

struct SearchEngineTests {
    let item = SearchItem(keyword: "Ubuntu Desktop", contentType: .software, retryInterval: .oneHour, autoDownload: false)

    @Test func sequentialStopsAtFirstSuccess() async {
        let down = StubProvider(name: "down", results: [], fails: true)
        let good = StubProvider(name: "good", results: [result("Ubuntu Desktop 24.04", seeds: 50)])
        let never = StubProvider(name: "never", results: [result("Ubuntu Desktop never", seeds: 99)])
        let engine = SearchEngine(providers: [down, good, never], algorithm: .sequential)
        let outcome = await engine.run(item)
        guard case let .results(results) = outcome else { Issue.record("expected results, got \(outcome)"); return }
        #expect(results.map(\.title) == ["Ubuntu Desktop 24.04"])
    }

    @Test func hybridFallsBackToTheRest() async {
        let empty = StubProvider(name: "empty", results: [result("Debian", seeds: 50)])
        let good = StubProvider(name: "good", results: [result("Ubuntu Desktop", seeds: 50)])
        let outcome = await SearchEngine(providers: [empty, good], algorithm: .hybrid).run(item)
        #expect(outcome == .results([result("Ubuntu Desktop", seeds: 50)]))
    }

    @Test func reportsWhyNothingWasFound() async {
        let down = StubProvider(name: "down", results: [], fails: true)
        #expect(await SearchEngine(providers: [down], algorithm: .parallel).run(item) == .failed(.cantReachSites))
        let adult = StubProvider(name: "adult", results: [result("ubuntu desktop xxx", seeds: 50)])
        #expect(await SearchEngine(providers: [down, adult], algorithm: .parallel).run(item) == .failed(.adultFiltered))
        #expect(await SearchEngine(providers: []).run(item) == .failed(.noProviders))
    }

    @Test func autoDownloadStartsBestReliableResult() async {
        var auto = item
        auto.autoDownload = true
        let provider = StubProvider(name: "p", results: [
            result("Ubuntu Desktop small", seeds: 15, size: 100),
            result("Ubuntu Desktop big", seeds: 900, size: 200),
        ])
        let started = Locked<[String]>([])
        let outcome = await SearchEngine(providers: [provider]).run(auto, startDownload: { candidate in
            started.mutate { $0.append(candidate.title) }
            return true
        })
        #expect(outcome == .downloadStarted(title: "Ubuntu Desktop big"))
        #expect(started.value == ["Ubuntu Desktop big"])
    }

    @Test func capsSuggestionsAtEight() async {
        let many = (1 ... 12).map { result("Ubuntu Desktop build \($0)", seeds: 10 + $0) }
        let outcome = await SearchEngine(providers: [StubProvider(name: "p", results: many)]).run(item)
        guard case let .results(results) = outcome else { Issue.record("expected results"); return }
        #expect(results.count == 8)
        #expect(results.first?.seeds == 22)
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}
