import SwiftUI
import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        return true
    }
}
@main struct LanternApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ChatStore()
    var body: some Scene {
        Window("Lantern", id: "main") {
            ContentView(store: store).frame(minWidth: 760, minHeight: 560)
                .task { await store.connect() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.shutdown() }
        }
        .restorationBehavior(.disabled)
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { Button("New Conversation") { store.newChat() }.keyboardShortcut("n").disabled(store.generating) }
        }
    }
}
