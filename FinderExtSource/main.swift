import Cocoa
import FinderSync

// Finder Sync extension: adds "Create ADM" items to Finder's right-click menu.
// Does no conversion itself — hands the selected files to the main app via the
// admconvert:// URL scheme and the app's headless conversion path.

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

    override init() {
        super.init()
        // Monitor everything so the menu is available anywhere in Finder.
        // We draw no badges, so this costs nothing beyond menu callbacks.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
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
