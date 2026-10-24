import SwiftUI
import TorrlyCore
import TorrlyEngine

/// Torrent details: info, files, trackers and pieces (TorrDroid `TorrentDetailActivity`).
struct TorrentDetailView: View {
    enum Section: String, CaseIterable, Identifiable {
        case info = "Info", files = "Files", trackers = "Trackers", pieces = "Pieces"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let infoHash: String
    @State private var section = Section.info

    var body: some View {
        Group {
            if let torrent = model.downloads.torrent(infoHash) {
                VStack(spacing: 0) {
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    switch section {
                    case .info: InfoSection(torrent: torrent)
                    case .files: FilesSection(torrent: torrent)
                    case .trackers: TrackersSection(torrent: torrent)
                    case .pieces: PiecesSection(torrent: torrent)
                    }
                }
                .navigationTitle(torrent.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.downloads.togglePause(infoHash)
                        } label: {
                            Image(systemName: torrent.isPaused ? "play.fill" : "pause.fill").foregroundStyle(.white)
                        }
                        .accessibilityLabel(torrent.isPaused ? "Resume" : "Pause")
                    }
                }
            } else {
                ContentUnavailableView("Torrent removed", systemImage: "trash")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .greenNavigationBar()
    }
}

private struct InfoSection: View {
    @Environment(AppModel.self) private var model
    let torrent: EngineTorrentStatus
    @State private var limitsShown = false

    var body: some View {
        List {
            SwiftUI.Section {
                LabeledContent("Status", value: torrent.stateTitle)
                LabeledContent("Progress", value: "\(Int(torrent.progress * 100))%")
                LabeledContent("Size", value: torrent.hasMetadata ? Format.bytes(torrent.totalWanted) : "Fetching metadata")
                LabeledContent("Downloaded", value: Format.bytes(torrent.totalWantedDone))
                LabeledContent("Uploaded", value: Format.bytes(torrent.totalUploaded))
                LabeledContent("Ratio", value: ratio)
                LabeledContent("Download speed", value: Format.speed(Int(torrent.downloadRate)))
                LabeledContent("Upload speed", value: Format.speed(Int(torrent.uploadRate)))
                LabeledContent("Time left", value: Format.eta(remaining: torrent.totalWanted - torrent.totalWantedDone, rate: Int(torrent.downloadRate)))
                LabeledContent("Seeds", value: "\(torrent.connectedSeeds) (\(max(0, torrent.totalSeeds)))")
                LabeledContent("Peers", value: "\(torrent.connectedPeers) (\(max(0, torrent.totalPeers)))")
                if let error = torrent.errorMessage {
                    LabeledContent("Error") { Text(error).foregroundStyle(.red) }
                }
            }
            SwiftUI.Section {
                LabeledContent("Pieces", value: "\(torrent.numPieces) × \(Format.bytes(Int64(torrent.pieceLength)))")
                LabeledContent("Added", value: torrent.addedDate.formatted(date: .abbreviated, time: .shortened))
                if let completed = torrent.completedDate {
                    LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
                }
                if let source = model.downloads.meta(for: torrent.infoHash)?.source {
                    LabeledContent("Source", value: source)
                }
                LabeledContent("Hash") {
                    Text(torrent.infoHash).font(.caption.monospaced()).textSelection(.enabled)
                }
                LabeledContent("Saved in", value: "Files › On My iPhone › Torrly › Downloads")
            }
            SwiftUI.Section {
                if torrent.isComplete {
                    Button("Play / open", systemImage: "play.fill") { model.openDownload(torrent) }
                    ShareLink(item: model.downloads.contentURL(torrent)) {
                        Label("Share or open in another app", systemImage: "square.and.arrow.up")
                    }
                }
                if let magnet = model.downloads.magnetLink(torrent.infoHash) {
                    Button("Copy magnet link", systemImage: "link") {
                        UIPasteboard.general.string = magnet
                        model.toast = "Magnet link copied"
                    }
                }
                Button("Update trackers and DHT", systemImage: "arrow.clockwise") { model.downloads.reannounce(torrent.infoHash) }
                Button("Verify downloaded data", systemImage: "checkmark.shield") {
                    model.downloads.recheck(torrent.infoHash)
                    model.toast = "Please wait while verifying downloaded data."
                }
                Button("Speed limits", systemImage: "speedometer") { limitsShown = true }
            }
        }
        .sheet(isPresented: $limitsShown) { SpeedLimitSheet(torrent: torrent) }
    }

    private var ratio: String {
        guard torrent.totalDownloaded > 0 else { return "0.00" }
        return String(format: "%.2f", Double(torrent.totalUploaded) / Double(torrent.totalDownloaded))
    }
}

private struct SpeedLimitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let torrent: EngineTorrentStatus
    @State private var download = ""
    @State private var upload = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Download limit (KB/s, 0 = none)", text: $download).keyboardType(.numberPad)
                TextField("Upload limit (KB/s, 0 = none)", text: $upload).keyboardType(.numberPad)
            }
            .navigationTitle("Speed limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.downloads.setLimits(download: Int(download) ?? 0, upload: Int(upload) ?? 0, for: torrent.infoHash)
                        dismiss()
                    }
                }
            }
            .onAppear {
                download = torrent.downloadLimit > 0 ? String(torrent.downloadLimit / 1024) : ""
                upload = torrent.uploadLimit > 0 ? String(torrent.uploadLimit / 1024) : ""
            }
        }
        .presentationDetents([.medium])
    }
}

