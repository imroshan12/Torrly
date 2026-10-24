import Foundation

/// Saves one Codable value as a JSON file, atomically.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public enum DefaultProviders {
    /// Providers bundled with the app (Resources/default-providers.json).
    public static func load() -> [ProviderDefinition] {
        guard let url = Bundle.module.url(forResource: "default-providers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let providers = try? ProviderImport.providers(from: data) else { return [] }
        return providers
    }
}
