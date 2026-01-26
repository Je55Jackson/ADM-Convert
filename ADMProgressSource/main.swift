import Cocoa
import QuartzCore

// MARK: - ProgressWindow
class ProgressWindow: NSWindow {
    let statusLabel: NSTextField
    let fileLabel: NSTextField
    let progressBar: NSProgressIndicator
    let versionLabel: NSTextField
    let audioIcon: NSImageView

    init() {
        // Window size
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 140

        // Create UI elements
        statusLabel = NSTextField(labelWithString: "Converting...")
        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.alignment = .center

        fileLabel = NSTextField(labelWithString: "")
        fileLabel.font = NSFont.systemFont(ofSize: 11)
        fileLabel.textColor = .secondaryLabelColor
        fileLabel.alignment = .left
        fileLabel.lineBreakMode = .byTruncatingMiddle

        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = true
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0

        // Apply purple tint using color filter
        if let purpleFilter = CIFilter(name: "CIFalseColor") {
            purpleFilter.setDefaults()
            purpleFilter.setValue(CIColor(red: 0.55, green: 0.36, blue: 0.76, alpha: 1.0), forKey: "inputColor0")
            purpleFilter.setValue(CIColor(red: 0.75, green: 0.65, blue: 0.88, alpha: 1.0), forKey: "inputColor1")
            progressBar.contentFilters = [purpleFilter]
        }

        versionLabel = NSTextField(labelWithString: "JessOS ADM Convert v1 :: Optimized for Apple Silicone Native")
        versionLabel.font = NSFont.systemFont(ofSize: 9)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center

        // Load audio icon at original size (32x32)
        audioIcon = NSImageView()
        let executablePath = Bundle.main.executablePath ?? ""
        let resourcesPath = (executablePath as NSString).deletingLastPathComponent
        let iconPath = (resourcesPath as NSString).appendingPathComponent("audio-icon.svg")
        if let image = NSImage(contentsOfFile: iconPath) {
            audioIcon.image = image
        }
        audioIcon.imageScaling = .scaleProportionallyUpOrDown

        // Calculate window position (center of screen)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowX = screenFrame.midX - windowWidth / 2
        let windowY = screenFrame.midY - windowHeight / 2

        super.init(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "JessOS ADM Convert"
        self.isReleasedWhenClosed = false
        self.level = .floating

        setupUI()
    }

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        let padding: CGFloat = 20
        let elementHeight: CGFloat = 20
        let spacing: CGFloat = 8
        let iconSize: CGFloat = 32

        // Layout from top to bottom
        let contentWidth = contentView.bounds.width - (padding * 2)

        statusLabel.frame = NSRect(
            x: padding,
            y: contentView.bounds.height - padding - elementHeight,
            width: contentWidth,
            height: elementHeight
        )

        progressBar.frame = NSRect(
            x: padding,
            y: statusLabel.frame.minY - spacing - elementHeight,
            width: contentWidth,
            height: elementHeight
        )

        // Audio icon + file label row - initial position (will be centered dynamically)
        let iconRowY = progressBar.frame.minY - spacing - iconSize

        audioIcon.frame = NSRect(
            x: 0,
            y: iconRowY,
            width: iconSize,
            height: iconSize
        )

        fileLabel.frame = NSRect(
            x: 0,
            y: iconRowY + (iconSize - elementHeight) / 2 - 2,
            width: 300,
            height: elementHeight
        )
        fileLabel.alignment = .left

        versionLabel.frame = NSRect(
            x: padding,
            y: 4,
            width: contentWidth,
            height: 14
        )

        contentView.addSubview(statusLabel)
        contentView.addSubview(progressBar)
        contentView.addSubview(audioIcon)
        contentView.addSubview(fileLabel)
        contentView.addSubview(versionLabel)
    }

    func centerIconRow(filename: String) {
        guard let contentView = self.contentView else { return }

        let iconSize: CGFloat = 32
        let iconLabelGap: CGFloat = 8
        let maxTextWidth: CGFloat = 280

        // Calculate text width
        let attributes: [NSAttributedString.Key: Any] = [.font: fileLabel.font!]
        var textWidth = (filename as NSString).size(withAttributes: attributes).width
        textWidth = min(textWidth, maxTextWidth) // Cap at max width

        // Total width of icon + gap + text
        let totalWidth = iconSize + iconLabelGap + textWidth
        let startX = (contentView.bounds.width - totalWidth) / 2

        // Update positions
        audioIcon.frame.origin.x = startX
        fileLabel.frame.origin.x = startX + iconSize + iconLabelGap
        fileLabel.frame.size.width = textWidth + 10 // Small buffer
    }

    func updateWindow(current: Int, total: Int, filename: String) {
        DispatchQueue.main.async {
            if total > 0 {
                self.statusLabel.stringValue = "Converting \(current) of \(total) files"
                self.progressBar.isIndeterminate = false
                self.progressBar.doubleValue = Double(current) / Double(total) * 100
            } else {
                // Streaming mode - no total known yet
                self.statusLabel.stringValue = "Converted \(current) file\(current == 1 ? "" : "s")..."
                if !self.progressBar.isIndeterminate {
                    self.progressBar.isIndeterminate = true
                    self.progressBar.startAnimation(nil)
                }
            }
            self.fileLabel.stringValue = filename
            self.audioIcon.isHidden = filename.isEmpty
            self.centerIconRow(filename: filename)
        }
    }

    func showComplete(total: Int) {
        DispatchQueue.main.async {
            self.statusLabel.stringValue = "Complete! Converted \(total) file\(total == 1 ? "" : "s")"
            self.fileLabel.stringValue = ""
            self.audioIcon.isHidden = true
            self.progressBar.doubleValue = 100
        }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: ProgressWindow!
    var total: Int = 0
    var current: Int = 0

    // SET THIS TO TRUE TO KEEP WINDOW OPEN FOR UI TWEAKING
    let debugKeepOpen: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = ProgressWindow()
        window.makeKeyAndOrderFront(nil)
        window.progressBar.startAnimation(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Read from stdin in background
        DispatchQueue.global(qos: .userInitiated).async {
            self.processInput()
        }
    }

    func processInput() {
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("TOTAL:") {
                let value = String(trimmed.dropFirst(6))
                total = Int(value) ?? 0
                DispatchQueue.main.async {
                    self.window.progressBar.maxValue = Double(self.total)
                }
            } else if trimmed.hasPrefix("START:") {
                let filename = String(trimmed.dropFirst(6))
                DispatchQueue.main.async {
                    self.window.fileLabel.stringValue = filename
                    self.window.audioIcon.isHidden = false
                    self.window.centerIconRow(filename: filename)
                }
            } else if trimmed.hasPrefix("FILE:") {
                current += 1
                let filename = String(trimmed.dropFirst(5))
                window.updateWindow(current: current, total: total, filename: filename)
            } else if trimmed == "DONE" {
                window.showComplete(total: current)

                if debugKeepOpen {
                    // Keep window open for UI debugging
                    DispatchQueue.main.async {
                        self.window.statusLabel.stringValue = "DEBUG MODE: Window kept open for UI tweaking"
                    }
                } else {
                    // Normal behavior: close after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }

        // stdin closed without DONE - keep open if debugging
        if !debugKeepOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !debugKeepOpen
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
