import Foundation
import SwiftUI

// MARK: - Conversion Status

enum ConversionStatus: Equatable {
    case pending
    case converting(progress: Double)  // 0.0-1.0
    case analyzing
    case completed(AFClipResult?)
    case error(String)

    static func == (lhs: ConversionStatus, rhs: ConversionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending):
            return true
        case (.converting(let p1), .converting(let p2)):
            return p1 == p2
        case (.analyzing, .analyzing):
            return true
        case (.completed(let r1), .completed(let r2)):
            if let r1 = r1, let r2 = r2 {
                return r1.filePath == r2.filePath
            }
            return r1 == nil && r2 == nil
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

// MARK: - File Conversion Item

class FileConversionItem: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let filename: String
    let isM4A: Bool  // M4A files are analyze-only (no conversion needed)

    @Published var status: ConversionStatus = .pending
    @Published var outputURL: URL?
    @Published var clipResult: AFClipResult?

    var displayName: String {
        filename
    }

    var isProcessing: Bool {
        switch status {
        case .converting, .analyzing:
            return true
        default:
            return false
        }
    }

    var isComplete: Bool {
        switch status {
        case .completed, .error:
            return true
        default:
            return false
        }
    }

    init(url: URL) {
        self.sourceURL = url
        self.filename = url.lastPathComponent
        self.isM4A = url.pathExtension.lowercased() == "m4a"
    }
}
