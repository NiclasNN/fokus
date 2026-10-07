import SwiftUI
import UserNotifications

@main
struct FokusApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(scheme)
                .tint(store.activeTint)
        }
        .onChange(of: phase) { _, new in
            switch new {
            case .active:
                // appen kan ha varit stängd i timmar — räkna om mot klockan
                store.resumeIfNeeded()
                UNUserNotificationCenter.current().setBadgeCount(0)
            case .background:
                store.saveNow()
                store.scheduleAlarm()
            default: break
            }
        }
    }

    private var scheme: ColorScheme? {
        switch store.s.settings.theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
