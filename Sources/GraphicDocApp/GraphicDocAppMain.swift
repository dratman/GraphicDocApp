import SwiftUI
import AppKit

// A plain command-line-built executable has no app bundle (no Info.plist),
// so macOS doesn't automatically register it as a regular foreground app —
// its window can end up created but not shown or focused, and it won't
// appear in the Dock. This delegate forces normal app behavior on launch.
// (Once this is packaged as a real .app bundle, this becomes unnecessary.)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct GraphicDocApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: GraphicDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
