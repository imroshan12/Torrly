import CryptoKit
import Foundation
import Testing
import TorrlyCore
import TorrlyEngine
@testable import Torrly

/// Exercises the libtorrent bridge itself (no network needed: torrents are added but never complete).
@MainActor
struct EngineTests {
    let stateDir: URL
    let saveDir: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "engine-tests-\(UUID().uuidString)")
        stateDir = root.appending(path: "state")
        saveDir = root.appending(path: "downloads")
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
    }

    func makeSession() -> EngineSession {
        var settings = AppSettings()
        settings.randomizePort = false
        settings.port = 0
        return EngineSession(settings: settings.engineSettings, stateDirectory: stateDir.path(percentEncoded: false))
    }

    @Test func reportsLibtorrentVersion() {
        #expect(EngineSession.libtorrentVersion().hasPrefix("2.0."))
    }

    @Test func addsPausesResumesAndRemovesAMagnet() async throws {
        let session = makeSession()
        let hash = String(repeating: "ab", count: 20)
        let magnet = Magnet.link(infoHash: hash, name: "Test torrent", trackers: [])
        #expect(EngineSession.infoHash(ofMagnet: magnet) == hash)

        let added = try session.addMagnet(magnet, savePath: saveDir.path(percentEncoded: false))
        #expect(added == hash)
        let status = try await waitFor { session.status(of: hash) }
        #expect(status.name == "Test torrent")
        #expect(!status.hasMetadata)

        session.pauseTorrent(hash)
        _ = try await waitFor { session.status(of: hash)?.isPaused == true ? true : nil }
        session.resumeTorrent(hash)
        _ = try await waitFor { session.status(of: hash)?.isPaused == false ? true : nil }

        // Adding the same magnet again does not create a second torrent.
        _ = try session.addMagnet(magnet, savePath: saveDir.path(percentEncoded: false))
        #expect(session.allStatuses().count == 1)

        session.removeTorrent(hash, deleteFiles: true)
        _ = try await waitFor { session.allStatuses().isEmpty ? true : nil }
        session.shutdown()
    }

    @Test func rejectsInvalidMagnet() {
        let session = makeSession()
        #expect(throws: (any Error).self) {
            try session.addMagnet("magnet:?xt=urn:nothing", savePath: saveDir.path(percentEncoded: false))
        }
        #expect(EngineSession.infoHash(ofMagnet: "not a magnet") == nil)
        session.shutdown()
    }

    @Test func readsAndAddsTorrentFile() async throws {
        let file = try TorrentFixture.write(to: stateDir.appending(path: "fixture.torrent"))
        let info = try EngineSession.readTorrentFile(file.path(percentEncoded: false))
        #expect(info.name == "hello.txt")
        #expect(info.totalSize == Int64(TorrentFixture.content.count))
        #expect(info.files.count == 1)
        #expect(info.trackers == ["udp://tracker.example:1337/announce"])
        #expect(info.infoHash == TorrentFixture.infoHash)

        let session = makeSession()
        let hash = try session.addTorrentFile(file.path(percentEncoded: false), savePath: saveDir.path(percentEncoded: false),
                                              filePriorities: [NSNumber(value: 4)])
        #expect(hash == info.infoHash)
        let status = try await waitFor { session.status(of: hash) }
        #expect(status.hasMetadata)
        #expect(status.totalWanted == Int64(TorrentFixture.content.count))
        #expect(session.files(of: hash).first?.path == "hello.txt")
        #expect(session.trackers(of: hash).map(\.url) == ["udp://tracker.example:1337/announce"])
        #expect(session.magnetLink(of: hash)?.contains(hash) == true)
        session.addTracker("udp://second.example:80/announce", toTorrent: hash)
        #expect(session.trackers(of: hash).count == 2)
        session.shutdown()
    }

    @Test func restoresTorrentsFromResumeData() async throws {
        let first = makeSession()
        let hash = String(repeating: "cd", count: 20)
        _ = try first.addMagnet(Magnet.link(infoHash: hash, name: "Persisted", trackers: []), savePath: saveDir.path(percentEncoded: false))
        _ = try await waitFor { first.status(of: hash) }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in first.saveState { done.resume() } }
        first.shutdown()

        let second = makeSession()
        second.restoreTorrents(withSavePath: saveDir.path(percentEncoded: false))
        let restored = try await waitFor { second.status(of: hash) }
        #expect(restored.name == "Persisted")
        second.shutdown()
    }

    /// iOS can move the app container between launches; saved torrents must follow the new Downloads folder.
    @Test func restoresIntoCurrentFolderWhenSavedOneIsOutsideTheContainer() async throws {
        let oldContainerFolder = "/nonexistent-old-container/Documents/Downloads"
        let newFolder = saveDir.appending(path: "new-container")
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        let first = makeSession()
        let hash = String(repeating: "ef", count: 20)
        _ = try first.addMagnet(Magnet.link(infoHash: hash, name: "Moved", trackers: []), savePath: oldContainerFolder)
        _ = try await waitFor { first.status(of: hash) }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in first.saveState { done.resume() } }
        first.shutdown()

        let second = makeSession()
        second.restoreTorrents(withSavePath: newFolder.path(percentEncoded: false))
        let restored = try await waitFor { second.status(of: hash) }
        let trimmed = { (path: String) in path.hasSuffix("/") ? String(path.dropLast()) : path }
        #expect(trimmed(restored.savePath) == trimmed(newFolder.path(percentEncoded: false)))
        second.shutdown()
    }

    /// A folder inside the current container is kept as saved.
    @Test func keepsSavedFolderInsideTheContainer() async throws {
        let custom = saveDir.appending(path: "custom")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let first = makeSession()
        let hash = String(repeating: "12", count: 20)
        _ = try first.addMagnet(Magnet.link(infoHash: hash, name: "Kept", trackers: []), savePath: custom.path(percentEncoded: false))
        _ = try await waitFor { first.status(of: hash) }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in first.saveState { done.resume() } }
        first.shutdown()

        let second = makeSession()
        second.restoreTorrents(withSavePath: saveDir.path(percentEncoded: false))
        let restored = try await waitFor { second.status(of: hash) }
        #expect(restored.savePath.contains("/custom"))
        second.shutdown()
    }

    @Test func settingsMapToEngine() {
        var settings = AppSettings()
        settings.maxDownloadKBps = 100
        settings.encryption = .require
        settings.encryptIncoming = false
        settings.proxyType = .socks5
        settings.proxyNeedsAuth = false
        settings.proxyUsername = "ignored"
        let engine = settings.engineSettings
        #expect(engine.maxDownloadRate == 102_400)
        #expect(engine.outgoingEncryption == .forced)
        #expect(engine.incomingEncryption == .disabled)
        #expect(engine.proxyType == .socks5)
        #expect(engine.proxyUsername == "")
        #expect((37000 ... 57000).contains(AppSettings().randomPort))
    }

    private func waitFor<T>(timeout: Duration = .seconds(10), _ probe: () -> T?) async throws -> T {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let value = probe() { return value }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CancellationError()
    }
}

/// Builds a minimal single-file .torrent in bencode.
enum TorrentFixture {
    static let content = Data("hello torrly\n".utf8)
    static let pieceLength = 16384

    static var infoDict: Data {
        var d = Data("d".utf8)
        d += bstr("length") + Data("i\(content.count)e".utf8)
        d += bstr("name") + bstr("hello.txt")
        d += bstr("piece length") + Data("i\(pieceLength)e".utf8)
        d += bstr("pieces") + bbytes(sha1(content))
        d += Data("e".utf8)
        return d
    }

    static var infoHash: String { sha1(infoDict).map { String(format: "%02x", $0) }.joined() }

    static func write(to url: URL) throws -> URL {
        var d = Data("d".utf8)
        d += bstr("announce") + bstr("udp://tracker.example:1337/announce")
        d += bstr("info") + infoDict
        d += Data("e".utf8)
        try d.write(to: url)
        return url
    }

    private static func bstr(_ s: String) -> Data { bbytes(Data(s.utf8)) }
    private static func bbytes(_ b: Data) -> Data { Data("\(b.count):".utf8) + b }

    private static func sha1(_ data: Data) -> Data { Data(Insecure.SHA1.hash(data: data)) }
}
