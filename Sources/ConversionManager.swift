import SwiftUI
import Combine

// MARK: - Conversion Error

enum ConversionError: LocalizedError {
    case afconvertFailed(String)
    case fileNotFound(String)
    case outputDirectoryFailed

    var errorDescription: String? {
        switch self {
        case .afconvertFailed(let msg): return "Conversion failed: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .outputDirectoryFailed: return "Could not create output directory"
        }
    }
}

// MARK: - Conversion Manager

class ConversionManager: ObservableObject {
    @AppStorage("includeSoundCheck") var includeSoundCheck: Bool = true
    @AppStorage("useOutputFolder") var useOutputFolder: Bool = false

    @Published var isConverting = false
    @Published var activeConversions = 0
    @Published var fileItems: [FileConversionItem] = []

    let parallelJobs = "12"
    private let maxConcurrentConversions = 4
    private let tempDir = "/tmp/JessOS_ADM_Convert"

    // MARK: - Window Mode: Add Files

    func addFiles(_ urls: [URL]) {
        let audioFiles = collectAudioFiles(from: urls)
        let newItems = audioFiles.map { FileConversionItem(url: $0) }
        DispatchQueue.main.async {
            self.fileItems.append(contentsOf: newItems)
        }
    }

    func clearFiles() {
        guard !isConverting else { return }
        DispatchQueue.main.async {
            self.fileItems.removeAll()
        }
    }

    // MARK: - Window Mode: Start Processing

    func startProcessing() {
        guard !isConverting else { return }

        let pendingItems = fileItems.filter {
            if case .pending = $0.status { return true }
            return false
        }

        guard !pendingItems.isEmpty else { return }

        DispatchQueue.main.async {
            self.isConverting = true
        }

        // Create temp directory
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        Task {
            await withTaskGroup(of: Void.self) { group in
                var runningCount = 0

                for item in pendingItems {
                    // Wait if we have max concurrent conversions
                    while runningCount >= maxConcurrentConversions {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                        runningCount = pendingItems.filter { $0.isProcessing }.count
                    }

                    runningCount += 1

                    group.addTask {
                        await self.processItem(item)
                    }
                }

                await group.waitForAll()
            }

            await MainActor.run {
                self.isConverting = false
            }
        }
    }

    // MARK: - Process Single Item

