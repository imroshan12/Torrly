import Foundation
@testable import TorrlyCore

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/" + name, withExtension: nil)!
    return try! Data(contentsOf: url)
}

/// Serves canned responses by URL prefix and records requested URLs.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [(prefix: String, data: Data?)] = []
    private(set) var requested: [URL] = []

    func serve(_ prefix: String, _ data: Data) { lock.withLock { routes.append((prefix, data)) } }
    func fail(_ prefix: String) { lock.withLock { routes.append((prefix, nil)) } }

    func get(_ url: URL, referer: URL?) async throws -> (Data, URL) {
        let route = lock.withLock {
            requested.append(url)
            return routes.first { url.absoluteString.hasPrefix($0.prefix) }
        }
        guard let route, let data = route.data else { throw URLError(.cannotConnectToHost) }
        return (data, url)
    }
}

struct StubProvider: SearchProvider {
    var name: String
    var results: [SearchResult]
    var fails = false

    func search(_ query: ProviderQuery) async throws -> [SearchResult] {
        if fails { throw URLError(.timedOut) }
        return results
    }

    func categoryMatches(_ result: SearchResult, type: ContentType) -> Bool { true }
}

func result(_ title: String, seeds: Int? = 10, leechers: Int? = 1, size: Int64 = 1_000_000, source: String = "stub") -> SearchResult {
    SearchResult(title: title, size: size, seeds: seeds, leechers: leechers,
                 downloadURL: "magnet:?xt=urn:btih:" + String(repeating: "\(abs(title.hashValue) % 10)", count: 40) + "&dn=\(title.count)\(title.hashValue)",
                 source: source)
}
