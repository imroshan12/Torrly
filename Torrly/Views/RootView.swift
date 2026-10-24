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
                TabStrip(selection: $model.tab)
                TabView(selection: $model.tab) {
                    HistoryView().tag(AppTab.history)
                    SearchFormView().tag(AppTab.search)
                    DownloadsView().tag(AppTab.downloads)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .overlay(alignment: .bottomTrailing) { addButton }
            .navigationTitle("Torrly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.primary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.primary, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .padding(20)
        .accessibilityLabel("add")
    }
}

private struct PendingFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Green tab strip under the toolbar (HISTORY / SEARCH / DOWNLOADS).
struct TabStrip: View {
    @Binding var selection: AppTab
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.snappy) { selection = tab }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == tab ? .white : .white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        ZStack {
                            Rectangle().fill(.clear).frame(height: 3)
                            if selection == tab {
                                Rectangle().fill(.white).frame(height: 3).matchedGeometryEffect(id: "line", in: underline)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .background(Theme.primary)
    }
}

extension UTType {
    static let torrent = UTType(importedAs: "org.bittorrent.torrent")
}
