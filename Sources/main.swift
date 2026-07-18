import Cocoa
import SwiftUI

// Manual app entry point - gives us full control over window creation
// This prevents SwiftUI's WindowGroup from auto-creating a window on launch

let app = NSApplication.shared
let delegate = AppDelegate()

// Launched by the post-update helper purely so macOS re-discovers the Finder
// extension inside the freshly installed bundle (pkd only scans appexes when
// their host app launches). Runs invisibly and quits itself.
delegate.registerExtensionOnly = CommandLine.arguments.contains("--register-extension")

app.delegate = delegate

// Regular policy shows in dock; the register-only cameo stays invisible.
app.setActivationPolicy(delegate.registerExtensionOnly ? .accessory : .regular)

// Run the app
app.run()
