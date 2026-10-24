import Foundation

public enum Magnet {
    /// Public trackers added to magnets built from a bare info hash (TorrDroid appends its own list, REPORT.md §3.2;
    /// most of those are dead, so this list is current).
    public static let defaultTrackers = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.demonii.com:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://explodie.org:6969/announce",
        "udp://tracker.dler.org:6969/announce",
        "http://tracker.opentrackr.org:1337/announce",
    ]

    public static func isInfoHash(_ text: String) -> Bool {
        text.wholeMatch(of: /[0-9a-fA-F]{40}/) != nil || text.wholeMatch(of: /[A-Z2-7a-z]{32}/) != nil
    }

    public static func link(infoHash: String, name: String?, trackers: [String] = defaultTrackers) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#:/")
        var link = "magnet:?xt=urn:btih:\(infoHash.lowercased())"
        if let name, let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) {
            link += "&dn=\(encoded)"
        }
        for tracker in trackers {
            if let encoded = tracker.addingPercentEncoding(withAllowedCharacters: allowed) { link += "&tr=\(encoded)" }
        }
        return link
    }

    /// The btih hash of a magnet link, lower-cased.
    public static func infoHash(of link: String) -> String? {
        guard link.hasPrefix("magnet:"), let match = link.firstMatch(of: /xt=urn:btih:([0-9A-Za-z]+)/) else { return nil }
        return String(match.output.1).lowercased()
    }

    public static func displayName(of link: String) -> String? {
        guard let components = URLComponents(string: link) else { return nil }
        return components.queryItems?.first { $0.name == "dn" }?.value
    }
}

public enum Format {
    /// "1.4 GB", like TorrDroid's `%.1f%sB`.
    public static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(max(0, value))
        var unit = 0
        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        return unit == 0 ? "\(Int(size)) B" : String(format: "%.1f %@", size, units[unit])
    }

    public static func speed(_ bytesPerSecond: Int) -> String {
        bytes(Int64(bytesPerSecond)) + "/s"
    }

    /// "2d 4h", "3h 12m", "5m 9s", "12s" (TorrDroid `m.java`).
    public static func duration(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "0s" }
        let years = seconds / 31_536_000
        let days = seconds % 31_536_000 / 86400
        let hours = seconds % 86400 / 3600
        let minutes = seconds % 3600 / 60
        let secs = seconds % 60
        if years > 0 { return "\(years)y \(days)d" }
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    public static func eta(remaining: Int64, rate: Int) -> String {
        rate > 0 ? duration(remaining / Int64(rate)) : "∞"
    }
}
