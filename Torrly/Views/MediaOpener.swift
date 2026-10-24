import AVFoundation
import AVKit
import QuickLook
import SwiftUI

/// A downloaded file to open (TorrDroid opens finished downloads with a player via ACTION_VIEW).
struct OpenableFile: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

enum MediaKind {
    case playable
    case other

    /// Formats AVFoundation can play; others (e.g. .mkv, .avi) go to Quick Look, whose share button reaches VLC and similar apps.
    static func of(_ url: URL) async -> MediaKind {
        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        let hasMedia = !((try? await asset.load(.tracks)) ?? []).isEmpty
        return playable && hasMedia ? .playable : .other
    }
}

extension View {
    /// Presents `file` in a full-screen player when iOS can play it, otherwise in Quick Look.
    func mediaOpener(_ file: Binding<OpenableFile?>) -> some View {
        modifier(MediaOpenerModifier(file: file))
    }
}

private struct MediaOpenerModifier: ViewModifier {
    @Binding var file: OpenableFile?
    @State private var player: OpenableFile?
    @State private var preview: OpenableFile?

    func body(content: Content) -> some View {
        content
            .task(id: file) {
                guard let target = file else { return }
                file = nil
                switch await MediaKind.of(target.url) {
                case .playable: player = target
                case .other: preview = target
                }
            }
            .fullScreenCover(item: $player) { PlayerView(url: $0.url).ignoresSafeArea() }
            .sheet(item: $preview) { QuickLookView(url: $0.url).ignoresSafeArea() }
    }
}

private struct PlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        // Play sound even with the silent switch on, like any video app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}

private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
