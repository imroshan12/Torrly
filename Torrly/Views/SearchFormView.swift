import SwiftUI
import TorrlyCore

/// The SEARCH tab: keyword, torrent type, retry interval and "Download if available" (TorrDroid's search page).
struct SearchFormView: View {
    @Environment(AppModel.self) private var model
    @State private var keyword = ""
    @State private var interval = RetryInterval.never
    @State private var type: ContentType?
    @State private var autoDownload = false
    @State private var maxSize = ""
    @State private var submitted = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SearchFields(keyword: $keyword, interval: $interval, type: $type, autoDownload: $autoDownload,
                             maxSize: $maxSize, showRecent: true)
                    .onSubmit(submit)
                    .zIndex(1) // keeps the suggestion dropdown above everything below it

                Button(action: submit) {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(.white)
                        .background(canSubmit ? Theme.primary : Color.gray.opacity(0.45),
                                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: canSubmit)
                .accessibilityHint(canSubmit ? "" : "Enter a keyword and choose a torrent type first")
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 100)
            .containerRelativeFrame(.vertical, alignment: .top)
            // Tapping empty space ends editing and closes the suggestions.
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { endEditing() })
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.screenBackground)
        .sensoryFeedback(.success, trigger: submitted)
    }

    private var canSubmit: Bool {
        !keyword.trimmingCharacters(in: .whitespaces).isEmpty && type != nil
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func submit() {
        endEditing()
        let size = Int(maxSize) ?? 0
        if !maxSize.isEmpty, size <= 0 {
            model.toast = "Please enter a valid size limit"
            return
        }
        if let error = model.submitSearch(keyword: keyword, type: type, interval: interval, autoDownload: autoDownload, maxSizeMB: size) {
            model.toast = error
            return
        }
        submitted += 1
        keyword = ""
        maxSize = ""
    }
}

/// Shared by the search tab and the edit sheet.
/// Typing 3+ characters shows keyword suggestions, like TorrDroid's AutoCompleteTextView.
struct SearchFields: View {
    @Binding var keyword: String
    @Binding var interval: RetryInterval
    @Binding var type: ContentType?
    @Binding var autoDownload: Bool
    @Binding var maxSize: String
    var showRecent = false
    @Environment(AppModel.self) private var model
    @FocusState private var keywordFocused: Bool
    @State private var suggestions: [String] = []
    /// Set when the keyword was filled from a suggestion, so that change doesn't fetch again.
    @State private var picked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            searchField
                .overlay(alignment: .topLeading) {
                    if keywordFocused, !suggestions.isEmpty { suggestionList.offset(y: 62) }
                }
                .zIndex(1)
                .task(id: keyword) { await loadSuggestions() }
                .onChange(of: keywordFocused) { _, focused in
                    if !focused { suggestions = [] }
                    model.editingSearch = focused
                }

            if showRecent, !recentKeywords.isEmpty, keyword.isEmpty {
                recentSearches
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Torrent type")
                    Spacer()
                    HelpButton(title: "Torrent Type", message: "Select the file type of the torrent you wish to download")
                }
                HStack(spacing: 10) {
                    ForEach(ContentType.allCases) { option in
                        TypeChip(type: option, selected: type == option) {
                            withAnimation(.snappy(duration: 0.2)) { type = option }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Options")
                VStack(spacing: 0) {
                    OptionRow(systemImage: "arrow.clockwise", title: "Retry if nothing found",
                              help: ("Retry Interval", "Time after which search should be attempted again if it was not successful in last attempt.")) {
                        Picker("Retry interval", selection: $interval) {
                            ForEach(RetryInterval.allCases) { option in
                                Text(option == .never ? "Off" : "Every \(option.title)").tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(Theme.primary)
                    }
                    Divider().padding(.leading, 56)
                    OptionRow(systemImage: "bolt.fill", title: "Download if available",
                              help: ("Download if available", "Let the app search and download a torrent if it's reliable and matches the filters above")) {
                        Toggle("Download if available", isOn: $autoDownload.animation())
                            .labelsHidden()
                            .tint(Theme.primary)
                    }
                    if autoDownload {
                        Divider().padding(.leading, 56)
                        OptionRow(systemImage: "internaldrive", title: "Max size", help: nil) {
                            HStack(spacing: 4) {
                                TextField("No limit", text: $maxSize)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 90)
                                Text("MB").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .card()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(keywordFocused ? Theme.primary : .secondary)
            TextField("Search movies, music, books, apps…", text: $keyword)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($keywordFocused)
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .card()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(keywordFocused ? Theme.primary : .clear, lineWidth: 1.5)
        }
        .animation(.easeInOut(duration: 0.15), value: keywordFocused)
    }

    private var recentKeywords: [String] {
        var seen = Set<String>()
        return model.searches.map(\.keyword).filter { seen.insert($0.lowercased()).inserted }.prefix(6).map { $0 }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Recent")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentKeywords, id: \.self) { recent in
                        Button {
                            picked = true
                            keyword = recent
                        } label: {
                            Label(recent, systemImage: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.cardBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(6), id: \.self) { suggestion in
                Button {
                    picked = true
                    keyword = suggestion
                    suggestions = []
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.footnote).foregroundStyle(.secondary)
                        Text(suggestion).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if suggestion != suggestions.prefix(6).last { Divider().padding(.leading, 44) }
            }
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private func loadSuggestions() async {
        if picked {
            picked = false
            return
        }
        guard model.settings.searchSuggestions, keywordFocused,
              keyword.trimmingCharacters(in: .whitespaces).count >= SearchSuggestions.minimumLength else {
            suggestions = []
            return
        }
        // Wait for a pause in typing before asking.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let found = await model.suggestions.suggestions(for: keyword)
        guard !Task.isCancelled else { return }
        suggestions = found.filter { $0.lowercased() != keyword.lowercased() }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

/// One of the four torrent types as a tappable tile.
private struct TypeChip: View {
    let type: ContentType
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.symbol).font(.title3.weight(.semibold))
                Text(type.label).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Theme.primary : Theme.cardBackground,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? .clear : Color(.separator).opacity(0.5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A settings-style row: icon, title, optional help, trailing control.
private struct OptionRow<Control: View>: View {
    let systemImage: String
    let title: String
    let help: (String, String)?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, size: 30)
            Text(title).font(.body)
            if let help { HelpButton(title: help.0, message: help.1) }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
    }
}
