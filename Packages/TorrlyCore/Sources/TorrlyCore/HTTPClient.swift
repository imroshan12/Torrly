import Foundation

public protocol HTTPClient: Sendable {
    /// Returns the body and the final URL after redirects.
    func get(_ url: URL, referer: URL?) async throws -> (Data, URL)
}

public struct HTTPStatusError: LocalizedError, Sendable {
    public var statusCode: Int
    public var errorDescription: String? { "HTTP \(statusCode)" }
}

/// URLSession client that presents itself as desktop Firefox, like TorrDroid's `m.z()` (REPORT.md §2.7).
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 10) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 3
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0",
            "Accept-Language": "en-US,en;q=0.8",
            "Upgrade-Insecure-Requests": "1",
        ]
        session = URLSession(configuration: config)
    }

    public func get(_ url: URL, referer: URL?) async throws -> (Data, URL) {
        var request = URLRequest(url: url)
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw HTTPStatusError(statusCode: http.statusCode)
        }
        return (data, response.url ?? url)
    }
}
