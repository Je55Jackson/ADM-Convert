import Cocoa
import SwiftUI

// Manual app entry point - gives us full control over window creation
// This prevents SwiftUI's WindowGroup from auto-creating a window on launch

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Set activation policy to regular (shows in dock)
app.setActivationPolicy(.regular)

// Run the app
app.run()
