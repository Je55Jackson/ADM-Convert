import SwiftUI

struct FileListView: View {
    @EnvironmentObject var conversionManager: ConversionManager
    @State private var expandedItemId: UUID?

    var body: some View {
        VStack(spacing: 12) {
            // Header with file count and clear button
            HStack {
                Text(headerText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Button(action: { conversionManager.clearFiles() }) {
                    Text("Clear")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(conversionManager.isConverting)
                .opacity(conversionManager.isConverting ? 0.4 : 1.0)
            }
            .padding(.horizontal, 4)

            // Scrollable file list - fills available space
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(conversionManager.fileItems) { item in
                        FileRowView(
                            item: item,
                            isExpanded: expandedItemId == item.id,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedItemId == item.id {
                                        expandedItemId = nil
                                    } else {
                                        expandedItemId = item.id
                                    }
                                }
                            }
                        )
                    }
                }
            }

            // Bottom controls
            HStack(spacing: 12) {
                // Output folder toggle - only shown when there are files to convert (not M4A analyze-only)
                if hasConvertibleFiles {
                    Toggle(isOn: $conversionManager.useOutputFolder) {
                        HStack(spacing: 4) {
                            Image(systemName: conversionManager.useOutputFolder ? "folder.fill" : "folder")
                                .font(.system(size: 11))
                            Text("M4A Folder")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.white.opacity(0.9))
                    }
                    .toggleStyle(.checkbox)
                    .tint(.white)
                    .disabled(conversionManager.isConverting)
                }

                Spacer()

                if conversionManager.isConverting {
                    // Single processing indicator while running
                    actionButton(text: "Processing...", action: {}, showSpinner: true)
                        .disabled(true)
                } else if pendingCount == 0 && conversionManager.fileItems.count > 0 {
                    actionButton(text: "All Done", action: {})
                        .disabled(true)
                } else if pendingM4ACount == pendingCount {
                    // All M4A files — single analyze button
                    actionButton(text: "Analyze \(pendingCount) file\(pendingCount == 1 ? "" : "s")", action: {
                        conversionManager.startProcessing(mode: .analyzeOnly)
                    })
                    .disabled(pendingCount == 0)
                } else {
                    // WAV/AIFF files — two buttons
                    actionButton(text: "Analyze Only", action: {
                        conversionManager.startProcessing(mode: .analyzeOnly)
                    })
                    .disabled(pendingCount == 0)

                    actionButton(text: "Convert & Analyze", action: {
                        conversionManager.startProcessing(mode: .convertAndAnalyze)
                    })
                    .disabled(pendingCount == 0)
                }
            }
        }
        .padding(.horizontal)
    }

    private var pendingItems: [FileConversionItem] {
        conversionManager.fileItems.filter {
            if case .pending = $0.status { return true }
            return false
        }
    }

    private var pendingCount: Int {
        pendingItems.count
    }

    private var pendingM4ACount: Int {
        pendingItems.filter { $0.isM4A }.count
    }

    // True if there are files that need conversion (not M4A analyze-only)
    private var hasConvertibleFiles: Bool {
        pendingItems.contains { !$0.isM4A }
    }

    private var completedCount: Int {
        conversionManager.fileItems.filter { $0.isComplete }.count
    }

    private func actionButton(text: String, action: @escaping () -> Void, showSpinner: Bool = false) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showSpinner {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                }
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.25))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var headerText: String {
        if conversionManager.isConverting {
            return "\(completedCount)/\(conversionManager.fileItems.count) complete"
        } else if completedCount == conversionManager.fileItems.count && completedCount > 0 {
            return "\(completedCount) files processed"
        } else {
            return "\(conversionManager.fileItems.count) files"
        }
    }

}

#Preview {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.4, blue: 0.2),
                Color(red: 0.7, green: 0.15, blue: 0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack {
            Spacer()
            FileListView()
                .environmentObject({
                    let manager = ConversionManager()
                    manager.fileItems = [
                        FileConversionItem(url: URL(fileURLWithPath: "/test/track01.wav")),
                        FileConversionItem(url: URL(fileURLWithPath: "/test/track02.wav")),
                        FileConversionItem(url: URL(fileURLWithPath: "/test/track03.wav")),
                    ]
                    return manager
                }())
            Spacer()
        }
    }
    .frame(width: 420, height: 480)
}
