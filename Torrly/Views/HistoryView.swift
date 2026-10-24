import SwiftUI
import TorrlyCore

/// The HISTORY tab: one card per saved search with its results (TorrDroid's history page).
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SearchItem?

    var body: some View {
        Group {
            if model.searches.isEmpty {
                ContentUnavailableView("No searches yet", systemImage: "magnifyingglass",
                                       description: Text("Searches you run appear here with their results."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(model.searches) { item in
                                SearchCard(item: item, onEdit: { editing = item })
                                    .id(item.id)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 80)
                    }
                    .onChange(of: model.focusedSearch) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                        model.focusedSearch = nil
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $editing) { item in EditSearchSheet(item: item) }
    }
}

struct SearchCard: View {
    @Environment(AppModel.self) private var model
    let item: SearchItem
    let onEdit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.keyword)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button {
                    model.run(item.id)
                } label: {
                    Image(systemName: "magnifyingglass").font(.title3.weight(.semibold)).foregroundStyle(.white)
                }
                .disabled(item.status == .searching)
                .accessibilityLabel("Search again")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.cardHeader)

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 24) {
                Text("Attempts : \(item.attempts)")
                    .font(.headline)
                    .foregroundStyle(Theme.primary)
                if let next = item.nextRunDate, item.lastRun != nil {
                    Text("Next \(next, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .accessibilityLabel("Edit search")
                Button { confirmDelete = true } label: { Image(systemName: "trash.fill") }
                    .accessibilityLabel("Delete search")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .confirmationDialog("Delete this search?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteSearch(item.id) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch (item.status, item.outcome) {
        case (.searching, _):
            HStack(spacing: 12) {
                ProgressView()
                Text(item.foundSoFar > 0 ? "In Progress • \(item.foundSoFar) found" : "In Progress")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        case (.queued, _):
            Text("Queued").foregroundStyle(.secondary).padding(16)
        case let (_, .results(results)):
            VStack(spacing: 0) {
                ForEach(results) { result in
                    ResultRow(result: result)
                    if result != results.last { Divider().padding(.leading, 16) }
                }
            }
        case let (_, .downloadStarted(title)):
            Label("Download was started: \(title)", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Theme.primary)
                .padding(16)
        case let (_, .failed(reason)):
            Text(reason.message).foregroundStyle(.secondary).padding(16)
        case (.idle, nil):
            Text("Queued").foregroundStyle(.secondary).padding(16)
        }
    }
}

struct ResultRow: View {
    @Environment(AppModel.self) private var model
    let result: SearchResult
    @State private var adding = false

    private var alreadyAdded: Bool { model.downloads.contains(infoHash: result.infoHash) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let seeds = result.seeds {
                        Label("\(seeds)", systemImage: "arrow.up").foregroundStyle(.green)
                    }
                    if let leechers = result.leechers {
                        Label("\(leechers)", systemImage: "arrow.down").foregroundStyle(.orange)
                    }
                    Text(result.source).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.caption)
                .labelStyle(CompactLabelStyle())
            }
            Spacer(minLength: 8)
            Text(result.size > 0 ? Format.bytes(result.size) : "—")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button {
                Task { await add() }
            } label: {
                if adding {
                    ProgressView()
                } else {
                    Image(systemName: alreadyAdded ? "checkmark" : "arrow.down.to.line")
                        .font(.title3)
                        .foregroundStyle(alreadyAdded ? Theme.primary : .secondary)
                }
            }
            .frame(width: 32)
            .disabled(adding || alreadyAdded)
            .accessibilityLabel(alreadyAdded ? "Added" : "Download")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contextMenu {
            Button("Copy link", systemImage: "doc.on.doc") { UIPasteboard.general.string = result.downloadURL }
            if let url = URL(string: "https://www.google.com/search?q=" + (result.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                Link(destination: url) { Label("Search on the web", systemImage: "safari") }
            }
        }
    }

    private func add() async {
        adding = true
        defer { adding = false }
        do {
            try await model.downloads.add(result: result, bySearch: false)
            model.toast = "Torrent has been added to downloads."
        } catch {
            model.toast = error.localizedDescription
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

struct EditSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: SearchItem
    @State private var keyword = ""
    @State private var interval = RetryInterval.never
    @State private var type: ContentType?
    @State private var autoDownload = false
    @State private var maxSize = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                SearchFields(keyword: $keyword, interval: $interval, type: $type, autoDownload: $autoDownload, maxSize: $maxSize)
                    .padding(20)
            }
            .navigationTitle("Edit search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & search") { save() }
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || type == nil)
                }
            }
        }
        .onAppear {
            keyword = item.keyword
            interval = item.retryInterval
            type = item.contentType
            autoDownload = item.autoDownload
            maxSize = item.maxSizeMB > 0 ? String(item.maxSizeMB) : ""
        }
    }

    private func save() {
        guard let type else { return }
        var edited = item
        edited.keyword = keyword.trimmingCharacters(in: .whitespaces)
        edited.retryInterval = interval
        edited.contentType = type
        edited.autoDownload = autoDownload
        edited.maxSizeMB = Int(maxSize) ?? 0
        model.update(edited)
        model.toast = "The field was updated"
        dismiss()
    }
}
