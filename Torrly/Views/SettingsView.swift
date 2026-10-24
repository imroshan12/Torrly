import SwiftUI
import TorrlyCore

/// Settings, laid out like TorrDroid's preferences (REPORT.md §3.4).
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("Storage path") {
                    VStack(alignment: .trailing) {
                        Text("On My iPhone › Torrly › Downloads")
                        Text(freeSpace).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $model.settings.wifiOnly) {
                    VStack(alignment: .leading) {
                        Text("Download over wifi only")
                        Text(model.settings.wifiOnly ? "Download data when connected to wifi only" : "Download data whether or not connected to wifi")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $model.settings.maxSearchRetries, in: 0 ... 100) {
                    VStack(alignment: .leading) {
                        Text("Max search retries: \(model.settings.maxSearchRetries)")
                        Text("Maximum times a failed search should be retried before deactivating")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $model.settings.safeSearch) {
                    VStack(alignment: .leading) {
                        Text("Filter adult content")
                        Text(model.settings.safeSearch ? "Filter search results that point to adult content" : "Allow search results that point to adult content")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Search") {
                NavigationLink("Search providers") { ProvidersView() }
                Toggle(isOn: $model.settings.searchSuggestions) {
                    VStack(alignment: .leading) {
                        Text("Suggestions while typing")
                        Text("Shows keyword suggestions from Google as you type")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Search order", selection: $model.settings.searchAlgorithm) {
                    ForEach(SearchAlgorithm.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                NavigationLink("More…") { MoreSettingsView() }
            }
        }
        .navigationTitle("Settings")
        .greenNavigationBar()
    }

    private var freeSpace: String {
        let url = model.downloads.downloadDirectory
        let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        return free.map { "\(Format.bytes($0)) free" } ?? ""
    }
}

struct MoreSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var port = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: $model.settings.seeding) {
                    VStack(alignment: .leading) {
                        Text("Seeding")
                        Text(model.settings.seeding ? "Seed torrents after completing downloads" : "Don't seed torrents after completing downloads")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Theme", selection: $model.settings.theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Speed") {
                LabeledContent("Maximum download speed (KB/s)") {
                    TextField("0", value: $model.settings.maxDownloadKBps, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Maximum upload speed (KB/s)") {
                    TextField("0", value: $model.settings.maxUploadKBps, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                Text("0 means unlimited.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Encryption") {
                Picker("Connection encryption", selection: $model.settings.encryption) {
                    ForEach(EncryptionChoice.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Incoming connections", isOn: $model.settings.encryptIncoming)
                Toggle("Outgoing connections", isOn: $model.settings.encryptOutgoing)
            }
            Section("Port") {
                Toggle("Use random port", isOn: $model.settings.randomizePort)
                if model.settings.randomizePort {
                    LabeledContent("Current port", value: String(model.settings.randomPort))
                } else {
                    LabeledContent("Port") {
                        TextField("6880", value: $model.settings.port, format: .number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
            }
            Section("Proxy") {
                Picker("Proxy type", selection: $model.settings.proxyType) {
                    ForEach(ProxyChoice.allCases) { Text($0.title).tag($0) }
                }
                if model.settings.proxyType != .none {
                    TextField("Proxy address", text: $model.settings.proxyHost)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    LabeledContent("Proxy port") {
                        TextField("1080", value: $model.settings.proxyPort, format: .number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Toggle("Proxy needs authentication", isOn: $model.settings.proxyNeedsAuth)
                    if model.settings.proxyNeedsAuth {
                        TextField("Username", text: $model.settings.proxyUsername)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $model.settings.proxyPassword)
                    }
                    Text("The proxy is used for peer and tracker connections. Search requests use the system network settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("More…")
        .greenNavigationBar()
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Torrent engine", value: "libtorrent \(DownloadManager.engineVersion)")
            }
            Section("How to use") {
                Text("Search: type a keyword, pick the torrent type and tap SEARCH. Results appear in History. With a retry interval, a search that finds nothing is repeated later and you get a notification when something turns up.")
                Text("Download if available: the best reliable match is downloaded automatically.")
                Text("Downloads are saved to Files › On My iPhone › Torrly › Downloads. iOS only lets downloads run while Torrly is open, plus a short time after you leave it.")
                Text("Search providers are configurable in Settings. Only download content you have the right to download.")
            }
            .font(.callout)
        }
        .navigationTitle("About")
        .greenNavigationBar()
    }
}
