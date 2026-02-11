import Cocoa

// Native AppKit progress window for headless mode (dock drops)
// Uses plain AppKit instead of SwiftUI to avoid memory management issues

class HeadlessProgressController: NSObject {
    private var window: NSWindow?
    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var fileLabel: NSTextField!

    private var totalFiles = 0
    private var completedFiles = 0
    private var quitWhenDone = false
    private let counterLock = NSLock()

    // User preferences
    private var includeSoundCheck: Bool {
        UserDefaults.standard.bool(forKey: "includeSoundCheck")
    }
    private var useOutputFolder: Bool {
        UserDefaults.standard.bool(forKey: "useOutputFolder")
    }

    func start(urls: [URL], quitWhenDone: Bool) {
        self.quitWhenDone = quitWhenDone

        // Collect audio files
        let audioFiles = collectAudioFiles(from: urls)

        guard !audioFiles.isEmpty else {
            if quitWhenDone {
                NSApp.terminate(nil)
            }
            return
        }

        totalFiles = audioFiles.count
        completedFiles = 0

        // Show window on main thread
        DispatchQueue.main.async {
            self.showWindow()
            self.updateStatus("Converting \(self.totalFiles) file\(self.totalFiles == 1 ? "" : "s")...")
        }

        // Start processing on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            self.processFiles(audioFiles)
        }
    }

    private func showWindow() {
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Create gradient background view
        let contentView = GradientView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true

        // Status label
        statusLabel = NSTextField(labelWithString: "Preparing...")
        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 20, y: 60, width: 280, height: 20)
        contentView.addSubview(statusLabel)

        // Progress bar
        progressBar = NSProgressIndicator(frame: NSRect(x: 20, y: 40, width: 280, height: 8))
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0

        // Style the progress bar
        progressBar.wantsLayer = true
        progressBar.layer?.cornerRadius = 4
        progressBar.layer?.masksToBounds = true

        contentView.addSubview(progressBar)

        // File label
        fileLabel = NSTextField(labelWithString: "")
        fileLabel.font = NSFont.systemFont(ofSize: 11)
        fileLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        fileLabel.alignment = .center
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.frame = NSRect(x: 20, y: 15, width: 280, height: 16)
        contentView.addSubview(fileLabel)

        window.contentView = contentView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating

        // Position above dock
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 160
            let y = screenFrame.minY + 80
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func updateStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusLabel?.stringValue = text
        }
    }

    private func updateFile(_ filename: String) {
        DispatchQueue.main.async {
            self.fileLabel?.stringValue = filename
        }
    }

    private func updateProgress(_ value: Double) {
        DispatchQueue.main.async {
            self.progressBar?.doubleValue = value
        }
    }

    private func processFiles(_ files: [URL]) {
        // Match shell script's parallelism (12 concurrent conversions)
        let maxConcurrent = 12
        let queue = DispatchQueue(label: "com.jessos.adm-convert.headless", attributes: .concurrent)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: maxConcurrent)

        for file in files {
            group.enter()
            semaphore.wait()

            queue.async {
                self.processFile(file)
                semaphore.signal()
                group.leave()
            }
        }

        group.wait()

        // All done
        DispatchQueue.main.async {
            self.updateStatus("Complete!")
            self.updateProgress(1.0)

            // Close after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.close()
                if self.quitWhenDone {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func processFile(_ file: URL) {
        let filename = file.lastPathComponent
        updateFile(filename)

        // Convert WAV/AIFF to M4A
        let ext = file.pathExtension.lowercased()
        if ext == "wav" || ext == "aif" || ext == "aiff" {
            do {
                _ = try convertFile(file)
            } catch {
                print("HeadlessProgress: ERROR converting \(filename): \(error)")
            }
        } else {
            print("HeadlessProgress: SKIP \(filename) - not a convertible format")
        }

        // Update progress (thread-safe counter increment)
        counterLock.lock()
        completedFiles += 1
        let currentCompleted = completedFiles
        let total = totalFiles
        counterLock.unlock()

        let progress = Double(currentCompleted) / Double(total)
        updateProgress(progress)
        updateStatus("Converting \(currentCompleted)/\(total)...")
    }

    private func convertFile(_ inputURL: URL) throws -> URL {
        let filename = inputURL.deletingPathExtension().lastPathComponent
        let outputDir: URL

        if useOutputFolder {
            let parentDir = inputURL.deletingLastPathComponent()
            outputDir = parentDir.appendingPathComponent("M4A")
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } else {
            outputDir = inputURL.deletingLastPathComponent()
        }

        let outputURL = outputDir.appendingPathComponent(filename + ".m4a")

        if includeSoundCheck {
            try convertWithSoundCheck(input: inputURL, output: outputURL)
        } else {
            try convertDirect(input: inputURL, output: outputURL)
        }

        return outputURL
    }

    private func convertWithSoundCheck(input: URL, output: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JessOS_ADM_Convert")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let cafPath = tempDir.appendingPathComponent(UUID().uuidString + ".caf")

        let sampleRate = getSampleRate(input)
        let needsResample = sampleRate > 48000

        // Pass 1: Generate SoundCheck data
        var pass1Args = [input.path]
        if needsResample {
            pass1Args += ["-d", "LEF32@48000", "-f", "caff", "--soundcheck-generate", "--src-complexity", "bats", "-r", "127"]
        } else {
            pass1Args += ["-d", "0", "-f", "caff", "--soundcheck-generate"]
        }
        pass1Args.append(cafPath.path)
        try runAfconvert(pass1Args)

        // Pass 2: Encode to AAC with SoundCheck
        let pass2Args = [
            cafPath.path,
            "-d", "aac",
            "-f", "m4af",
            "-u", "pgcm", "2",
            "--soundcheck-read",
            "-b", "256000",
            "-q", "127",
            "-s", "2",
            output.path
        ]
        try runAfconvert(pass2Args)

        // Clean up temp file
        try? FileManager.default.removeItem(at: cafPath)
    }

    private func convertDirect(input: URL, output: URL) throws {
        let sampleRate = getSampleRate(input)
        let needsResample = sampleRate > 48000

        var args = [input.path]
        args += ["-d", "aac", "-f", "m4af", "-u", "pgcm", "2", "-b", "256000", "-q", "127", "-s", "2"]
        if needsResample {
            args += ["-r", "127", "--src-complexity", "bats"]
        }
        args.append(output.path)
        try runAfconvert(args)
    }

    private func runAfconvert(_ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        task.arguments = arguments
        task.standardError = FileHandle.nullDevice

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw NSError(
                domain: "HeadlessProgress",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "afconvert failed with status \(task.terminationStatus)"]
            )
        }
    }

    private func getSampleRate(_ url: URL) -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/afinfo")
        task.arguments = [url.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            for line in output.components(separatedBy: "\n") {
                if line.contains("sample rate:") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let rateStr = parts[1].trimmingCharacters(in: .whitespaces)
                        if let rate = Double(rateStr) {
                            return Int(rate)
                        }
                    }
                }
            }
        } catch {
            print("Error getting sample rate: \(error)")
        }

        return 48000 // Default
    }

    private func collectAudioFiles(from urls: [URL]) -> [URL] {
        var audioFiles: [URL] = []
        let fm = FileManager.default
        let validExtensions = ["wav", "aif", "aiff"]

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator {
                        if validExtensions.contains(fileURL.pathExtension.lowercased()) {
                            audioFiles.append(fileURL)
                        }
                    }
                }
            } else if validExtensions.contains(url.pathExtension.lowercased()) {
                audioFiles.append(url)
            }
        }

        return audioFiles
    }

    func close() {
        window?.close()
        window = nil
    }
}

// Custom gradient view for the progress window background
class GradientView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(
            colors: [
                NSColor(red: 0.95, green: 0.4, blue: 0.2, alpha: 1.0),
                NSColor(red: 0.7, green: 0.15, blue: 0.3, alpha: 1.0)
            ]
        )
        gradient?.draw(in: bounds, angle: -45)
    }
}
