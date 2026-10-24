import Foundation

/// Query and title clean-up, mirroring TorrDroid's `SearchService.i`, `jb.k.a/l/m` (REPORT.md §2.3, §2.9).
public enum TextNormalizer {
    /// Lower-cases and strips punctuation. For video, "season 2 episode 5", "2x5" and "s2 e5" become "s02e05".
    public static func query(_ keyword: String, type: ContentType) -> String {
        var text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == .video,
           let match = text.firstMatch(of: /\b(season\s*\d+\s*ep\w*\s*\d+|\d+\s*x\s*\d+|s\s*\d+\s*e\s*\d+)/) {
            let numbers = String(match.output.0).matches(of: /\d+/).compactMap { Int($0.output) }
            if numbers.count >= 2 {
                let replacement = String(format: " s%02de%02d", numbers[0], numbers[1])
                text.replaceSubrange(match.range, with: replacement)
            }
        }
        return collapse(text.replacing(/[^\p{L}\p{N}']+/, with: " "))
    }

    /// Removes words sites don't index well ("mp3", "full movie download", "torrent", …) before sending the query.
    public static func siteQuery(_ query: String, stripSymbols: Bool = true) -> String {
        var text = query.replacing(/mp3|audio|music|e?book(?!s)|(\s+(full|movies?|download|in(?=\s)))+|torrents?|films?/, with: "")
        if stripSymbols { text = text.replacing(/\W+/, with: " ") }
        return collapse(text)
    }

    /// Title form used for matching: lower-case, letters and digits only.
    public static func title(_ title: String) -> String {
        collapse(title.lowercased().replacing(/[\W_]/, with: " "))
    }

    /// The query with season/episode markers removed, used to match titles word by word.
    public static func withoutEpisode(_ query: String) -> String {
        collapse(query
            .replacing(/\s+((season\s*\d+)|(ep(isode)?\s*\d+)|(s(\d+e)?\d+)|(\d+\s*x\s*\d+))/, with: "")
            .replacing(/[\W_]+/, with: " "))
    }

    public static func isEpisodic(_ query: String) -> Bool {
        query.contains(/.*\s((season\s*)|(ep(isode)?\s*)|(s(\d+e)?)|(\d+x))\d+.*/)
    }

    /// Season/episode numbers in the query must appear, in order, in the title (TorrDroid `jb.k.b`).
    public static func episodeMatches(query: String, title: String) -> Bool {
        guard let wanted = episodeNumbers(in: query, limit: 2) else { return true }
        return episodeNumbers(in: title, limit: wanted.count) == wanted
    }

    static func episodeNumbers(in text: String, limit: Int) -> [Int]? {
        var numbers: [Int] = []
        for match in text.matches(of: /\s*(season\s*\d+)|(ep\w*\s*\d+)|(s\s*\d+(\s*e\s*\d+)?)|(\d+\s*x\s*\d+)/) {
            for n in String(match.output.0).matches(of: /\d+/) {
                guard numbers.count < limit, let value = Int(n.output) else { break }
                numbers.append(value)
            }
            if numbers.count == limit { break }
        }
        return numbers.isEmpty ? nil : numbers
    }

    /// Parses "1.4 GB", "700 MiB", "512 KB" into bytes (TorrDroid `jb.k.k`).
    public static func size(_ text: String) -> Int64 {
        let lower = text.lowercased()
        guard let match = lower.firstMatch(of: /(\d+(?:\.\d+)?)[ \s]*([kmgt])?i?b/) else {
            return Int64(lower.filter(\.isNumber)) ?? 0
        }
        let value = Double(match.output.1) ?? 0
        let multiplier: Double = switch match.output.2 {
        case "k": 1024
        case "m": 1024 * 1024
        case "g": 1024 * 1024 * 1024
        case "t": 1024 * 1024 * 1024 * 1024
        default: 1
        }
        return Int64(value * multiplier)
    }

    /// "1,234" → 1234.
    public static func integer(_ text: String) -> Int? {
        let digits = text.filter { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    static func collapse(_ text: String) -> String {
        text.replacing(/\s\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    }
}
