import Foundation
import TorrlyCore
import TorrlyEngine

enum ThemeChoice: Int, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: "Use system default"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum EncryptionChoice: Int, Codable, CaseIterable, Identifiable {
    case prefer, require, disable

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .prefer: "Prefer encryption"
        case .require: "Require encryption"
        case .disable: "Disable encryption"
        }
    }
}

enum ProxyChoice: Int, Codable, CaseIterable, Identifiable {
    case none, socks4, socks5, http

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: "(None)"
        case .socks4: "SOCKS4"
        case .socks5: "SOCKS5"
        case .http: "HTTP"
        }
    }
}

/// Mirrors TorrDroid's preferences screen (REPORT.md §3.4).
struct AppSettings: Codable, Equatable {
    var wifiOnly = false
    /// TorrDroid's `max_attempts` (default 2): failed searches are retried this many times.
    var maxSearchRetries = 2
    var safeSearch = true
    /// Keyword suggestions while typing (sends the typed text to Google, as TorrDroid does).
    var searchSuggestions = true
    var seeding = true
    var theme = ThemeChoice.system
    /// KB/s, 0 = unlimited.
    var maxDownloadKBps = 0
    var maxUploadKBps = 0
    var encryption = EncryptionChoice.prefer
    var encryptIncoming = true
    var encryptOutgoing = true
    var randomizePort = true
    var randomPort = Int.random(in: 37000 ... 57000)
    var port = 6880
    var proxyType = ProxyChoice.none
    var proxyHost = ""
    var proxyPort = 1080
    var proxyNeedsAuth = false
    var proxyUsername = ""
    var proxyPassword = ""
    var searchAlgorithm = SearchAlgorithm.hybrid
    
    /// Version of the provider list migration.
    var providersVersion = 0

    var listenPort: Int { randomizePort ? randomPort : port }

    var engineSettings: EngineSettings {
        let s = EngineSettings()
        s.listenPort = Int32(listenPort)
        s.maxDownloadRate = Int32(maxDownloadKBps * 1024)
        s.maxUploadRate = Int32(maxUploadKBps * 1024)
        let policy: EngineEncryptionPolicy = switch encryption {
        case .prefer: .prefer
        case .require: .forced
        case .disable: .disabled
        }
        s.incomingEncryption = encryptIncoming ? policy : .disabled
        s.outgoingEncryption = encryptOutgoing ? policy : .disabled
        s.dhtEnabled = true
        s.proxyType = switch proxyType {
        case .none: .none
        case .socks4: .socks4
        case .socks5: .socks5
        case .http: .HTTP
        }
        s.proxyHost = proxyHost
        s.proxyPort = Int32(proxyPort)
        s.proxyUsername = proxyNeedsAuth ? proxyUsername : ""
        s.proxyPassword = proxyNeedsAuth ? proxyPassword : ""
        s.caBundlePath = Bundle.main.path(forResource: "cacert", ofType: "pem")
        return s
    }
}
