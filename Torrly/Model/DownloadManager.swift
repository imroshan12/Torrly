import Foundation
import Network
import Observation
import TorrlyCore
import TorrlyEngine

/// Extra facts about a download that libtorrent does not keep.
struct DownloadMeta: Codable {
    var source: String?
    var addedBySearch: Bool
    var addedAt: Date
}

enum AddTorrentError: LocalizedError {
    case invalidLink
    case duplicate
    case downloadFailed(String)
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .invalidLink: "Invalid link, please re-enter"
        case .duplicate: "The torrent already exists"
        case let .downloadFailed(detail): "Couldn't download the torrent file: \(detail)"
        case let .engine(detail): detail
        }
    }
}

/// Owns the libtorrent session and publishes torrent state to the UI (TorrDroid `DownloadService`, REPORT.md §3).
@Observable
@MainActor
final class DownloadManager: NSObject {
    private(set) var torrents: [EngineTorrentStatus] = []
    private(set) var waitingForWiFi = false
    var lastError: String?

    @ObservationIgnored private let session: EngineSession
    @ObservationIgnored private var meta: [String: DownloadMeta]
    @ObservationIgnored private let metaStore: JSONFileStore<[String: DownloadMeta]>
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var settings: AppSettings
    @ObservationIgnored private var onCellular = false
    @ObservationIgnored private var finishedHashes: Set<String> = []
    @ObservationIgnored private let launchDate = Date()
    @ObservationIgnored var notifier: Notifier?

    let downloadDirectory: URL
    let torrentFileDirectory: URL

    init(settings: AppSettings) {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        downloadDirectory = documents.appending(path: "Downloads", directoryHint: .isDirectory)
        torrentFileDirectory = support.appending(path: "TorrentFiles", directoryHint: .isDirectory)
        let engineState = support.appending(path: "Engine", directoryHint: .isDirectory)
        for dir in [downloadDirectory, torrentFileDirectory, engineState] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        metaStore = JSONFileStore(url: support.appending(path: "downloads.json"))
        meta = metaStore.load() ?? [:]
        self.settings = settings
        session = EngineSession(settings: settings.engineSettings, stateDirectory: engineState.path(percentEncoded: false))
        super.init()
        session.delegate = self
        session.restoreTorrents(withSavePath: downloadDirectory.path(percentEncoded: false))
        startPathMonitor()
    }

    static var engineVersion: String { EngineSession.libtorrentVersion() }

    func apply(_ newSettings: AppSettings) {
        let wifiChanged = newSettings.wifiOnly != settings.wifiOnly
        settings = newSettings
        session.apply(newSettings.engineSettings)
        if wifiChanged { updateWiFiPause() }
    }

    func meta(for hash: String) -> DownloadMeta? { meta[hash] }

    func torrent(_ hash: String) -> EngineTorrentStatus? { torrents.first { $0.infoHash == hash } }

    func contains(infoHash: String?) -> Bool {
        guard let infoHash = infoHash?.lowercased() else { return false }
        return torrents.contains { $0.infoHash == infoHash } || meta[infoHash] != nil
    }

    // MARK: Adding

    /// Adds a search result: magnets directly, .torrent URLs after downloading the file.
    @discardableResult
    func add(result: SearchResult, bySearch: Bool) async throws -> String {
        if contains(infoHash: result.infoHash) { throw AddTorrentError.duplicate }
        let hash = try await add(link: result.downloadURL, source: result.source, bySearch: bySearch)
        return hash
    }

