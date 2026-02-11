import SwiftUI
import Cocoa

// Helper class to create and manage the main SwiftUI window
class MainWindowController {
    static var shared: MainWindowController?

    private var window: NSWindow?
    private let appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func showWindow() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the SwiftUI content view
        let contentView = ContentView()
            .environmentObject(appDelegate.conversionManager)

        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.contentView = NSHostingView(rootView: contentView)
        window.minSize = NSSize(width: 500, height: 300)
        window.backgroundColor = .clear
        window.isOpaque = false

        // Set window delegate to track visibility
        window.delegate = appDelegate

        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appDelegate.isWindowVisible = true
    }

    func closeWindow() {
        window?.close()
        appDelegate.isWindowVisible = false
    }
}