private struct FilesSection: View {
    @Environment(AppModel.self) private var model
    let torrent: EngineTorrentStatus
    @State private var files: [EngineFile] = []

    var body: some View {
        List {
            if !torrent.hasMetadata {
                Text("The file list appears once metadata has been fetched from peers.").foregroundStyle(.secondary)
            }
            SwiftUI.Section(files.isEmpty ? "" : "Files to download") {
                ForEach(files, id: \.index) { file in
                    HStack(spacing: 12) {
                        Button {
                            toggle(file)
                        } label: {
                            Image(systemName: file.priority > 0 ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(file.priority > 0 ? Theme.primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(file.priority > 0 ? "Skip file" : "Download file")
                        VStack(alignment: .leading, spacing: 4) {
                            Text((file.path as NSString).lastPathComponent).lineLimit(2)
                                .foregroundStyle(file.size > 0 && file.downloaded >= file.size ? Theme.primary : .primary)
                            ProgressView(value: file.size > 0 ? Double(file.downloaded) / Double(file.size) : 0).tint(Theme.primary)
                            Text("\(Format.bytes(file.downloaded)) / \(Format.bytes(file.size)) • Priority : \(file.priority > 0 ? "Normal" : "Skip")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // A finished file opens in the player or Quick Look.
                            guard file.size > 0, file.downloaded >= file.size else { return }
                            model.openingFile = OpenableFile(url: model.downloads.fileURL(torrent, file))
                        }
                    }
                }
            }
        }
        .task(id: torrent.totalWantedDone) { files = model.downloads.files(torrent.infoHash) }
    }

    private func toggle(_ file: EngineFile) {
        var priorities = files.map { Int($0.priority) }
        guard let index = files.firstIndex(where: { $0.index == file.index }) else { return }
        priorities[index] = file.priority > 0 ? 0 : 4
        // Priorities are indexed by libtorrent file index; pad files are skipped in `files`.
        var byIndex = [Int](repeating: 4, count: (files.map { Int($0.index) }.max() ?? 0) + 1)
        for (offset, entry) in files.enumerated() { byIndex[Int(entry.index)] = priorities[offset] }
        model.downloads.setPriorities(byIndex, for: torrent.infoHash)
        files = model.downloads.files(torrent.infoHash)
    }
}

private struct TrackersSection: View {
    @Environment(AppModel.self) private var model
    let torrent: EngineTorrentStatus
    @State private var trackers: [EngineTracker] = []
    @State private var adding = false
    @State private var newTracker = ""

    var body: some View {
        List {
            ForEach(trackers, id: \.url) { tracker in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tracker.url).font(.callout).lineLimit(2)
                    HStack {
                        Text(tracker.updating ? "Updating…" : tracker.working ? "Working" : (tracker.message.isEmpty ? "Not contacted" : tracker.message))
                            .foregroundStyle(tracker.working ? Theme.primary : .secondary)
                        Spacer()
                        if tracker.seeds >= 0 { Text("S \(tracker.seeds)  L \(max(0, tracker.peers))") }
                    }
                    .font(.caption)
                }
            }
            .onDelete { offsets in
                let remaining = trackers.enumerated().filter { !offsets.contains($0.offset) }.map(\.element.url)
                model.downloads.replaceTrackers(remaining, of: torrent.infoHash)
                trackers = model.downloads.trackers(torrent.infoHash)
            }
        }
        .overlay {
            if trackers.isEmpty { ContentUnavailableView("No trackers", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Add tracker", systemImage: "plus") { adding = true }
            }
        }
        .alert("Add tracker", isPresented: $adding) {
            TextField("udp://tracker.example:1337/announce", text: $newTracker)
                .textInputAutocapitalization(.never)
            Button("Add") {
                model.downloads.addTracker(newTracker, to: torrent.infoHash)
                newTracker = ""
                trackers = model.downloads.trackers(torrent.infoHash)
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            while !Task.isCancelled {
                trackers = model.downloads.trackers(torrent.infoHash)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

private struct PiecesSection: View {
    @Environment(AppModel.self) private var model
    let torrent: EngineTorrentStatus
    @State private var pieces: [Bool] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(pieces.filter { $0 }.count) of \(pieces.count) pieces")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                PiecesGrid(pieces: pieces)
            }
            .padding()
        }
        .task(id: torrent.totalWantedDone) { pieces = model.downloads.pieces(torrent.infoHash) }
    }
}

/// A square per piece, green when downloaded (TorrDroid `PiecesView`).
struct PiecesGrid: View {
    let pieces: [Bool]

    var body: some View {
        Canvas { context, size in
            guard !pieces.isEmpty else { return }
            let cell = max(3, min(14, floor(sqrt(size.width * 600 / Double(pieces.count)))))
            let columns = max(1, Int(size.width / cell))
            for (index, done) in pieces.enumerated() {
                let rect = CGRect(x: Double(index % columns) * cell, y: Double(index / columns) * cell, width: cell - 1, height: cell - 1)
                context.fill(Path(rect), with: .color(done ? Theme.primary : Color(.systemGray5)))
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(pieces.filter { $0 }.count) of \(pieces.count) pieces downloaded")
    }

    private var height: CGFloat {
        guard !pieces.isEmpty else { return 0 }
        let width = 360.0
        let cell = max(3, min(14, floor(sqrt(width * 600 / Double(pieces.count)))))
        return ceil(Double(pieces.count) / floor(width / cell)) * cell
    }
}
