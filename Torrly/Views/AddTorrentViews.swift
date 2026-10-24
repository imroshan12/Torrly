import SwiftUI
import TorrlyCore
import TorrlyEngine

/// "+" › Add link: magnet or http(s) link to a .torrent file.
struct AddLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Enter http/https/magnet link", text: $link, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(3 ... 6)
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                Button("Paste from clipboard", systemImage: "doc.on.clipboard") {
                    link = UIPasteboard.general.string ?? link
                }
            }
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if adding {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await add() } }.disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func add() async {
        adding = true
        defer { adding = false }
        do {
            try await model.downloads.add(link: link)
            model.toast = "Torrent has been added to downloads."
            model.tab = .downloads
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Pick which files of a .torrent to download (TorrDroid `FileChooserDialog`).
struct FileChooserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let torrentFile: URL
    @State private var info: EngineTorrentInfo?
    @State private var selected: Set<Int32> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let info {
                    List {
                        SwiftUI.Section {
                            LabeledContent("Name", value: info.name)
                            LabeledContent("Total size", value: Format.bytes(info.totalSize))
                            LabeledContent("Selected", value: Format.bytes(selectedSize(info)))
                        }
                        SwiftUI.Section {
                            ForEach(info.files, id: \.index) { file in
                                Button {
                                    if selected.contains(file.index) { selected.remove(file.index) } else { selected.insert(file.index) }
                                } label: {
                                    HStack {
                                        Image(systemName: selected.contains(file.index) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(selected.contains(file.index) ? Theme.primary : .secondary)
                                        Text(file.path).foregroundStyle(.primary).lineLimit(2)
                                        Spacer()
                                        Text(Format.bytes(file.size)).foregroundStyle(.secondary).font(.caption)
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("Files to download")
                                Spacer()
                                Button(selected.count == info.files.count ? "Select none" : "Select all") {
                                    selected = selected.count == info.files.count ? [] : Set(info.files.map(\.index))
                                }
                                .font(.caption)
                            }
                        }
                    }
                } else if let error {
                    ContentUnavailableView("Invalid torrent", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Add torrent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") { add() }.disabled(info == nil || selected.isEmpty)
                }
            }
        }
        .task {
            do {
                let parsed = try model.downloads.readTorrent(torrentFile)
                info = parsed
                selected = Set(parsed.files.map(\.index))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func selectedSize(_ info: EngineTorrentInfo) -> Int64 {
        info.files.filter { selected.contains($0.index) }.reduce(0) { $0 + $1.size }
    }

    private func add() {
        guard let info else { return }
        let count = Int((info.files.map(\.index).max() ?? 0) + 1)
        var priorities = [Int](repeating: 0, count: count)
        for index in selected { priorities[Int(index)] = 4 }
        do {
            try model.downloads.add(torrentFile: torrentFile, priorities: priorities)
            model.toast = "Torrent has been added to downloads."
            model.tab = .downloads
            dismiss()
        } catch {
            self.error = error.localizedDescription
            model.toast = error.localizedDescription
        }
    }
}
