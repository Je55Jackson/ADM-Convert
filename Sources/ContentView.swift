import SwiftUI
import UniformTypeIdentifiers

// MARK: - Window Configuration

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            // Make window resizable and set initial size
            window.styleMask.insert(.resizable)
            window.setContentSize(NSSize(width: 700, height: 480))
            window.minSize = NSSize(width: 500, height: 300)
            window.isMovableByWindowBackground = true

            // Remove black border by making window background transparent
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView: View {
    @EnvironmentObject var conversionManager: ConversionManager
    @State private var isDragOver = false

    var body: some View {
        ZStack {
            // Window configuration
            WindowAccessor()
                .frame(width: 0, height: 0)

            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.4, blue: 0.2),
                    Color(red: 0.7, green: 0.15, blue: 0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                // Header
                Text("JessOS ADM Convert")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                // Show drop zone or file list
                if conversionManager.fileItems.isEmpty {
                    Spacer()

                    // Drop Zone
                    DropZoneView(isDragOver: $isDragOver) { urls in
                        conversionManager.addFiles(urls)
                    }
                    .padding(.horizontal)

                    Spacer()
                } else {
                    // File List with processing controls - fills available space
                    FileListView()
                }

                // Version
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0")")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            conversionManager.addFiles(urls)
        }
    }
}

// MARK: - Drop Zone View

struct DropZoneView: View {
    @Binding var isDragOver: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(.white.opacity(0.8))

            Text("Drop audio files here")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("WAV, AIFF, M4A supported")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isDragOver ? 0.15 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    Color.white.opacity(isDragOver ? 0.8 : 0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .animation(.easeInOut(duration: 0.15), value: isDragOver)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            onDrop(urls)
        }
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let icon: String
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(.white.opacity(isActive ? 0.9 : 0.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(isActive ? 0.15 : 0.05))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
        .environmentObject(ConversionManager())
        .frame(width: 700, height: 480)
}
