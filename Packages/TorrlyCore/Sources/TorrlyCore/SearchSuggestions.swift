import Foundation

/// Keyword suggestions while typing, from Google's public suggest service, like TorrDroid's search box
/// (`ab.a2` + `ab.k`: 3+ characters, `client=chrome`, reply `[query, [suggestion, …], …]`).
public struct SearchSuggestions: Sendable {
    public static let minimumLength = 3

    let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    public static func url(for text: String) -> URL? {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.queryItems = [URLQueryItem(name: "client", value: "chrome"), URLQueryItem(name: "q", value: text)]
        return components?.url
    }

    /// Suggestions for `text`, or an empty list when it is too short or the request fails.
    public func suggestions(for text: String) async -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= Self.minimumLength, let url = Self.url(for: trimmed),
              let (data, _) = try? await http.get(url, referer: nil) else { return [] }
        return Self.parse(data)
    }

    public static func parse(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any], root.count > 1,
              let list = root[1] as? [Any] else { return [] }
        var seen = Set<String>()
        return list.compactMap { $0 as? String }.filter { seen.insert($0.lowercased()).inserted }
    }
}
