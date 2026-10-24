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
                EmptyState(systemImage: "arrow.down.circle", title: "No downloads yet",
                           message: "Download a search result, or tap + to add a magnet link or a .torrent file.")
            } else {
                List {
                    Section {
                        SpeedSummary(torrents: torrents, waitingForWiFi: model.downloads.waitingForWiFi)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(torrents, id: \.infoHash) { torrent in
                        DownloadRow(torrent: torrent)
                            // Hidden link: keeps the whole card tappable without a list chevron.
                            .background(NavigationLink(value: torrent.infoHash) { EmptyView() }.opacity(0))
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = torrent }
                            }
                            // The tab pager takes horizontal swipes, so row actions also live on long-press (as in TorrDroid).
                            .contextMenu { menu(for: torrent) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 90, for: .scrollContent)
            }
        }
        .background(Theme.screenBackground)
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

    @ViewBuilder
    private func menu(for torrent: EngineTorrentStatus) -> some View {
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

/// Totals across all torrents, plus the Wi-Fi-only notice.
private struct SpeedSummary: View {
    let torrents: [EngineTorrentStatus]
    let waitingForWiFi: Bool

    var body: some View {
        let down = torrents.reduce(0) { $0 + Int($1.downloadRate) }
        let up = torrents.reduce(0) { $0 + Int($1.uploadRate) }
        let active = torrents.filter { !$0.isPaused && !$0.isComplete }.count
        let done = torrents.filter(\.isComplete).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                metric("arrow.down", Format.speed(down), "Download", Theme.primary)
                Divider().frame(height: 34)
                metric("arrow.up", Format.speed(up), "Upload", .teal)
                Divider().frame(height: 34)
                metric("bolt.horizontal", "\(active) / \(done)", "Active / done", .orange)
            }
            if waitingForWiFi {
                Label("Waiting for Wi-Fi. Downloads resume when Wi-Fi is available.", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .card()
    }

    private func metric(_ symbol: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Label(caption, systemImage: symbol)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .labelStyle(CompactLabelStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

struct DownloadRow: View {
    @Environment(AppModel.self) private var model
    let torrent: EngineTorrentStatus

    var body: some View {
        let tint = Theme.color(for: torrent)
        HStack(alignment: .center, spacing: 12) {
            IconTile(systemImage: FileIcon.symbol(for: torrent.name), tint: tint, size: 46)
            VStack(alignment: .leading, spacing: 7) {
                Text(torrent.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                ProgressBar(value: Double(torrent.progress), tint: tint)
                HStack(spacing: 6) {
                    StatusBadge(text: torrent.stateTitle, tint: tint)
                    Text(primaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                if let detail = detailLine {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(torrent.state == .error ? .red : .secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Button {
                if torrent.isComplete {
                    model.openDownload(torrent)
                } else {
                    model.downloads.togglePause(torrent.infoHash)
                }
            } label: {
                Image(systemName: torrent.isComplete ? "play.fill" : torrent.isPaused ? "arrow.down" : "pause.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(torrent.isComplete ? .white : tint)
                    .frame(width: 40, height: 40)
                    .background(torrent.isComplete ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(tint.opacity(0.14)), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(torrent.isComplete ? "Open" : torrent.isPaused ? "Resume" : "Pause")
        }
        .padding(14)
        .card()
    }

    private var primaryLine: String {
        let done = Format.bytes(torrent.totalWantedDone)
        let total = torrent.hasMetadata ? Format.bytes(torrent.totalWanted) : "?"
        return "\(Int((torrent.progress * 100).rounded(.down)))% · \(done) of \(total)"
    }

    private var detailLine: String? {
        switch torrent.state {
        case .error:
            return torrent.errorMessage ?? "Error"
        case .downloading, .downloadingMetadata:
            let eta = Format.eta(remaining: torrent.totalWanted - torrent.totalWantedDone, rate: Int(torrent.downloadRate))
            return "↓ \(Format.speed(Int(torrent.downloadRate)))  ↑ \(Format.speed(Int(torrent.uploadRate)))  · \(eta) left · \(torrent.connectedSeeds) seeds"
        case .seeding:
            return "↑ \(Format.speed(Int(torrent.uploadRate))) · \(torrent.connectedPeers) peers"
        default:
            return nil
        }
    }
}

extension EngineTorrentStatus {
    var isComplete: Bool { hasMetadata && progress >= 1 }

    var stateTitle: String {
        switch state {
        case .checkingFiles, .checkingResumeData: "Checking"
        case .downloadingMetadata: "Metadata"
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
