import Foundation

// MARK: - Individual Clip Instance

struct ClipInstance: Identifiable, Equatable {
    let id = UUID()
    let seconds: Double
    let sample: Int
    let channel: String  // "L" or "R"
    let value: Double
    let decibels: Double

    static func == (lhs: ClipInstance, rhs: ClipInstance) -> Bool {
        lhs.sample == rhs.sample && lhs.channel == rhs.channel
    }
}

// MARK: - AFClip Result Model

struct AFClipResult: Equatable {
    let filename: String
    let filePath: String
    let channels: Int
    let sampleRate: Int
    let leftOnSample: Int
    let leftInterSample: Int
    let rightOnSample: Int
    let rightInterSample: Int
    let hasNoClipping: Bool
    let clipInstances: [ClipInstance]

    var totalClips: Int {
        leftOnSample + leftInterSample + rightOnSample + rightInterSample
    }

    var hasClipping: Bool { totalClips > 0 }

    // Decibel statistics - how much samples exceed clipping point
    var minDecibels: Double? {
        clipInstances.isEmpty ? nil : clipInstances.map(\.decibels).min()
    }

    var maxDecibels: Double? {
        clipInstances.isEmpty ? nil : clipInstances.map(\.decibels).max()
    }

    var avgDecibels: Double? {
        guard !clipInstances.isEmpty else { return nil }
        let sum = clipInstances.reduce(0.0) { $0 + $1.decibels }
        return sum / Double(clipInstances.count)
    }

    var statusText: String {
        if hasNoClipping {
            return "No clipping detected"
        } else if hasClipping {
            return "\(totalClips) clips detected"
        } else {
            return "Analysis complete"
        }
    }

    static func == (lhs: AFClipResult, rhs: AFClipResult) -> Bool {
        lhs.filePath == rhs.filePath &&
        lhs.totalClips == rhs.totalClips &&
        lhs.hasNoClipping == rhs.hasNoClipping
    }
}

// MARK: - AFClip Parser

struct AFClipParser {

    /// Parse afclip output and extract clip counts
    static func parse(output: String, filename: String, filePath: String) -> AFClipResult {
        var leftOn = 0, leftInter = 0, rightOn = 0, rightInter = 0
        var channels = 2
        var sampleRate = 48000
        var noClipping = false
        var clipInstances: [ClipInstance] = []
        var inClipTable = false

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            // Check for "no samples clipped" message
            if line.contains("no samples clipped") {
                noClipping = true
            }

            // Parse file info line: afclip : "file"    2 ch,  48000 Hz, ...
            if line.contains(" ch,") && line.contains(" Hz") {
                if let chMatch = line.range(of: #"(\d+)\s*ch"#, options: .regularExpression) {
                    let chStr = line[chMatch].replacingOccurrences(of: " ch", with: "").replacingOccurrences(of: "ch", with: "")
                    channels = Int(chStr.trimmingCharacters(in: .whitespaces)) ?? 2
                }
                if let hzMatch = line.range(of: #"(\d+)\s*Hz"#, options: .regularExpression) {
                    let hzStr = line[hzMatch].replacingOccurrences(of: " Hz", with: "").replacingOccurrences(of: "Hz", with: "")
                    sampleRate = Int(hzStr.trimmingCharacters(in: .whitespaces)) ?? 48000
                }
            }

            // Detect clip table header
            if line.contains("SECONDS") && line.contains("SAMPLE") && line.contains("CHAN") {
                inClipTable = true
                continue
            }

            // Parse individual clip instances (format: SECONDS SAMPLE CHAN VALUE DECIBELS)
            if inClipTable {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.contains("total clipped") {
                    inClipTable = false
                } else {
                    let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if components.count >= 5,
                       let seconds = Double(components[0]),
                       let sampleDouble = Double(components[1]),  // Parse as Double first (e.g., "643681.00")
                       let value = Double(components[3]),
                       let decibels = Double(components[4]) {
                        // Convert channel from "0"/"1" to "L"/"R"
                        let rawChannel = components[2]
                        let channel = rawChannel == "0" ? "L" : (rawChannel == "1" ? "R" : rawChannel)
                        clipInstances.append(ClipInstance(
                            seconds: seconds,
                            sample: Int(sampleDouble),
                            channel: channel,
                            value: value,
                            decibels: decibels
                        ))
                    }
                }
            }

            // Parse clipping summary lines
            if line.contains("total clipped samples") {
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

                if let onIdx = components.firstIndex(of: "on-sample:"),
                   let interIdx = components.firstIndex(of: "inter-sample:"),
                   onIdx + 1 < components.count,
                   interIdx + 1 < components.count {
                    let onVal = Int(components[onIdx + 1]) ?? 0
                    let interVal = Int(components[interIdx + 1]) ?? 0

                    if line.contains("Left") || line.contains("channel 0") {
                        leftOn = onVal
                        leftInter = interVal
                    } else if line.contains("Right") || line.contains("channel 1") {
                        rightOn = onVal
                        rightInter = interVal
                    }
                }
            }
        }

        return AFClipResult(
            filename: filename,
            filePath: filePath,
            channels: channels,
            sampleRate: sampleRate,
            leftOnSample: leftOn,
            leftInterSample: leftInter,
            rightOnSample: rightOn,
            rightInterSample: rightInter,
            hasNoClipping: noClipping,
            clipInstances: clipInstances
        )
    }

    /// Async version of analyze using proper termination handler
    static func analyzeAsync(file: URL) async -> AFClipResult {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/afclip")
            task.arguments = ["-x", file.path]  // -x = don't write output file

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            // Collect output data asynchronously
            var outputData = Data()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                outputData.append(handle.availableData)
            }

            task.terminationHandler = { _ in
                // Stop reading
                pipe.fileHandleForReading.readabilityHandler = nil

                // Read any remaining data
                outputData.append(pipe.fileHandleForReading.readDataToEndOfFile())

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let result = parse(output: output, filename: file.lastPathComponent, filePath: file.path)
                continuation.resume(returning: result)
            }

            do {
                try task.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: AFClipResult(
                    filename: file.lastPathComponent,
                    filePath: file.path,
                    channels: 0,
                    sampleRate: 0,
                    leftOnSample: 0,
                    leftInterSample: 0,
                    rightOnSample: 0,
                    rightInterSample: 0,
                    hasNoClipping: false,
                    clipInstances: []
                ))
            }
        }
    }
}
