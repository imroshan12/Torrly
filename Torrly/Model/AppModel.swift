import BackgroundTasks
import Foundation
import Observation
import SwiftUI
import TorrlyCore
import TorrlyEngine

enum AppTab: Int, CaseIterable, Identifiable {
    case history, search, downloads

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .history: "HISTORY"
        case .search: "SEARCH"
        case .downloads: "DOWNLOADS"
        }
    }
}

/// App state: saved searches and their scheduler, providers and settings (TorrDroid `SearchService`, REPORT.md §2).
@Observable
@MainActor
final class AppModel {
    static let refreshTaskID = "com.sarvesh.torrly.search-refresh"

    var tab: AppTab = .search
    private(set) var searches: [SearchItem] = []
    private(set) var providers: [ProviderDefinition] = []
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings)
            downloads.apply(settings)
        }
    }

    var toast: String?
    /// A finished file to open in the player or Quick Look.
    var openingFile: OpenableFile?
    /// Search to scroll to in History (from a notification tap).
    var focusedSearch: UUID?

    let downloads: DownloadManager
    let notifier = Notifier()
    let suggestions = SearchSuggestions(http: URLSessionHTTPClient(timeout: 5))

    @ObservationIgnored private let searchStore: JSONFileStore<[SearchItem]>
    @ObservationIgnored private let providerStore: JSONFileStore<[ProviderDefinition]>
    @ObservationIgnored private let settingsStore = SettingsStore()
    @ObservationIgnored private let http = URLSessionHTTPClient()
    @ObservationIgnored private var schedulerTask: Task<Void, Never>?
    @ObservationIgnored private var running: Set<UUID> = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        searchStore = JSONFileStore(url: support.appending(path: "searches.json"))
        providerStore = JSONFileStore(url: support.appending(path: "providers.json"))
        let loadedSettings = settingsStore.load()
        settings = loadedSettings
        downloads = DownloadManager(settings: loadedSettings)
        downloads.notifier = notifier
        searches = searchStore.load() ?? []
        providers = providerStore.load() ?? DefaultProviders.load()
        // A search interrupted by the app being killed is queued again.
        for index in searches.indices where searches[index].status == .searching {
            searches[index].status = searches[index].isActive ? .queued : .idle
        }
    }

    // MARK: Searches

    /// Validates the form like TorrDroid's search tab, saves the search and runs it.
    func submitSearch(keyword: String, type: ContentType?, interval: RetryInterval, autoDownload: Bool, maxSizeMB: Int) -> String? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Please enter a keyword to search" }
        guard let type else { return "Please select a Torrent type from the dropdown box" }
        let item = SearchItem(keyword: trimmed, contentType: type, retryInterval: interval, autoDownload: autoDownload, maxSizeMB: maxSizeMB)
        searches.insert(item, at: 0)
        persistSearches()
        tab = .history
        run(item.id)
        return nil
    }

    func update(_ item: SearchItem) {
        guard let index = searches.firstIndex(where: { $0.id == item.id }) else { return }
        var edited = item
        edited.isActive = true
        edited.status = .queued
        edited.attempts = 0
        edited.lastRun = nil
        searches[index] = edited
        persistSearches()
        run(item.id)
    }

    func deleteSearch(_ id: UUID) {
        searches.removeAll { $0.id == id }
        persistSearches()
    }

    func clearHistory() {
        searches.removeAll { $0.status != .searching }
        persistSearches()
    }

    /// Runs a saved search now (the search icon on a History card).
    func run(_ id: UUID) {
        guard !running.contains(id), let index = searches.firstIndex(where: { $0.id == id }) else { return }
        running.insert(id)
        searches[index].status = .searching
        searches[index].foundSoFar = 0
        let item = searches[index]
        let engine = makeEngine()
        Task {
            let outcome = await engine.run(item, progress: { count in
                Task { @MainActor in self.setFound(count, for: id) }
            }, startDownload: { result in
                await self.autoDownload(result)
            })
            finish(id, outcome: outcome)
        }
    }

    private func autoDownload(_ result: SearchResult) async -> Bool {
        do {
            try await downloads.add(result: result, bySearch: true)
            return true
        } catch {
            return false
        }
    }

    private func setFound(_ count: Int, for id: UUID) {
        guard let index = searches.firstIndex(where: { $0.id == id }), searches[index].status == .searching else { return }
        searches[index].foundSoFar = count
    }

    private func finish(_ id: UUID, outcome: SearchOutcome) {
        running.remove(id)
        guard let index = searches.firstIndex(where: { $0.id == id }) else { return }
        searches[index].record(outcome, at: Date(), maxRetries: settings.maxSearchRetries)
        let item = searches[index]
        persistSearches()
        let inForeground = UIApplication.shared.applicationState == .active
        switch outcome {
        case .results:
            if !inForeground { notifier.suggestionsAvailable(keyword: item.keyword, searchID: id) }
        case let .downloadStarted(title):
            notifier.downloadStarted(name: title)
        case let .failed(reason):
            // TorrDroid only notifies on the first failure and every 100th.
            if !inForeground, item.attempts == 1 || item.attempts % 100 == 0 {
                notifier.searchComplete(keyword: item.keyword, message: reason.message, searchID: id)
            }
        }
        scheduleBackgroundRefresh()
    }

    private func makeEngine() -> SearchEngine {
        let enabled = providers.filter(\.isEnabled).compactMap { $0.makeProvider(http: http) }
        return SearchEngine(providers: enabled, algorithm: settings.searchAlgorithm, safeSearch: settings.safeSearch)
    }

    func runDueSearches() {
        let now = Date()
        for item in searches where item.isDue(at: now) {
            run(item.id)
        }
    }

    /// Checks for due searches every 30 seconds while the app is open.
    func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.runDueSearches()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopScheduler() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    var nextDueDate: Date? {
        searches.compactMap(\.nextRunDate).min()
    }

    func scheduleBackgroundRefresh() {
        guard let next = nextDueDate else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = max(next, Date().addingTimeInterval(15 * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Background refresh: run due searches and wait for them, within the few seconds iOS allows.
    func handleBackgroundRefresh() async {
        runDueSearches()
        let deadline = Date().addingTimeInterval(25)
        while !running.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(500))
        }
        await downloads.saveState()
        scheduleBackgroundRefresh()
    }

    private func persistSearches() {
        try? searchStore.save(searches)
    }

    // MARK: Providers

    func setProviders(_ list: [ProviderDefinition]) {
        providers = list
        try? providerStore.save(list)
    }

    func upsert(_ provider: ProviderDefinition) {
        var list = providers
        if let index = list.firstIndex(where: { $0.id == provider.id }) {
            list[index] = provider
        } else {
            list.append(provider)
        }
        setProviders(list)
    }

    func importProviders(from data: Data) throws -> Int {
        let imported = try ProviderImport.providers(from: data)
        var list = providers
        for provider in imported {
            if let index = list.firstIndex(where: { $0.name == provider.name }) {
                var replaced = provider
                replaced.id = list[index].id
                list[index] = replaced
            } else {
                list.append(provider)
            }
        }
        setProviders(list)
        return imported.count
    }

    func restoreDefaultProviders() {
        var list = providers
        for provider in DefaultProviders.load() where !list.contains(where: { $0.id == provider.id }) {
            list.insert(provider, at: 0)
        }
        setProviders(list)
    }

    /// Opens a finished download's main file (TorrDroid opens it in a player when tapped).
    func openDownload(_ torrent: EngineTorrentStatus) {
        guard let url = downloads.mainFileURL(torrent), FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            toast = "File not yet created."
            return
        }
        openingFile = OpenableFile(url: url)
    }

    // MARK: Incoming links and files

    func open(_ url: URL) {
        Task {
            do {
                if url.scheme?.lowercased() == "magnet" {
                    try await downloads.add(link: url.absoluteString)
                    toast = "Torrent has been added to downloads."
                    tab = .downloads
                } else if url.isFileURL {
                    pendingTorrentFile = try copyIncoming(url)
                }
            } catch {
                toast = error.localizedDescription
            }
        }
    }

    /// A .torrent file waiting for the user to pick files (FileChooser).
    var pendingTorrentFile: URL?

    private func copyIncoming(_ url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let target = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".torrent")
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }
}

/// Settings live in UserDefaults; the proxy password goes to the keychain.
struct SettingsStore {
    private let key = "settings.v1"

    func load() -> AppSettings {
        guard let stored = UserDefaults.standard.data(forKey: key),
              let data = Self.fillingNewKeys(stored),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            let fresh = AppSettings()
            save(fresh)
            return fresh
        }
        settings.proxyPassword = Keychain.read("proxyPassword") ?? ""
        return settings
    }

    /// Settings saved by an older version lack newly added keys; take those from the defaults.
    private static func fillingNewKeys(_ stored: Data) -> Data? {
        guard let defaults = try? JSONEncoder().encode(AppSettings()),
              var merged = (try? JSONSerialization.jsonObject(with: defaults)) as? [String: Any],
              let saved = (try? JSONSerialization.jsonObject(with: stored)) as? [String: Any] else { return nil }
        merged.merge(saved) { _, saved in saved }
        return try? JSONSerialization.data(withJSONObject: merged)
    }

    func save(_ settings: AppSettings) {
        var stored = settings
        Keychain.write("proxyPassword", value: settings.proxyPassword)
        stored.proxyPassword = ""
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum Keychain {
    private static let service = "com.sarvesh.torrly"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
