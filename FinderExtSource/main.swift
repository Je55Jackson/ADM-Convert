import Cocoa
import FinderSync

// Finder Sync extension: adds "Convert to M4A" items to Finder's right-click menu.
// Does no conversion itself — hands the selected files to the main app via the
// admconvert:// URL scheme and the app's headless conversion path.
//
// Known platform limit: Finder does NOT route Finder Sync menus inside File
// Provider domains (Dropbox, Google Drive, Synology Drive under
// ~/Library/CloudStorage) — verified empirically; menu(for:) is never called
// there even when the domain root is in directoryURLs. The Quick Actions the
// main app installs into ~/Library/Services cover those locations instead.

@objc(FinderSync)
class FinderSync: FIFinderSync {

    private let audioExtensions: Set<String> = ["wav", "wave", "aif", "aiff"]

    // The appex lives at <App>.app/Contents/PlugIns/ADMConvertFinder.appex —
    // borrow the host app's icon instead of bundling a duplicate copy.
    private lazy var menuIcon: NSImage? = {
        let iconURL = Bundle.main.bundleURL
            .deletingLastPathComponent()  // PlugIns/
            .deletingLastPathComponent()  // Contents/
            .appendingPathComponent("Resources/AppIcon.icns")
        guard let image = NSImage(contentsOf: iconURL) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }()

    private var rescanTimer: DispatchSourceTimer?

    override init() {
        super.init()
        updateMonitoredDirectories()

        // Volumes mount and unmount while we're running — rescan periodically.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in self?.updateMonitoredDirectories() }
        timer.resume()
        rescanTimer = timer
    }

    // Monitor everything so the menu is available anywhere in Finder — we draw
    // no badges, so this costs nothing beyond menu callbacks. Monitoring "/"
    // only covers the boot volume: external drives and network shares under
    // /Volumes must each be monitored explicitly or the menu won't appear
    // there. mountedVolumeURLs uses the mount table, so no sandbox exception
    // is needed to enumerate them.
    private func updateMonitoredDirectories() {
        var dirs: Set<URL> = [URL(fileURLWithPath: "/")]

        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            for volume in volumes where volume.path.hasPrefix("/Volumes/") {
                dirs.insert(volume)
            }
        }

        let controller = FIFinderSyncController.default()
        if controller.directoryURLs != dirs {
            controller.directoryURLs = dirs
        }
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        guard selectionIsRelevant() else { return nil }

        let menu = NSMenu(title: "")

        let convertItem = NSMenuItem(title: "Convert to M4A - JessOS", action: #selector(createADM(_:)), keyEquivalent: "")
        convertItem.target = self
        convertItem.image = menuIcon
        menu.addItem(convertItem)

        let folderItem = NSMenuItem(title: "Convert to M4A (Folder) - JessOS", action: #selector(createADMInFolder(_:)), keyEquivalent: "")
        folderItem.target = self
        folderItem.image = menuIcon
        menu.addItem(folderItem)

        return menu
    }

    // Only offer the menu when the selection contains WAV/AIFF files or folders
    // (folders are recursed by the app, same as dock drops).
    private func selectionIsRelevant() -> Bool {
        guard let urls = FIFinderSyncController.default().selectedItemURLs() else { return false }
        return urls.contains { url in
            if audioExtensions.contains(url.pathExtension.lowercased()) { return true }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory == true
        }
    }

    // MARK: - Actions

    @objc func createADM(_ sender: Any?) {
        openInApp(mode: "samefolder")
    }

    @objc func createADMInFolder(_ sender: Any?) {
        openInApp(mode: "usefolder")
    }

    private func openInApp(mode: String) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }

        var components = URLComponents()
        components.scheme = "admconvert"
        components.host = "convert"
        components.queryItems = [URLQueryItem(name: "mode", value: mode)]
            + urls.map { URLQueryItem(name: "file", value: $0.path) }

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
