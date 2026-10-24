import Foundation
import UserNotifications

/// Local notifications, worded like TorrDroid's (REPORT.md §2.10).
@MainActor
final class Notifier {
    nonisolated static let searchIDKey = "searchID"

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func suggestionsAvailable(keyword: String, searchID: UUID) {
        post(title: "Suggestions available", body: "Tap to see results for '\(keyword)'", id: "search-\(searchID)",
             info: [Self.searchIDKey: searchID.uuidString])
    }

    func searchComplete(keyword: String, message: String, searchID: UUID) {
        post(title: "Search Complete", body: "\(keyword): \(message)", id: "search-\(searchID)",
             info: [Self.searchIDKey: searchID.uuidString])
    }

    func downloadStarted(name: String) {
        post(title: "Download was started", body: name, id: "started-\(name.hashValue)")
    }

    func downloadComplete(name: String) {
        post(title: "Download complete", body: name, id: "done-\(name.hashValue)")
    }

    func waitingForWiFi() {
        post(title: "Waiting for Wi-fi", body: "Downloads will resume when wi-fi is available", id: "wifi")
    }

    private func post(title: String, body: String, id: String, info: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = info
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
