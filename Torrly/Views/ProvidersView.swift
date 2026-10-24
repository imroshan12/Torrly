import SwiftUI
import TorrlyCore
import UniformTypeIdentifiers

/// Search providers: order, enable, add, import (TorrDroid's remote `order` + `siteMap` + `siteSettings`, made local).
struct ProvidersView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ProviderDefinition?
    @State private var pasting = false
    @State private var importing = false

    var body: some View {
        List {
            Section {
                ForEach(model.providers) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                            Text(provider.kindLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { provider.isEnabled }, set: { enabled in
                            var updated = provider
                            updated.isEnabled = enabled
                            model.upsert(updated)
                        }))
                        .labelsHidden()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = provider }
                }
                .onMove { from, to in
                    var list = model.providers
                    list.move(fromOffsets: from, toOffset: to)
                    model.setProviders(list)
                }
                .onDelete { offsets in
                    var list = model.providers
                    list.remove(atOffsets: offsets)
                    model.setProviders(list)
                }
            } footer: {
                Text("Providers are searched top to bottom. Each one is a JSON rule set: HTML rules use the same format as TorrDroid's siteSettings, so a rule set can be imported directly. Tap a provider to edit its rules.")
            }
        }
        .navigationTitle("Search providers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Paste JSON", systemImage: "doc.on.clipboard") { pasting = true }
                    Button("Import JSON file", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Restore built-in providers", systemImage: "arrow.counterclockwise") { model.restoreDefaultProviders() }
                } label: {
                    Image(systemName: "plus").foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton().foregroundStyle(.white) }
        }
        .greenNavigationBar()
        .sheet(item: $editing) { provider in ProviderEditor(provider: provider) }
        .sheet(isPresented: $pasting) { PasteProvidersSheet() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let count = try model.importProviders(from: Data(contentsOf: url))
                model.toast = "Imported \(count) provider\(count == 1 ? "" : "s")"
            } catch {
                model.toast = error.localizedDescription
            }
        }
    }
}

private struct PasteProvidersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.caption.monospaced())
                        .frame(minHeight: 260)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("A provider, a list of providers, or a siteSettings object such as { \"https://site\": { \"request\": …, \"rows\": …, \"name\": … } }.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Paste providers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        do {
                            let count = try model.importProviders(from: Data(text.utf8))
                            model.toast = "Imported \(count) provider\(count == 1 ? "" : "s")"
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
    }
}

/// Edits one provider as JSON, then tests it with a sample query.
private struct ProviderEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let provider: ProviderDefinition
    @State private var name = ""
    @State private var json = ""
    @State private var error: String?
    @State private var testQuery = "ubuntu"
    @State private var testType = ContentType.software
    @State private var testOutput: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Name", text: $name) }
                Section {
                    TextEditor(text: $json)
                        .font(.caption.monospaced())
                        .frame(minHeight: 280)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(provider.kindLabel + " rules")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section("Test") {
                    TextField("Query", text: $testQuery).textInputAutocapitalization(.never)
                    Picker("Type", selection: $testType) {
                        ForEach(ContentType.allCases) { Text($0.title).tag($0) }
                    }
                    Button(testing ? "Searching…" : "Run test search") { Task { await test() } }.disabled(testing)
                    if let testOutput { Text(testOutput).font(.caption.monospaced()) }
                }
            }
            .navigationTitle(provider.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let updated = parse() {
                            model.upsert(updated)
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            name = provider.name
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data: Data? = if let html = provider.html { try? encoder.encode(html) } else { try? encoder.encode(provider.json) }
            json = data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        }
    }

    private func parse() -> ProviderDefinition? {
        var updated = provider
        updated.name = name
        do {
            if provider.html != nil {
                updated.html = try JSONDecoder().decode(HTMLSiteRules.self, from: Data(json.utf8))
            } else {
                updated.json = try JSONDecoder().decode(JSONAPIRules.self, from: Data(json.utf8))
            }
            error = nil
            return updated
        } catch {
            self.error = "Invalid rules: \(error.localizedDescription)"
            return nil
        }
    }

    private func test() async {
        guard let candidate = parse(), let search = candidate.makeProvider(http: URLSessionHTTPClient()) else { return }
        testing = true
        defer { testing = false }
        do {
            let results = try await search.search(ProviderQuery(text: testQuery, contentType: testType))
            testOutput = results.isEmpty ? "No rows matched." : results.prefix(5).map {
                "\($0.title)\n  \(Format.bytes($0.size)) • S \($0.seeds.map(String.init) ?? "?") L \($0.leechers.map(String.init) ?? "?")"
            }.joined(separator: "\n") + "\n\(results.count) result(s)"
        } catch {
            testOutput = "Failed: \(error.localizedDescription)"
        }
    }
}
