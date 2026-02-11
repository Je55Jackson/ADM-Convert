import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {

    // Shared conversion manager
    let conversionManager = ConversionManager()
    let updateManager = UpdateManager()

    // Window visibility tracking
    @Published var isWindowVisible = false

    // Main window controller
    private var mainWindowController: MainWindowController?

    // User preferences (bridged from ConversionManager)
    var includeSoundCheck: Bool {
        get { UserDefaults.standard.bool(forKey: "includeSoundCheck") }
        set { UserDefaults.standard.set(newValue, forKey: "includeSoundCheck") }
    }

    var useOutputFolder: Bool {
        get { UserDefaults.standard.bool(forKey: "useOutputFolder") }
        set { UserDefaults.standard.set(newValue, forKey: "useOutputFolder") }
    }

    let parallelJobs = "12"

    // Keka-style quit behavior
    private var quitAfterNextConversion = true
    private var activeConversions = 0
    private var launchedWithFiles = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set up the main menu bar
        setupMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register default preferences
        UserDefaults.standard.register(defaults: ["includeSoundCheck": true, "useOutputFolder": false])

        // Register for services
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // Create window controller (but don't show window yet)
        mainWindowController = MainWindowController(appDelegate: self)

        // Wait a moment to see if files arrive, then show window if not
        // Reduced delay for snappier normal launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !self.launchedWithFiles {
                // User launched app normally - show the window
                self.showMainWindow()
                self.quitAfterNextConversion = false
            }
        }

        // Safety: after 5 seconds, definitely don't quit
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.quitAfterNextConversion = false
        }

        // Silent update check on launch (no alerts if offline or up to date)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.updateManager.checkForUpdates(userInitiated: false)
        }
    }

    // MARK: - Main Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let appName = "JessOS ADM Convert"
        appMenu.addItem(NSMenuItem(title: "About \(appName)", action: #selector(showAbout(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())

        appMenu.addItem(NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        // Edit menu (for copy/paste in text fields)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    func showMainWindow() {
        mainWindowController?.showWindow()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        isWindowVisible = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit if we're in headless mode (processing files via ADMProgress)
        if launchedWithFiles || activeConversions > 0 {
            return false
        }
        return true
    }

    // MARK: - About Dialog

    @objc func showAbout(_ sender: Any?) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        let alert = NSAlert()
        alert.messageText = "JessOS ADM Convert"
        alert.informativeText = """
            Version \(version) (Build \(build))

            Converts WAV/AIFF audio to AAC (.m4a) using Apple Digital Masters encoding parameters.

            256kbps AAC \u{2022} Optional SoundCheck \u{2022} Apple Silicon Native

            \u{00A9} 2024 Jess Jackson
            """
        alert.alertStyle = .informational

        if let icon = NSImage(named: "AppIcon") {
            alert.icon = icon
        }

        alert.runModal()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updateManager.checkForUpdates(userInitiated: true)
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
        let titleItem = NSMenuItem(title: "JessOS ADM Convert v\(version)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let includeItem = NSMenuItem(
            title: "Include SoundCheck Metadata",
            action: #selector(selectIncludeSoundCheck(_:)),
            keyEquivalent: ""
        )
        includeItem.state = includeSoundCheck ? .on : .off
        menu.addItem(includeItem)

        let excludeItem = NSMenuItem(
            title: "Exclude SoundCheck Metadata (Fast)",
            action: #selector(selectExcludeSoundCheck(_:)),
            keyEquivalent: ""
        )
        excludeItem.state = includeSoundCheck ? .off : .on
        menu.addItem(excludeItem)

        menu.addItem(NSMenuItem.separator())

        let outputFolderItem = NSMenuItem(
            title: "Output to M4A Folder",
            action: #selector(toggleOutputFolder(_:)),
            keyEquivalent: ""
        )
        outputFolderItem.state = useOutputFolder ? .on : .off
        menu.addItem(outputFolderItem)

        menu.addItem(NSMenuItem.separator())

        let showWindowItem = NSMenuItem(
            title: "Show Window",
            action: #selector(showMainWindowFromMenu(_:)),
            keyEquivalent: ""
        )
        menu.addItem(showWindowItem)

        return menu
    }

    @objc func showMainWindowFromMenu(_ sender: NSMenuItem) {
        quitAfterNextConversion = false  // User wants to interact, don't auto-quit
        showMainWindow()
    }

    @objc func selectIncludeSoundCheck(_ sender: NSMenuItem) {
        includeSoundCheck = true
    }

    @objc func selectExcludeSoundCheck(_ sender: NSMenuItem) {
        includeSoundCheck = false
    }

    @objc func toggleOutputFolder(_ sender: NSMenuItem) {
        useOutputFolder = !useOutputFolder
    }

    // MARK: - File Handling (Drag & Drop, Open With)

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        handleIncomingFiles([url])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        handleIncomingFiles(urls)
        NSApp.reply(toOpenOrPrint: .success)
    }

    private func handleIncomingFiles(_ urls: [URL]) {
        // If window is already visible, add files to the list (window mode)
        if isWindowVisible {
            conversionManager.addFiles(urls)
            return
        }

        // Window not visible - this is a dock drop, use headless mode
        // Queue files with debouncing to accumulate rapid openFile calls
        launchedWithFiles = true
        let shouldQuit = quitAfterNextConversion
        quitAfterNextConversion = false
        queueFilesForHeadless(urls, quitWhenDone: shouldQuit)
    }

    // MARK: - Services Handler

    @objc func convertToM4A(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let items = pboard.pasteboardItems else {
            error.pointee = "No items on pasteboard" as NSString
            return
        }

        var urls: [URL] = []

        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                urls.append(url)
            }
        }

        if urls.isEmpty, let filenames = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = filenames.map { URL(fileURLWithPath: $0) }
        }

        if urls.isEmpty {
            error.pointee = "No files found" as NSString
            return
        }

        // Treat Services the same as dock drop: headless mode, quit when done
        launchedWithFiles = true
        queueFilesForHeadless(urls, quitWhenDone: true)
    }

    // MARK: - Processing (Headless Mode with native progress popup)

    private var headlessController: HeadlessProgressController?

    // File accumulation for dock drops (macOS may call openFile multiple times)
    private var pendingHeadlessFiles: [URL] = []
    private var headlessDebounceWorkItem: DispatchWorkItem?
    private var pendingQuitWhenDone = false

    private func queueFilesForHeadless(_ urls: [URL], quitWhenDone: Bool) {
        // Accumulate files
        pendingHeadlessFiles.append(contentsOf: urls)
        if quitWhenDone {
            pendingQuitWhenDone = true
        }

        // Cancel previous debounce timer
        headlessDebounceWorkItem?.cancel()

        // Start new debounce timer (100ms to collect all files from rapid openFile calls)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let files = self.pendingHeadlessFiles
            let shouldQuit = self.pendingQuitWhenDone
            self.pendingHeadlessFiles = []
            self.pendingQuitWhenDone = false
            self.processFilesHeadless(files, quitWhenDone: shouldQuit)
        }
        headlessDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    func processFilesHeadless(_ urls: [URL], quitWhenDone: Bool = false) {
        guard !urls.isEmpty else { return }

        activeConversions += 1

        // Create and start the headless progress controller
        let controller = HeadlessProgressController()
        headlessController = controller
        controller.start(urls: urls, quitWhenDone: quitWhenDone)
    }

    func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.runModal()
        }
    }
}

// MARK: - String Extension for Shell Quoting

extension String {
    func shellQuoted() -> String {
        return "'\(self.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
