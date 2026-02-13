import Cocoa

// MARK: - Appcast Model

private struct Appcast: Decodable {
    let version: String
    let build: String
    let dmgURL: String
    let releaseNotes: String              // v3.0 compat: single string
    let releaseNotesList: [String]?       // v3.1+: structured list for new update dialog
    let minimumSystemVersion: String
}

// MARK: - UpdateManager

class UpdateManager: NSObject, URLSessionDownloadDelegate {

    private let appcastURL = URL(string: "https://raw.githubusercontent.com/Je55Jackson/ADM-Convert/main/appcast.json")!
    private var isChecking = false
    private var downloadTask: URLSessionDownloadTask?
    private var progressWindow: UpdateProgressWindow?
    private var pendingVersion: String?

    // MARK: - Check for Updates

    func checkForUpdates(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true

        // Append timestamp to bust GitHub CDN cache
        var components = URLComponents(url: appcastURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
        let request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            defer { self.isChecking = false }

            guard let data, error == nil else {
                if userInitiated {
                    DispatchQueue.main.async {
                        self.showErrorAlert()
                    }
                }
                return
            }

            guard let appcast = try? JSONDecoder().decode(Appcast.self, from: data) else {
                if userInitiated {
                    DispatchQueue.main.async {
                        self.showErrorAlert()
                    }
                }
                return
            }

            let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            if self.isNewerVersion(appcast.version, than: localVersion) {
                DispatchQueue.main.async {
                    self.showUpdateAlert(appcast: appcast)
                }
            } else if userInitiated {
                DispatchQueue.main.async {
                    self.showUpToDateAlert(version: localVersion)
                }
            }
        }.resume()
    }

    // MARK: - Version Comparison

    func isNewerVersion(_ remote: String, than local: String) -> Bool {
        var remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        var localParts = local.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(remoteParts.count, localParts.count)
        while remoteParts.count < maxCount { remoteParts.append(0) }
        while localParts.count < maxCount { localParts.append(0) }

        for i in 0..<maxCount {
            if remoteParts[i] > localParts[i] { return true }
            if remoteParts[i] < localParts[i] { return false }
        }
        return false
    }

    // MARK: - Download & Install

