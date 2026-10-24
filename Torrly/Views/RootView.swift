import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddLink = false
    @State private var showFileImporter = false
    @State private var showSettings = false
    @State private var showProviders = false
    @State private var showAbout = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                TabStrip(selection: $model.tab, badges: tabBadges)
                TabView(selection: $model.tab) {
                    HistoryView().tag(AppTab.history)
                    SearchFormView().tag(AppTab.search)
                    DownloadsView().tag(AppTab.downloads)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(alignment: .top) {
                // One solid green behind the title bar and the tab strip, so both read as a single header.
                Theme.primary.frame(height: 1).ignoresSafeArea(edges: .top)
            }
            .background(Theme.screenBackground)
            .overlay(alignment: .bottomTrailing) {
                if !model.editingSearch { addButton.transition(.scale.combined(with: .opacity)) }
            }
            .animation(.snappy(duration: 0.2), value: model.editingSearch)
            .navigationTitle("Torrly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
            .navigationDestination(isPresented: $showProviders) { ProvidersView() }
            .navigationDestination(isPresented: $showAbout) { AboutView() }
            .navigationDestination(for: String.self) { hash in TorrentDetailView(infoHash: hash) }
        }
        .sheet(isPresented: $showAddLink) { AddLinkSheet() }
        .sheet(item: Binding(get: { model.pendingTorrentFile.map(PendingFile.init) },
                             set: { model.pendingTorrentFile = $0?.url })) { pending in
            FileChooserView(torrentFile: pending.url)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.torrent]) { result in
            if case let .success(url) = result { model.open(url) }
        }
        .mediaOpener($model.openingFile)
        .toast($model.toast)
        .fontDesign(.rounded)
    }

    private var tabBadges: [AppTab: Int] {
        let active = model.downloads.torrents.filter { !$0.isPaused && !$0.isComplete }.count
        let searching = model.searches.filter { $0.status == .searching }.count
        return [.downloads: active, .history: searching]
    }

    private var menu: some View {
        Menu {
            Button("Resume all", systemImage: "play.fill") { model.downloads.resumeAll() }
            Button("Pause all", systemImage: "pause.fill") { model.downloads.pauseAll() }
            Divider()
            Button("Search providers", systemImage: "globe") { showProviders = true }
            Button("Settings", systemImage: "gearshape") { showSettings = true }
            Button("About", systemImage: "info.circle") { showAbout = true }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("More options")
    }

    private var addButton: some View {
        Menu {
            Button("Add link", systemImage: "link") { showAddLink = true }
            Button("Open .torrent file", systemImage: "doc") { showFileImporter = true }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Theme.primary.gradient, in: Circle())
                .shadow(color: Theme.primary.opacity(0.45), radius: 10, y: 4)
        }
        .padding(20)
        .accessibilityLabel("add")
    }
}

private struct PendingFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Green tab strip under the toolbar (HISTORY / SEARCH / DOWNLOADS), with a sliding indicator.
struct TabStrip: View {
    @Binding var selection: AppTab
    var badges: [AppTab: Int] = [:]
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.snappy) { selection = tab }
                } label: {
                    VStack(spacing: 9) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbol)
                                .font(.subheadline.weight(.semibold))
                            Text(tab.title)
                                .font(.footnote.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let count = badges[tab], count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.primaryDark)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.white, in: Capsule())
                            }
                        }
                        .foregroundStyle(selection == tab ? .white : .white.opacity(0.72))
                        ZStack {
                            Capsule().fill(.clear).frame(height: 3)
                            if selection == tab {
                                Capsule().fill(.white).frame(width: 44, height: 3)
                                    .matchedGeometryEffect(id: "line", in: underline)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title.capitalized)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .background(Theme.primary)
    }
}

extension UTType {
    static let torrent = UTType(importedAs: "org.bittorrent.torrent")
}
