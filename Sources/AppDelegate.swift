import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    // User preference for SoundCheck
    var includeSoundCheck: Bool {
        get { UserDefaults.standard.bool(forKey: "includeSoundCheck") }
        set { UserDefaults.standard.set(newValue, forKey: "includeSoundCheck") }
    }

    // User preference for output folder
    var useOutputFolder: Bool {
        get { UserDefaults.standard.bool(forKey: "useOutputFolder") }
        set { UserDefaults.standard.set(newValue, forKey: "useOutputFolder") }
    }

    // Parallel jobs setting
    let parallelJobs = "12"

    // Keka-style quit: if app was closed when files arrived, quit after conversion
    // True during the first few seconds after launch; cleared on first file open or after timeout
    private var quitAfterNextConversion = true
    private var activeConversions = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register default preferences
        UserDefaults.standard.register(defaults: ["includeSoundCheck": true, "useOutputFolder": false])

        // Register for services
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // If no files arrive within 5 seconds, user launched the app manually - don't quit
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.quitAfterNextConversion = false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        // App name and version at top
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
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

        let convertItem = NSMenuItem(
            title: "Convert Files...",
            action: #selector(openFilePicker(_:)),
            keyEquivalent: ""
        )
        menu.addItem(convertItem)

        return menu
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

    @objc func openFilePicker(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            processFiles(panel.urls)
        }
    }

    // MARK: - File Handling (Drag & Drop, Open With)

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        let shouldQuit = quitAfterNextConversion
        quitAfterNextConversion = false  // Only the first batch gets quit behavior
        processFiles([url], quitWhenDone: shouldQuit)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        let shouldQuit = quitAfterNextConversion
        quitAfterNextConversion = false  // Only the first batch gets quit behavior
        processFiles(urls, quitWhenDone: shouldQuit)
        NSApp.reply(toOpenOrPrint: .success)
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

        // Also try NSFilenamesPboardType
        if urls.isEmpty, let filenames = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = filenames.map { URL(fileURLWithPath: $0) }
        }

        if urls.isEmpty {
            error.pointee = "No files found" as NSString
            return
        }

        let shouldQuit = quitAfterNextConversion
        quitAfterNextConversion = false
        processFiles(urls, quitWhenDone: shouldQuit)
    }

    // MARK: - Processing

    func processFiles(_ urls: [URL], quitWhenDone: Bool = false) {
        guard !urls.isEmpty else { return }

        // Get paths to bundled resources
        let bundle = Bundle.main
        guard let scriptPath = bundle.path(forResource: "convert", ofType: "sh", inDirectory: "Scripts"),
              let wrapperPath = bundle.path(forResource: "run_with_progress", ofType: "sh", inDirectory: "Scripts"),
              let progressAppPath = bundle.path(forResource: "ADMProgress", ofType: nil) else {
            showError("Required scripts not found in app bundle")
            return
        }

        // Build the file paths argument
        let quotedPaths = urls.map { "'\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }
        let pathString = quotedPaths.joined(separator: " ")

        // Determine flags based on preferences
        let soundCheckFlag = includeSoundCheck ? "soundcheck" : "nosoundcheck"
        let outputFolderFlag = useOutputFolder ? "usefolder" : "samefolder"

        // Build and execute the command
        let command = "\(wrapperPath.shellQuoted()) \(scriptPath.shellQuoted()) \(progressAppPath.shellQuoted()) \(parallelJobs) \(soundCheckFlag) \(outputFolderFlag) \(pathString)"

        // Track active conversions
        activeConversions += 1

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", command]

            do {
                try task.run()
                task.waitUntilExit()  // Wait for conversion to complete

                DispatchQueue.main.async {
                    self.activeConversions -= 1

                    // If app was launched for this conversion and no other conversions active, quit
                    if quitWhenDone && self.activeConversions == 0 {
                        // Small delay to let progress window close gracefully
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NSApp.terminate(nil)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.activeConversions -= 1
                    self.showError("Failed to start conversion: \(error.localizedDescription)")
                }
            }
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

// MARK: - String Extension for Shell Quoting

extension String {
    func shellQuoted() -> String {
        return "'\(self.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
