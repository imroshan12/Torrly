import SwiftUI
import TorrlyCore

/// The SEARCH tab: keyword, retry interval, torrent type and "Download if available" (TorrDroid's search page).
struct SearchFormView: View {
    @Environment(AppModel.self) private var model
    @State private var keyword = ""
    @State private var interval = RetryInterval.never
    @State private var type: ContentType?
    @State private var autoDownload = false
    @State private var maxSize = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SearchFields(keyword: $keyword, interval: $interval, type: $type, autoDownload: $autoDownload, maxSize: $maxSize)
                    .onSubmit(submit)
                    .zIndex(1) // keeps the suggestion dropdown above the SEARCH button

                Button(action: submit) {
                    Text("SEARCH")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 150, height: 46)
                        .background(canSubmit ? Theme.primary : Color.gray, in: RoundedRectangle(cornerRadius: 4))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var canSubmit: Bool {
        !keyword.trimmingCharacters(in: .whitespaces).isEmpty && type != nil
    }

    private func submit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let size = Int(maxSize) ?? 0
        if !maxSize.isEmpty, size <= 0 {
            model.toast = "Please enter a valid size limit"
            return
        }
        if let error = model.submitSearch(keyword: keyword, type: type, interval: interval, autoDownload: autoDownload, maxSizeMB: size) {
            model.toast = error
            return
        }
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
    @Environment(AppModel.self) private var model
    @FocusState private var keywordFocused: Bool
    @State private var suggestions: [String] = []
    /// Set when the keyword was filled from a suggestion, so that change doesn't fetch again.
    @State private var picked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 4) {
                TextField("Enter Keywords to search torrent", text: $keyword)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($keywordFocused)
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 1)
            }
            .overlay(alignment: .topLeading) {
                if keywordFocused, !suggestions.isEmpty { suggestionList.offset(y: 44) }
            }
            .zIndex(1)
            .task(id: keyword) { await loadSuggestions() }
            .onChange(of: keywordFocused) { _, focused in if !focused { suggestions = [] } }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .trailing, spacing: 6) {
                    HelpButton(title: "Retry Interval",
                               message: "Time after which search should be attempted again if it was not successful in last attempt.")
                    Picker("Retry Interval", selection: $interval) {
                        ForEach(RetryInterval.allCases) { option in
                            Text(option == .never ? "Retry Interval" : option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .underlined()
                }
                VStack(alignment: .trailing, spacing: 6) {
                    HelpButton(title: "Torrent Type", message: "Select the file type of the torrent you wish to download")
                    Picker("Torrent Type", selection: $type) {
                        Text("Torrent Type").tag(ContentType?.none)
                        ForEach(ContentType.allCases) { option in
                            Text(option.title).tag(Optional(option))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .underlined()
                }
            }
            .tint(.primary)

            HStack {
                Toggle(isOn: $autoDownload) {
                    Text("Download if available").font(.title3)
                }
                .toggleStyle(CheckboxToggleStyle())
                Spacer()
                HelpButton(title: "Download if available",
                           message: "Let the app search and download a torrent if it's reliable and matches the filters above")
            }

            if autoDownload {
                HStack {
                    TextField("Max size in MB (optional)", text: $maxSize)
                        .keyboardType(.numberPad)
                    Text("MB").foregroundStyle(.secondary)
                }
                .underlined()
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
                    Text(suggestion)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if suggestion != suggestions.prefix(6).last { Divider() }
            }
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
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

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(configuration.isOn ? Theme.primary : .secondary)
                configuration.label.foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private struct Underlined: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 2) {
            content
            Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 1)
        }
    }
}

extension View {
    func underlined() -> some View { modifier(Underlined()) }
}