    /// Adds a magnet or http(s) link to a .torrent file.
    @discardableResult
    func add(link: String, source: String? = nil, bySearch: Bool = false) async throws -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("magnet:") {
            if let hash = EngineSession.infoHash(ofMagnet: trimmed), contains(infoHash: hash) { throw AddTorrentError.duplicate }
            do {
                let hash = try session.addMagnet(trimmed, savePath: downloadDirectory.path(percentEncoded: false))
                remember(hash, source: source, bySearch: bySearch)
                return hash
            } catch {
                throw AddTorrentError.invalidLink
            }
        }
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw AddTorrentError.invalidLink
        }
        let file = try await downloadTorrentFile(from: url)
        return try add(torrentFile: file, priorities: nil, source: source ?? url.host(), bySearch: bySearch)
    }

    /// Adds a local .torrent file; `priorities` comes from the file chooser (nil = everything).
    @discardableResult
    func add(torrentFile: URL, priorities: [Int]?, source: String? = nil, bySearch: Bool = false) throws -> String {
        let info = try readTorrent(torrentFile)
        if contains(infoHash: info.infoHash) { throw AddTorrentError.duplicate }
        let stored = torrentFileDirectory.appending(path: info.infoHash + ".torrent")
        if torrentFile.standardizedFileURL != stored.standardizedFileURL {
            try? FileManager.default.removeItem(at: stored)
            try FileManager.default.copyItem(at: torrentFile, to: stored)
        }
        do {
            let hash = try session.addTorrentFile(stored.path(percentEncoded: false),
                                                  savePath: downloadDirectory.path(percentEncoded: false),
                                                  filePriorities: priorities?.map { NSNumber(value: $0) })
            remember(hash, source: source, bySearch: bySearch)
            return hash
        } catch {
            throw AddTorrentError.engine(error.localizedDescription)
        }
    }

    func readTorrent(_ file: URL) throws -> EngineTorrentInfo {
        do {
            return try EngineSession.readTorrentFile(file.path(percentEncoded: false))
        } catch {
            throw AddTorrentError.engine("Invalid torrent, please try another")
        }
    }

    func downloadTorrentFile(from url: URL) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0", forHTTPHeaderField: "User-Agent")
        do {
            let (temp, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                throw AddTorrentError.downloadFailed("HTTP \(http.statusCode)")
            }
            let target = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".torrent")
            try FileManager.default.moveItem(at: temp, to: target)
            return target
        } catch let error as AddTorrentError {
            throw error
        } catch {
            throw AddTorrentError.downloadFailed(error.localizedDescription)
        }
    }

    private func remember(_ hash: String, source: String?, bySearch: Bool) {
        meta[hash] = DownloadMeta(source: source, addedBySearch: bySearch, addedAt: Date())
        try? metaStore.save(meta)
        torrents = session.allStatuses()
    }

    // MARK: Control

    func pause(_ hash: String) { session.pauseTorrent(hash); refresh() }
    func resume(_ hash: String) { session.resumeTorrent(hash); refresh() }
    func pauseAll() { session.pauseAll(); refresh() }
    func resumeAll() { session.resumeAll(); refresh() }

    func togglePause(_ hash: String) {
        guard let t = torrent(hash) else { return }
        t.isPaused ? resume(hash) : pause(hash)
    }

    func remove(_ hash: String, deleteFiles: Bool) {
        session.removeTorrent(hash, deleteFiles: deleteFiles)
        meta[hash] = nil
        try? metaStore.save(meta)
        try? FileManager.default.removeItem(at: torrentFileDirectory.appending(path: hash + ".torrent"))
        torrents.removeAll { $0.infoHash == hash }
    }

    func files(_ hash: String) -> [EngineFile] { session.files(of: hash) }
    func setPriorities(_ priorities: [Int], for hash: String) {
        session.setFilePriorities(priorities.map { NSNumber(value: $0) }, forTorrent: hash)
    }

    func pieces(_ hash: String) -> [Bool] { session.pieces(of: hash).map { $0 != 0 } }
    func trackers(_ hash: String) -> [EngineTracker] { session.trackers(of: hash) }
    func addTracker(_ url: String, to hash: String) { session.addTracker(url, toTorrent: hash) }
    func replaceTrackers(_ urls: [String], of hash: String) { session.replaceTrackers(urls, ofTorrent: hash) }
    func magnetLink(_ hash: String) -> String? { session.magnetLink(of: hash) }
    func reannounce(_ hash: String) { session.forceReannounce(hash); session.forceDHTAnnounce(hash) }
    func recheck(_ hash: String) { session.forceRecheck(hash) }
    func setLimits(download: Int, upload: Int, for hash: String) {
        session.setDownloadLimit(Int32(download * 1024), uploadLimit: Int32(upload * 1024), forTorrent: hash)
    }

    /// Location of a torrent's content on disk.
    func contentURL(_ status: EngineTorrentStatus) -> URL {
        URL(filePath: status.savePath, directoryHint: .isDirectory).appending(path: status.name)
    }

    func fileURL(_ status: EngineTorrentStatus, _ file: EngineFile) -> URL {
        URL(filePath: status.savePath, directoryHint: .isDirectory).appending(path: file.path)
    }

    /// The largest selected file: the movie in a movie torrent, the archive in a software one.
    func mainFileURL(_ status: EngineTorrentStatus) -> URL? {
        let chosen = files(status.infoHash).filter { $0.priority > 0 }
        return chosen.max { $0.size < $1.size }.map { fileURL(status, $0) }
    }

    func refresh() {
        torrents = session.allStatuses()
    }

    func saveState() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.saveState { continuation.resume() }
        }
    }

    // MARK: Wi-Fi only

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
            Task { @MainActor in
                self?.onCellular = cellular
                self?.updateWiFiPause()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "torrly.path-monitor"))
    }

    private func updateWiFiPause() {
        let shouldPause = settings.wifiOnly && onCellular
        guard shouldPause != waitingForWiFi else { return }
        waitingForWiFi = shouldPause
        if shouldPause {
            session.pauseSession()
            notifier?.waitingForWiFi()
        } else {
            session.resumeSession()
        }
    }
}

extension DownloadManager: EngineSessionDelegate {
    nonisolated func session(_ session: EngineSession, didUpdateTorrents torrents: [EngineTorrentStatus]) {
        MainActor.assumeIsolated {
            self.torrents = torrents
        }
    }

    nonisolated func session(_ session: EngineSession, torrentDidFinish infoHash: String) {
        MainActor.assumeIsolated {
            guard !finishedHashes.contains(infoHash) else { return }
            finishedHashes.insert(infoHash)
            // Torrents restored at launch that were already complete also report "finished"; skip those.
            if Date().timeIntervalSince(launchDate) > 10 {
                notifier?.downloadComplete(name: torrent(infoHash)?.name ?? infoHash)
            }
            if !settings.seeding { session.pauseTorrent(infoHash) }
        }
    }

    nonisolated func session(_ session: EngineSession, torrentDidReceiveMetadata infoHash: String) {}

    nonisolated func session(_ session: EngineSession, torrent infoHash: String?, didFailWithMessage message: String) {
        MainActor.assumeIsolated {
            lastError = message
        }
    }

    nonisolated func session(_ session: EngineSession, torrentWasRemoved infoHash: String) {
        MainActor.assumeIsolated {
            torrents.removeAll { $0.infoHash == infoHash }
        }
    }
}
