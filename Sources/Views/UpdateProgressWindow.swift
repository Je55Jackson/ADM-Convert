import Cocoa

class UpdateProgressWindow: NSObject {
    let window: NSWindow
    let progressBar: NSProgressIndicator
    let statusLabel: NSTextField
    let cancelButton: NSButton
    var onCancel: (() -> Void)?

    private var currentVersion: String = ""

    override init() {
        // Create window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Software Update"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 130))

        // Status label
        statusLabel = NSTextField(labelWithString: "Downloading update...")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(statusLabel)

        // Progress bar
        progressBar = NSProgressIndicator()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        contentView.addSubview(progressBar)

        // Cancel button
        cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.bezelStyle = .rounded
        contentView.addSubview(cancelButton)

        window.contentView = contentView

        super.init()

        // Wire cancel button
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)

        // Auto Layout constraints
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            progressBar.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            progressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            cancelButton.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 12),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @objc func cancelClicked() {
        onCancel?()
        window.close()
    }

    func show(version: String) {
        currentVersion = version
        statusLabel.stringValue = "Downloading version \(version)..."
        progressBar.doubleValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateProgress(_ fraction: Double) {
        progressBar.doubleValue = fraction * 100
        let percent = Int(fraction * 100)
        statusLabel.stringValue = "Downloading version \(currentVersion)... (\(percent)%)"
    }

    func close() {
        window.close()
    }
}
