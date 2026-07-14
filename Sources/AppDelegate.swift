import Cocoa
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {

    let conversionManager = ConversionManager()
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

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

    // Keka-style quit behavior
    private var quitAfterNextConversion = true
    private var activeConversions = 0
    private var launchedWithFiles = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set up the main menu bar
        setupMainMenu()

        // Register for admconvert:// URLs here, NOT via application(_:open:).
        // AppKit delivers that delegate call after didFinishLaunching, which
        // races the 0.15s show-window timer — losing the race flashes the main
        // window open for Finder-extension conversions. A kAEGetURL handler
        // registered in willFinishLaunching is guaranteed to see a launch URL
        // before the timer starts (same ordering dock drops rely on).
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register default preferences
        UserDefaults.standard.register(defaults: ["includeSoundCheck": true, "useOutputFolder": false])

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

        // Silent update check shortly after launch. Sparkle bypasses its 24h
        // throttle for this call but still respects the user's auto-check
        // preference — only shows UI if an update is actually available.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.updater.updater.checkForUpdatesInBackground()
        }

        // Silently enable the Finder extension on first run (same pluginkit
        // mechanism Dropbox uses); falls back to a one-time prompt if that
        // fails. Skipped for headless launches.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !self.launchedWithFiles {
                self.setupFinderExtensionIfNeeded()
            }
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

        let updatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = updater
        appMenu.addItem(updatesItem)

        appMenu.addItem(NSMenuItem(title: "Finder Extension Settings...", action: #selector(openFinderExtensionSettings(_:)), keyEquivalent: ""))
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
        // Don't quit if we're in headless mode (conversion still running)
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

    // MARK: - URL Scheme (Finder extension)

    // admconvert://convert?mode=samefolder|usefolder&file=/path&file=/path...
    // Sent by the Finder Sync extension. Always converts headless, with the
    // output-folder choice from the menu item overriding the saved preference.
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "admconvert",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }

        let files = queryItems
            .filter { $0.name == "file" }
            .compactMap { $0.value }
            .map { URL(fileURLWithPath: $0) }
        guard !files.isEmpty else { return }

        let mode = queryItems.first(where: { $0.name == "mode" })?.value
        let outputFolderOverride: Bool? = (mode == "usefolder") ? true : (mode == "samefolder" ? false : nil)

        launchedWithFiles = true
        let shouldQuit = quitAfterNextConversion
        quitAfterNextConversion = false
        processFilesHeadless(files, quitWhenDone: shouldQuit, outputFolderOverride: outputFolderOverride)
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

    func processFilesHeadless(_ urls: [URL], quitWhenDone: Bool = false, outputFolderOverride: Bool? = nil) {
        guard !urls.isEmpty else { return }

        activeConversions += 1

        // Create and start the headless progress controller
        let controller = HeadlessProgressController()
        headlessController = controller
        controller.start(urls: urls, quitWhenDone: quitWhenDone, outputFolderOverride: outputFolderOverride)
    }

    // MARK: - Finder Extension Enablement

    @objc func openFinderExtensionSettings(_ sender: Any?) {
        let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync")!
        NSWorkspace.shared.open(url)
    }

    private let finderExtensionID = "com.jessos.adm-convert.finder"

    @discardableResult
    private func runPluginkit(_ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    // Returns true/false for enabled/disabled, nil if pluginkit gave no answer
    // (e.g. the extension isn't registered yet on a fresh install).
    private func finderExtensionEnabled() -> Bool? {
        guard let output = runPluginkit(["-m", "-i", finderExtensionID]),
              let flag = output.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return flag == "+"
    }

    // One-shot: silently self-enable the extension (the pluginkit election is
    // user-level, no admin rights involved). If the user later disables it in
    // System Settings, we never re-enable — their choice stands.
    private func setupFinderExtensionIfNeeded() {
        let doneKey = "finderExtensionSetupDone"
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }

        DispatchQueue.global(qos: .utility).async {
            // nil = not registered with pluginkit yet; try again next launch.
            guard let enabled = self.finderExtensionEnabled() else { return }

            if enabled {
                UserDefaults.standard.set(true, forKey: doneKey)
                return
            }

            self.runPluginkit(["-e", "use", "-i", self.finderExtensionID])
            Thread.sleep(forTimeInterval: 1.0)
            let nowEnabled = self.finderExtensionEnabled() == true
            UserDefaults.standard.set(true, forKey: doneKey)

            if !nowEnabled {
                DispatchQueue.main.async {
                    self.showFinderExtensionPrompt()
                }
            }
        }
    }

    // Fallback, only shown if the silent enable didn't take.
    private func showFinderExtensionPrompt() {
        let alert = NSAlert()
        alert.messageText = "Convert right from Finder"
        alert.informativeText = """
            JessOS ADM Convert can now add "Convert to M4A" to Finder's right-click menu.

            To turn it on: System Settings → General → Login Items & Extensions, then under Extensions click the ⓘ next to "File Providers" and enable JessOS ADM Convert.

            You can open these settings anytime from the app menu.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            openFinderExtensionSettings(nil)
        }
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
