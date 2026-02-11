import Cocoa
import QuartzCore

// MARK: - Gradient Background View

class GradientBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // Orange/red gradient matching main app
        let topColor = NSColor(red: 0.95, green: 0.4, blue: 0.2, alpha: 1.0)
        let bottomColor = NSColor(red: 0.7, green: 0.15, blue: 0.3, alpha: 1.0)

        let gradient = NSGradient(starting: topColor, ending: bottomColor)
        gradient?.draw(in: bounds, angle: -45)
    }

    override var isOpaque: Bool { true }
}

// MARK: - ProgressWindow

class ProgressWindow: NSWindow {
    let backgroundView: GradientBackgroundView
    let statusLabel: NSTextField
    let fileLabel: NSTextField
    let progressBar: NSProgressIndicator
    let versionLabel: NSTextField

    init() {
        // Window size
        let windowWidth: CGFloat = 380
        let windowHeight: CGFloat = 120

        // Calculate window position: centered horizontally, above the dock
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowX = screenFrame.midX - windowWidth / 2
        let windowY = screenFrame.minY + 20  // 20px above dock area

        // Create background
        backgroundView = GradientBackgroundView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 16
        backgroundView.layer?.masksToBounds = true

        // Create UI elements with white styling
        statusLabel = NSTextField(labelWithString: "Preparing...")
        statusLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .center

        fileLabel = NSTextField(labelWithString: "")
        fileLabel.font = NSFont.systemFont(ofSize: 12)
        fileLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        fileLabel.alignment = .center
        fileLabel.lineBreakMode = .byTruncatingMiddle

        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        progressBar.wantsLayer = true
        progressBar.layer?.cornerRadius = 3

        // White tint for progress bar
        if let whiteFilter = CIFilter(name: "CIFalseColor") {
            whiteFilter.setDefaults()
            whiteFilter.setValue(CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3), forKey: "inputColor0")
            whiteFilter.setValue(CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9), forKey: "inputColor1")
            progressBar.contentFilters = [whiteFilter]
        }

        versionLabel = NSTextField(labelWithString: "JessOS ADM Convert")
        versionLabel.font = NSFont.systemFont(ofSize: 10)
        versionLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        versionLabel.alignment = .center

        super.init(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.isReleasedWhenClosed = false

        setupUI()
    }

    private func setupUI() {
        self.contentView = backgroundView

        let padding: CGFloat = 20
        let elementHeight: CGFloat = 20
        let spacing: CGFloat = 8
        let contentWidth = backgroundView.bounds.width - (padding * 2)

        // Layout from top to bottom
        statusLabel.frame = NSRect(
            x: padding,
            y: backgroundView.bounds.height - padding - elementHeight,
            width: contentWidth,
            height: elementHeight
        )

        progressBar.frame = NSRect(
            x: padding,
            y: statusLabel.frame.minY - spacing - 6,
            width: contentWidth,
            height: 6
        )

        fileLabel.frame = NSRect(
            x: padding,
            y: progressBar.frame.minY - spacing - elementHeight,
            width: contentWidth,
            height: elementHeight
        )

        versionLabel.frame = NSRect(
            x: padding,
            y: 8,
            width: contentWidth,
            height: 14
        )

        backgroundView.addSubview(statusLabel)
        backgroundView.addSubview(progressBar)
        backgroundView.addSubview(fileLabel)
        backgroundView.addSubview(versionLabel)
    }

    func updateWindow(current: Int, total: Int, filename: String) {
        DispatchQueue.main.async {
            self.statusLabel.stringValue = "Converting \(current) of \(total) file\(total == 1 ? "" : "s")"
            self.progressBar.doubleValue = Double(current) / Double(total) * 100
            self.fileLabel.stringValue = filename
        }
    }

    func showComplete(total: Int) {
        DispatchQueue.main.async {
            self.statusLabel.stringValue = "Complete! Converted \(total) file\(total == 1 ? "" : "s")"
            self.fileLabel.stringValue = ""
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
                    self.window.statusLabel.stringValue = "Converting 0 of \(self.total) file\(self.total == 1 ? "" : "s")"
                }
            } else if trimmed.hasPrefix("START:") {
                let filename = String(trimmed.dropFirst(6))
                DispatchQueue.main.async {
                    self.window.fileLabel.stringValue = filename
                }
            } else if trimmed.hasPrefix("FILE:") {
                current += 1
                let filename = String(trimmed.dropFirst(5))
                window.updateWindow(current: current, total: total, filename: filename)
            } else if trimmed == "DONE" {
                window.showComplete(total: current)

                if debugKeepOpen {
                    DispatchQueue.main.async {
                        self.window.statusLabel.stringValue = "DEBUG MODE: Window kept open"
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }

        // stdin closed without DONE
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
