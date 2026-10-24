import SwiftUI
import TorrlyCore
import TorrlyEngine

enum Theme {
    /// TorrDroid's colorPrimary (#8BC34A, #9CCC65 at night) via the AccentColor asset.
    static let primary = Color("AccentColor")
    static let primaryDark = Color("PrimaryDark")
    static let screenBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let cornerRadius: CGFloat = 16

    static func color(for torrent: EngineTorrentStatus) -> Color {
        if torrent.state == .error { return .red }
        if torrent.isComplete { return torrent.isPaused ? .gray : .teal }
        switch torrent.state {
        case .paused: return .gray
        case .checkingFiles, .checkingResumeData, .downloadingMetadata: return .blue
        default: return primary
        }
    }
}

// MARK: - Cards and chips

private struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 8, y: 2)
    }
}

extension View {
    /// Rounded card on the grouped background.
    func card() -> some View { modifier(CardModifier()) }
}

/// Small icon + value pill, e.g. seeders or size.
struct StatChip: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text).monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Coloured state label, e.g. "Downloading".
struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Rounded-square icon tile.
struct IconTile: View {
    let systemImage: String
    var tint: Color = Theme.primary
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Thin rounded progress bar.
struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule().fill(tint).frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: value)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// Empty-state block with an icon, text and an optional action.
struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 84, height: 84)
                .background(Theme.primary.opacity(0.14), in: Circle())
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Icons

extension ContentType {
    var symbol: String {
        switch self {
        case .audio: "music.note"
        case .video: "film"
        case .ebook: "book.closed"
        case .software: "square.grid.2x2"
        }
    }

    var label: String { title.capitalized }
}

enum FileIcon {
    /// Symbol for a torrent or file name, from its extension (no extension usually means a folder torrent).
    static func symbol(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp4", "mkv", "avi", "mov", "m4v", "webm", "wmv", "flv", "ts": "film"
        case "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus": "music.note"
        case "pdf", "epub", "mobi", "azw3", "djvu", "cbz", "cbr": "book.closed"
        case "iso", "img", "dmg": "opticaldiscdrive"
        case "zip", "rar", "7z", "tar", "gz", "xz", "bz2": "doc.zipper"
        case "apk", "ipa", "exe", "msi", "deb", "rpm", "appimage": "app.badge"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": "photo"
        case "srt", "txt", "nfo": "doc.text"
        case "": "folder"
        default: "doc"
        }
    }
}

// MARK: - Help and toast

/// The "?" button next to form fields, showing TorrDroid-style help text.
struct HelpButton: View {
    let title: String
    let message: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What's this?")
        .alert(title, isPresented: $showing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

/// Short message shown at the bottom of the screen, like an Android toast.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.82), in: Capsule())
                    .padding(.bottom, 96)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: message)
    }
}

extension View {
    /// Green title bar with white text, like TorrDroid's toolbar.
    func greenNavigationBar() -> some View {
        toolbarBackground(Theme.primary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}

/// Short relative time, e.g. "2 min ago" or "in 1 hr".
func relativeTime(_ date: Date) -> String {
    if abs(date.timeIntervalSinceNow) < 45 { return "just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}