    func downloadAndInstall(from url: URL, version: String) {
        pendingVersion = version

        let window = UpdateProgressWindow()
        window.onCancel = { [weak self] in
            self?.downloadTask?.cancel()
            self?.downloadTask = nil
        }
        window.show(version: version)
        progressWindow = window

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    // URLSessionDownloadDelegate - progress

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            self?.progressWindow?.updateProgress(fraction)
        }
    }

    // URLSessionDownloadDelegate - completion

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Check HTTP status code
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            DispatchQueue.main.async { [weak self] in
                self?.progressWindow?.close()
                self?.progressWindow = nil
                self?.showDownloadError("Server returned status \(httpResponse.statusCode).")
            }
            return
        }

        let dmgPath = FileManager.default.temporaryDirectory.appendingPathComponent("JessOS_ADM_Update.dmg")
        try? FileManager.default.removeItem(at: dmgPath)
        do {
            try FileManager.default.moveItem(at: location, to: dmgPath)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.progressWindow?.close()
                self?.progressWindow = nil
                self?.showDownloadError("Could not save update file.")
            }
            return
        }

        // Verify file is a reasonable size (DMG should be > 100KB)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: dmgPath.path)[.size] as? Int) ?? 0
        guard fileSize > 100_000 else {
            try? FileManager.default.removeItem(at: dmgPath)
            DispatchQueue.main.async { [weak self] in
                self?.progressWindow?.close()
                self?.progressWindow = nil
                self?.showDownloadError("Downloaded file is invalid (\(fileSize) bytes).")
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.progressWindow?.close()
            self?.progressWindow = nil
            self?.installUpdate(dmgPath: dmgPath)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async { [weak self] in
            self?.progressWindow?.close()
            self?.progressWindow = nil
            self?.showDownloadError(error.localizedDescription)
        }
    }

    // MARK: - Install Update

    private func installUpdate(dmgPath: URL) {
        let mountPoint = "/tmp/jessos_update_mount"

        // Clean up any stale mount point from a previous attempt
        if FileManager.default.fileExists(atPath: mountPoint) {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint, "-force"]
            detach.standardOutput = FileHandle.nullDevice
            detach.standardError = FileHandle.nullDevice
            try? detach.run()
            detach.waitUntilExit()
            try? FileManager.default.removeItem(atPath: mountPoint)
        }

        // Mount the DMG
        let mount = Process()
        mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mount.arguments = ["attach", dmgPath.path, "-nobrowse", "-noverify", "-mountpoint", mountPoint]
        mount.standardOutput = FileHandle.nullDevice
        mount.standardError = FileHandle.nullDevice

        do {
            try mount.run()
            mount.waitUntilExit()
        } catch {
            showDownloadError("Could not mount the update image.")
            return
        }

        guard mount.terminationStatus == 0 else {
            showDownloadError("Failed to mount update image (exit code \(mount.terminationStatus)).")
            return
        }

        // Find the .app inside the mounted volume
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mountPoint),
              let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            // Cleanup on failure
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint]
            try? detach.run()
            showDownloadError("Could not find app in update image.")
            return
        }

        let currentAppPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        // Write the updater script
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done
        rm -rf "\(currentAppPath)"
        cp -R "\(mountPoint)/\(appName)" "\(currentAppPath)"
        hdiutil detach "\(mountPoint)"
        rm -f "\(dmgPath.path)" "/tmp/jessos_updater.sh"
        open "\(currentAppPath)"
        """

        let scriptPath = "/tmp/jessos_updater.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            showDownloadError("Could not prepare update installer.")
            return
        }

        // Launch the updater script and terminate
        let updater = Process()
        updater.executableURL = URL(fileURLWithPath: "/bin/bash")
        updater.arguments = [scriptPath]
        updater.standardOutput = FileHandle.nullDevice
        updater.standardError = FileHandle.nullDevice

        do {
            try updater.run()
        } catch {
            showDownloadError("Could not launch update installer.")
            return
        }

        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func showUpdateAlert(appcast: Appcast) {
        let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Software Update"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))

        // Title
        let title = NSTextField(labelWithString: "JessOS ADM Convert v\(appcast.version)")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        // Subtitle
        let subtitle = NSTextField(labelWithString: "You're currently running v\(localVersion)")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(subtitle)

        // "What's New" label
        let whatsNewLabel = NSTextField(labelWithString: "What's New:")
        whatsNewLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        whatsNewLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(whatsNewLabel)

        // Release notes: prefer structured list, fall back to single string
        let notes = appcast.releaseNotesList ?? [appcast.releaseNotes]
        let notesText = notes.enumerated().map { i, note in
            "\(i + 1). \(note)"
        }.joined(separator: "\n")

        let notesLabel = NSTextField(wrappingLabelWithString: notesText)
        notesLabel.font = NSFont.systemFont(ofSize: 13)
        notesLabel.isSelectable = true
        notesLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(notesLabel)

        // Buttons
        let laterButton = NSButton(title: "Later", target: nil, action: nil)
        laterButton.bezelStyle = .rounded
        laterButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(laterButton)

        let downloadButton = NSButton(title: "Download & Install", target: nil, action: nil)
        downloadButton.bezelStyle = .rounded
        downloadButton.keyEquivalent = "\r"
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(downloadButton)

        window.contentView = content

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),

            whatsNewLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            whatsNewLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),

            notesLabel.topAnchor.constraint(equalTo: whatsNewLabel.bottomAnchor, constant: 8),
            notesLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            notesLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            downloadButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            downloadButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            laterButton.trailingAnchor.constraint(equalTo: downloadButton.leadingAnchor, constant: -8),
            laterButton.centerYAnchor.constraint(equalTo: downloadButton.centerYAnchor),
        ])

        // Button actions via closures using a helper
        let handler = UpdateAlertHandler(window: window, appcast: appcast, manager: self)
        downloadButton.target = handler
        downloadButton.action = #selector(UpdateAlertHandler.downloadClicked)
        laterButton.target = handler
        laterButton.action = #selector(UpdateAlertHandler.laterClicked)

        // Prevent handler from being deallocated while window is open
        objc_setAssociatedObject(window, "handler", handler, .OBJC_ASSOCIATION_RETAIN)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showUpToDateAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "JessOS ADM Convert \(version) is the current version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not check for updates. Please check your internet connection."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showDownloadError(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = "Update Failed"
        alert.informativeText = "Could not download or install the update.\n\n\(detail)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Update Alert Button Handler

private class UpdateAlertHandler: NSObject {
    let window: NSWindow
    let dmgURL: String
    let version: String
    weak var manager: UpdateManager?

    init(window: NSWindow, appcast: Appcast, manager: UpdateManager) {
        self.window = window
        self.dmgURL = appcast.dmgURL
        self.version = appcast.version
        self.manager = manager
    }

    @objc func downloadClicked() {
        window.close()
        guard let url = URL(string: dmgURL) else { return }
        manager?.downloadAndInstall(from: url, version: version)
    }

    @objc func laterClicked() {
        window.close()
    }
}
