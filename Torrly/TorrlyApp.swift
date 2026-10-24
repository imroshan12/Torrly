import SwiftUI
import UserNotifications

@main
struct TorrlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.primary)
                .preferredColorScheme(colorScheme)
                .onOpenURL { model.open($0) }
                .onAppear {
                    appDelegate.model = model
                    model.notifier.requestPermission()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.downloads.refresh()
                model.startScheduler()
            case .background:
                model.stopScheduler()
                model.scheduleBackgroundRefresh()
                saveInBackground()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await model.handleBackgroundRefresh()
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Keeps the app alive for the few seconds iOS allows so resume data gets written.
    private func saveInBackground() {
        let application = UIApplication.shared
        let task = BackgroundTaskBox()
        task.id = application.beginBackgroundTask(withName: "save-torrents") {
            MainActor.assumeIsolated { task.end() }
        }
        Task {
            await model.downloads.saveState()
            task.end()
        }
    }
}

@MainActor
private final class BackgroundTaskBox {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor weak var model: AppModel?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let idString = response.notification.request.content.userInfo[Notifier.searchIDKey] as? String
        await MainActor.run {
            if let idString, let id = UUID(uuidString: idString) {
                model?.tab = .history
                model?.focusedSearch = id
            } else {
                model?.tab = .downloads
            }
        }
    }
}
