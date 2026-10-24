import SwiftUI
import TorrlyCore
import TorrlyEngine

/// The DOWNLOADS tab.
struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var deleting: EngineTorrentStatus?

    var body: some View {
        let torrents = model.downloads.torrents.sorted { $0.addedDate > $1.addedDate }
        Group {
            if torrents.isEmpty {
                ContentUnavailableView("No downloads", systemImage: "arrow.down.circle",
                                       description: Text("Download a search result, or tap + to add a magnet link or .torrent file."))
            } else {
                List {
                    if model.downloads.waitingForWiFi {
                        Label("Waiting for Wi-fi. Downloads will resume when wi-fi is available.", systemImage: "wifi.exclamationmark")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    ForEach(torrents, id: \.infoHash) { torrent in
                        NavigationLink(value: torrent.infoHash) {
                            DownloadRow(torrent: torrent)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = torrent }
                        }
                        // The tab pager takes horizontal swipes, so row actions also live on long-press (as in TorrDroid).
                        .contextMenu {
                            if torrent.isComplete {
                                Button("Open", systemImage: "play") { model.openDownload(torrent) }
                                ShareLink(item: model.downloads.contentURL(torrent)) {
                                    Label("Share or open in another app", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button(torrent.isComplete ? (torrent.isPaused ? "Resume seeding" : "Stop seeding")
                                   : (torrent.isPaused ? "Resume" : "Pause"),
                                   systemImage: torrent.isPaused ? "arrow.down" : "pause") {
                                model.downloads.togglePause(torrent.infoHash)
                            }
                            if let magnet = model.downloads.magnetLink(torrent.infoHash) {
                                Button("Copy magnet link", systemImage: "link") { UIPasteboard.general.string = magnet }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                model.downloads.remove(torrent.infoHash, deleteFiles: false)
                            }
                            Button("Delete files with torrent", systemImage: "trash.fill", role: .destructive) {
                                model.downloads.remove(torrent.infoHash, deleteFiles: true)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.bottom, 80, for: .scrollContent)
            }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let hash = deleting?.infoHash { model.downloads.remove(hash, deleteFiles: false) }
            }
            Button("Delete files with torrent", role: .destructive) {
                if let hash = deleting?.infoHash { model.downloads.remove(hash, deleteFiles: true) }
            }
        }
    }
}

struct DownloadRow: View {
    @Environment(AppModel.self) private var model
    let torrent: EngineTorrentStatus

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(torrent.name)
                    .font(.headline)
                    .lineLimit(2)
                ProgressView(value: Double(torrent.progress))
                    .tint(torrent.state == .error ? .red : Theme.primary)
                Text(primaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(torrent.state == .error ? .red : .secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Button {
                if torrent.isComplete {
                    model.openDownload(torrent)
                } else {
                    model.downloads.togglePause(torrent.infoHash)
                }
            } label: {
                Image(systemName: torrent.isComplete ? "play.circle.fill"
                    : torrent.isPaused ? "arrow.down.circle.fill" : "pause.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(torrent.isComplete ? "Open" : torrent.isPaused ? "Resume" : "Pause")
        }
        .padding(.vertical, 6)
    }

    private var primaryLine: String {
        let done = Format.bytes(torrent.totalWantedDone)
        let total = torrent.hasMetadata ? Format.bytes(torrent.totalWanted) : "?"
        return "\(done) / \(total) • \(Int((torrent.progress * 100).rounded(.down)))%"
    }

    private var secondaryLine: String {
        torrent.statusLine
    }
}

extension EngineTorrentStatus {
    var isComplete: Bool { hasMetadata && progress >= 1 }

    var stateTitle: String {
        switch state {
        case .checkingFiles, .checkingResumeData: "Checking"
        case .downloadingMetadata: "Fetching metadata"
        case .downloading: "Downloading"
        case .finished: "Finished"
        case .seeding: "Seeding"
        case .paused: progress >= 1 ? "Completed" : "Paused"
        case .error: "Error"
        @unknown default: "Unknown"
        }
    }

    var statusLine: String {
        switch state {
        case .error:
            return errorMessage ?? "Error"
        case .downloading, .downloadingMetadata:
            let eta = Format.eta(remaining: totalWanted - totalWantedDone, rate: Int(downloadRate))
            return "↓ \(Format.speed(Int(downloadRate)))  ↑ \(Format.speed(Int(uploadRate)))  • \(eta) • \(connectedSeeds)/\(totalSeeds) seeds"
        case .seeding:
            return "Seeding • ↑ \(Format.speed(Int(uploadRate))) • \(connectedPeers) peers"
        default:
            return stateTitle
        }
    }
}
