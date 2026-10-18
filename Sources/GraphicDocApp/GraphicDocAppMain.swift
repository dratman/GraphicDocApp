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

    // The app stays running with no window, so File > Open… can create one.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// State shared between the menu bar and the windows.
final class AppModel: ObservableObject {
    // A grid just loaded by File > Open…, waiting for the new window that
    // File > Open… creates to take it.
    var pendingField: WaveField?
}

struct FileCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.saveFieldAction) private var saveAction

    var body: some Commands {
        // Replaces the default File > New items. As the Mac convention
        // expects, New and Open each create a new window.
        CommandGroup(replacing: .newItem) {
            Button("New") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open…") {
                // Deferred to the next turn of the main loop so the panel
                // isn't run from inside the menu action's own event handling.
                DispatchQueue.main.async { openField() }
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Save…") {
                DispatchQueue.main.async { saveAction?() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(saveAction == nil)

            Button("Save As…") {
                DispatchQueue.main.async { saveAction?() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(saveAction == nil)
        }
    }

    // Reads the chosen file and opens a new window showing it.
    private func openField() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            model.pendingField = try JSONDecoder().decode(WaveField.self, from: data)
            openWindow(id: "main")
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

@main
struct GraphicDocApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            FileCommands(model: model)
        }
    }
}