    private func processItem(_ item: FileConversionItem) async {
        do {
            let fileToAnalyze: URL

            if item.isM4A {
                // M4A files: skip conversion, analyze directly
                await MainActor.run {
                    item.status = .analyzing
                }
                fileToAnalyze = item.sourceURL
            } else {
                // WAV/AIFF files: convert first
                await MainActor.run {
                    item.status = .converting(progress: 0.0)
                }

                let outputURL = try await convertFile(item)

                await MainActor.run {
                    item.outputURL = outputURL
                    item.status = .analyzing
                }
                fileToAnalyze = outputURL
            }

            // Run afclip analysis
            let clipResult = await AFClipParser.analyzeAsync(file: fileToAnalyze)

            await MainActor.run {
                item.clipResult = clipResult
                item.status = .completed(clipResult)
            }

        } catch {
            await MainActor.run {
                item.status = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Convert File (Direct afconvert)

    private func convertFile(_ item: FileConversionItem) async throws -> URL {
        let inputURL = item.sourceURL

        // Determine output directory
        let outputDir: URL
        if useOutputFolder {
            outputDir = inputURL.deletingLastPathComponent().appendingPathComponent("M4A")
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } else {
            outputDir = inputURL.deletingLastPathComponent()
        }

        // Generate unique output filename
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        var outputURL = outputDir.appendingPathComponent("\(baseName).m4a")
        var counter = 1
        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = outputDir.appendingPathComponent("\(baseName)-\(counter).m4a")
            counter += 1
        }

        // Check sample rate for resampling
        let sampleRate = await getSampleRate(for: inputURL)
        let needsResample = sampleRate > 48000

        // Always use SoundCheck in window mode (two-pass conversion)
        await MainActor.run {
            item.status = .converting(progress: 0.25)
        }

        // Pass 1: Convert to CAF with SoundCheck generation
        let cafURL = URL(fileURLWithPath: "\(tempDir)/\(UUID().uuidString).caf")
        try await runAfconvert(pass1Arguments(input: inputURL, output: cafURL, needsResample: needsResample))

        await MainActor.run {
            item.status = .converting(progress: 0.75)
        }

        // Pass 2: Convert CAF to AAC with SoundCheck read
        try await runAfconvert(pass2Arguments(input: cafURL, output: outputURL))

        // Clean up temp CAF file
        try? FileManager.default.removeItem(at: cafURL)

        return outputURL
    }

    // MARK: - afconvert Arguments

    private func pass1Arguments(input: URL, output: URL, needsResample: Bool) -> [String] {
        var args = [input.path]

        if needsResample {
            args += ["-d", "LEF32@48000", "-f", "caff", "--soundcheck-generate", "--src-complexity", "bats", "-r", "127"]
        } else {
            args += ["-d", "0", "-f", "caff", "--soundcheck-generate"]
        }

        args.append(output.path)
        return args
    }

    private func pass2Arguments(input: URL, output: URL) -> [String] {
        return [
            input.path,
            "-d", "aac",
            "-f", "m4af",
            "-u", "pgcm", "2",
            "--soundcheck-read",
            "-b", "256000",
            "-q", "127",
            "-s", "2",
            output.path
        ]
    }

    // MARK: - Run afconvert

    private func runAfconvert(_ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            task.arguments = arguments

            let errorPipe = Pipe()
            task.standardError = errorPipe

            task.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: ConversionError.afconvertFailed(errorString))
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Get Sample Rate

    private func getSampleRate(for url: URL) async -> Int {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/afinfo")
            task.arguments = [url.path]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                // Parse sample rate from afinfo output
                for line in output.components(separatedBy: .newlines) {
                    if line.contains("sample rate:") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count >= 2 {
                            let rateStr = parts[1].trimmingCharacters(in: .whitespaces)
                            if let rate = Double(rateStr) {
                                continuation.resume(returning: Int(rate))
                                return
                            }
                        }
                    }
                }
                continuation.resume(returning: 48000) // Default
            } catch {
                continuation.resume(returning: 48000) // Default on error
            }
        }
    }

    // MARK: - Collect Audio Files

    private func collectAudioFiles(from urls: [URL]) -> [URL] {
        var audioFiles: [URL] = []
        let fm = FileManager.default
        let validExtensions = ["wav", "aif", "aiff", "m4a"]  // M4A for analyze-only

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

    // MARK: - Headless Mode (External Progress Popup)

    func processFiles(_ urls: [URL], quitWhenDone: Bool = false) {
        guard !urls.isEmpty else { return }

        let bundle = Bundle.main
        guard let scriptPath = bundle.path(forResource: "convert", ofType: "sh", inDirectory: "Scripts"),
              let wrapperPath = bundle.path(forResource: "run_with_progress", ofType: "sh", inDirectory: "Scripts"),
              let progressAppPath = bundle.path(forResource: "ADMProgress", ofType: nil) else {
            showError("Required scripts not found in app bundle")
            return
        }

        let quotedPaths = urls.map { "'\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }
        let pathString = quotedPaths.joined(separator: " ")

        let soundCheckFlag = includeSoundCheck ? "soundcheck" : "nosoundcheck"
        let outputFolderFlag = useOutputFolder ? "usefolder" : "samefolder"

        let command = "\(wrapperPath.shellQuoted()) \(scriptPath.shellQuoted()) \(progressAppPath.shellQuoted()) \(parallelJobs) \(soundCheckFlag) \(outputFolderFlag) \(pathString)"

        DispatchQueue.main.async {
            self.activeConversions += 1
            self.isConverting = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", command]

            do {
                try task.run()
                task.waitUntilExit()

                DispatchQueue.main.async {
                    self.activeConversions -= 1
                    self.isConverting = self.activeConversions > 0

                    if quitWhenDone && self.activeConversions == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NSApp.terminate(nil)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.activeConversions -= 1
                    self.isConverting = self.activeConversions > 0
                    self.showError("Failed to start conversion: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Error Handling

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.runModal()
        }
    }
}

// shellQuoted() extension is in AppDelegate.swift
