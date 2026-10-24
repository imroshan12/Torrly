import SwiftUI
import TorrlyCore

/// The HISTORY tab: one card per saved search with its results (TorrDroid's history page).
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SearchItem?

    var body: some View {
        Group {
            if model.searches.isEmpty {
                EmptyState(systemImage: "clock.arrow.circlepath", title: "No searches yet",
                           message: "Searches you run show up here with their best results.",
                           actionTitle: "Start a search") { withAnimation(.snappy) { model.tab = .search } }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(model.searches) { item in
                                SearchCard(item: item, onEdit: { editing = item })
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                    .onChange(of: model.focusedSearch) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                        model.focusedSearch = nil
                    }
                }
            }
        }
        .background(Theme.screenBackground)
        .sheet(item: $editing) { item in EditSearchSheet(item: item) }
    }
}

struct SearchCard: View {
    @Environment(AppModel.self) private var model
    let item: SearchItem
    let onEdit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconTile(systemImage: item.contentType.symbol)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.keyword)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    model.run(item.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(item.status == .searching)
                .accessibilityLabel("Search again")
                Menu {
                    Button("Search again", systemImage: "arrow.clockwise") { model.run(item.id) }
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More")
            }
            .foregroundStyle(.primary)
            .padding(14)

            content
        }
        .card()
        .confirmationDialog("Delete this search?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteSearch(item.id) }
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        switch (item.status, item.outcome) {
        case (.searching, _):
            parts.append(item.foundSoFar > 0 ? "Searching… \(item.foundSoFar) found" : "Searching…")
        case (.queued, _), (.idle, nil):
            parts.append("Queued")
        case let (_, .results(results)):
            parts.append("\(results.count) result\(results.count == 1 ? "" : "s")")
        case (_, .downloadStarted):
            parts.append("Download started")
        case (_, .failed):
            parts.append("Nothing found")
        }
        if item.status != .searching {
            if item.isActive, item.lastRun != nil, let next = item.nextRunDate {
                parts.append("next try \(relativeTime(next))")
            } else if let last = item.lastRun {
                parts.append(relativeTime(last))
            }
        }
        if item.attempts > 1 { parts.append("attempt \(item.attempts)") }
        if item.autoDownload { parts.append("auto-download") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        switch (item.status, item.outcome) {
        case (.searching, _):
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking across your search providers…").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        case let (_, .results(results)) where item.status != .queued:
            VStack(spacing: 0) {
                ForEach(results) { result in
                    Divider().padding(.leading, 14)
                    ResultRow(result: result)
                }
            }
            .padding(.bottom, 4)
        case let (_, .downloadStarted(title)) where item.status != .queued:
            Message(systemImage: "checkmark.circle.fill", tint: Theme.primary, text: "Download started: \(title)")
        case let (_, .failed(reason)) where item.status != .queued:
            Message(systemImage: "exclamationmark.magnifyingglass", tint: .orange, text: reason.message)
        default:
            EmptyView()
        }
    }
}

private struct Message: View {
    let systemImage: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}

struct ResultRow: View {
    @Environment(AppModel.self) private var model
    let result: SearchResult
    @State private var adding = false
    @State private var added = 0

    private var alreadyAdded: Bool { model.downloads.contains(infoHash: result.infoHash) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(result.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let seeds = result.seeds {
                        StatChip(systemImage: "arrow.up", text: "\(seeds)", tint: seeds > 0 ? .green : .secondary)
                    }
                    if let leechers = result.leechers {
                        StatChip(systemImage: "arrow.down", text: "\(leechers)", tint: .orange)
                    }
                    if result.size > 0 {
                        StatChip(systemImage: "internaldrive", text: Format.bytes(result.size))
                    }
                    if result.preferredQuality {
                        StatChip(systemImage: "sparkles", text: "HQ", tint: .purple)
                    }
                    Text(result.source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button {
                Task { await add() }
            } label: {
                ZStack {
                    Circle().fill(alreadyAdded ? Theme.primary : Theme.primary.opacity(0.14))
                    if adding {
                        ProgressView().tint(Theme.primary)
                    } else {
                        Image(systemName: alreadyAdded ? "checkmark" : "arrow.down")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(alreadyAdded ? .white : Theme.primary)
                    }
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(adding || alreadyAdded)
            .accessibilityLabel(alreadyAdded ? "Added" : "Download")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .sensoryFeedback(.success, trigger: added)
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
            added += 1
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
                    .padding(16)
            }
            .background(Theme.screenBackground)
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
        .fontDesign(.rounded)
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
