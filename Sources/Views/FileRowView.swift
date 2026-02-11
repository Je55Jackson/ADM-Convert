import SwiftUI

// Custom corner radius extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        self.init()

        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomLeft = corners.contains(.bottomLeft)
        let bottomRight = corners.contains(.bottomRight)

        let radius = cornerRadii.width

        move(to: CGPoint(x: rect.minX + (topLeft ? radius : 0), y: rect.minY))

        // Top edge and top right corner
        line(to: CGPoint(x: rect.maxX - (topRight ? radius : 0), y: rect.minY))
        if topRight {
            curve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                  controlPoint1: CGPoint(x: rect.maxX, y: rect.minY),
                  controlPoint2: CGPoint(x: rect.maxX, y: rect.minY + radius))
        }

        // Right edge and bottom right corner
        line(to: CGPoint(x: rect.maxX, y: rect.maxY - (bottomRight ? radius : 0)))
        if bottomRight {
            curve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                  controlPoint1: CGPoint(x: rect.maxX, y: rect.maxY),
                  controlPoint2: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        }

        // Bottom edge and bottom left corner
        line(to: CGPoint(x: rect.minX + (bottomLeft ? radius : 0), y: rect.maxY))
        if bottomLeft {
            curve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                  controlPoint1: CGPoint(x: rect.minX, y: rect.maxY),
                  controlPoint2: CGPoint(x: rect.minX, y: rect.maxY - radius))
        }

        // Left edge and top left corner
        line(to: CGPoint(x: rect.minX, y: rect.minY + (topLeft ? radius : 0)))
        if topLeft {
            curve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                  controlPoint1: CGPoint(x: rect.minX, y: rect.minY),
                  controlPoint2: CGPoint(x: rect.minX + radius, y: rect.minY))
        }

        close()
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}

struct UIRectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct FileRowView: View {
    @ObservedObject var item: FileConversionItem
    var isExpanded: Bool = false
    var onTap: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 8) {
                // Status icon
                statusIcon
                    .frame(width: 16, height: 16)

                // Filename
                Text(item.filename)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Progress or result indicator
                statusIndicator

                // Chevron for completed items
                if case .completed = item.status {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(rowBackground)
            .cornerRadius(6, corners: isExpanded ? [.topLeft, .topRight] : .allCorners)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                if case .completed = item.status {
                    onTap?()
                }
            }

            // Expanded detail section
            if isExpanded, case .completed(let result) = item.status, let r = result {
                expandedDetail(for: r)
            }
        }
    }

    @ViewBuilder
    private func expandedDetail(for result: AFClipResult) -> some View {
        VStack(spacing: 8) {
            if result.hasClipping {
                // Channel summary
                HStack(spacing: 16) {
                    channelSummary(label: "Left", onSample: result.leftOnSample, interSample: result.leftInterSample)
                    Divider()
                        .frame(height: 30)
                        .background(Color.white.opacity(0.2))
                    channelSummary(label: "Right", onSample: result.rightOnSample, interSample: result.rightInterSample)
                }

                // dB statistics
                HStack(spacing: 0) {
                    decibelStat(label: "Min dB Clip", value: result.minDecibels)
                    Spacer()
                    decibelStat(label: "Avg dB Clip", value: result.avgDecibels)
                    Spacer()
                    decibelStat(label: "Max dB Clip", value: result.maxDecibels)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))
                    Text("No Clipping Detected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            // File info
            HStack(spacing: 12) {
                Text("\(result.channels) ch")
                Text("\(result.sampleRate) Hz")
                if result.hasClipping {
                    Text("\(result.totalClips) clips")
                }
            }
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.3))  // Darker background for better contrast
        .cornerRadius(6, corners: [.bottomLeft, .bottomRight])
    }

    private func channelSummary(label: String, onSample: Int, interSample: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(onSample)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(onSample > 0 ? Color(red: 1.0, green: 0.75, blue: 0.0) : .white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inter")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(interSample)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(interSample > 0 ? Color(red: 1.0, green: 0.75, blue: 0.0) : .white)
                }
            }
        }
    }

    private func decibelStat(label: String, value: Double?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Text(value != nil ? String(format: "%+.2f", value!) : "—")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(decibelColor(for: value))
        }
    }

    private func decibelColor(for value: Double?) -> Color {
        guard let db = value else { return .white }
        if db > 0 {
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        } else if db < 0 {
            return Color(red: 1.0, green: 0.7, blue: 0.4)
        }
        return Color(red: 1.0, green: 0.5, blue: 0.5)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "waveform")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))

        case .converting:
            ProgressView()
                .scaleEffect(0.6)
                .tint(.white)

        case .analyzing:
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))

        case .completed(let result):
            if let r = result, r.hasClipping {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.0))  // Bright yellow-orange
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))
            }

        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch item.status {
        case .pending:
            EmptyView()

        case .converting(let progress):
            ProgressView(value: progress)
                .frame(width: 60)
                .tint(.white)

        case .analyzing:
            ProgressView()
                .scaleEffect(0.5)
                .tint(.white)
                .frame(width: 60)

        case .completed(let result):
            if let r = result {
                Text(r.hasClipping ? "\(r.totalClips) clips" : "No Clipping")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(r.hasClipping ?
                        Color(red: 1.0, green: 0.75, blue: 0.0) :  // Bright yellow-orange for clips
                        Color(red: 0.4, green: 0.9, blue: 0.4))
            }

        case .error:
            Text("Error")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
        }
    }

    private var rowBackground: Color {
        switch item.status {
        case .completed(let result):
            if let r = result, r.hasClipping {
                // Red-tinted background for clipping - use lighter() on hover
                let baseColor = Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.15)
                return isHovered ? baseColor.lighter(by: 0.1) : baseColor
            } else {
                // White background for no clipping - just increase opacity on hover
                return Color.white.opacity(isHovered ? 0.15 : 0.1)
            }
        case .error:
            let baseColor = Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.15)
            return isHovered ? baseColor.lighter(by: 0.1) : baseColor
        default:
            // Pending/converting/analyzing - subtle opacity change on hover
            return Color.white.opacity(isHovered ? 0.15 : 0.1)
        }
    }
}

// Color extension for hover effect
extension Color {
    func lighter(by amount: Double) -> Color {
        return Color(
            red: min(1, Double(NSColor(self).redComponent) + amount),
            green: min(1, Double(NSColor(self).greenComponent) + amount),
            blue: min(1, Double(NSColor(self).blueComponent) + amount)
        )
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

        VStack(spacing: 8) {
            FileRowView(item: {
                let item = FileConversionItem(url: URL(fileURLWithPath: "/test/pending.wav"))
                return item
            }())

            FileRowView(item: {
                let item = FileConversionItem(url: URL(fileURLWithPath: "/test/converting.wav"))
                item.status = .converting(progress: 0.6)
                return item
            }())

            FileRowView(item: {
                let item = FileConversionItem(url: URL(fileURLWithPath: "/test/clean.wav"))
                item.status = .completed(AFClipResult(
                    filename: "clean.m4a", filePath: "/test/clean.m4a",
                    channels: 2, sampleRate: 48000,
                    leftOnSample: 0, leftInterSample: 0,
                    rightOnSample: 0, rightInterSample: 0,
                    hasNoClipping: true,
                    clipInstances: []
                ))
                return item
            }(), isExpanded: true)

            FileRowView(item: {
                let item = FileConversionItem(url: URL(fileURLWithPath: "/test/clipped.wav"))
                item.status = .completed(AFClipResult(
                    filename: "clipped.m4a", filePath: "/test/clipped.m4a",
                    channels: 2, sampleRate: 48000,
                    leftOnSample: 5, leftInterSample: 3,
                    rightOnSample: 2, rightInterSample: 2,
                    hasNoClipping: false,
                    clipInstances: [
                        ClipInstance(seconds: 0.0234, sample: 1123, channel: "L", value: 1.000000, decibels: 0.00),
                        ClipInstance(seconds: 0.0456, sample: 2189, channel: "R", value: 0.999999, decibels: -0.01),
                    ]
                ))
                return item
            }(), isExpanded: true)
        }
        .padding()
    }
    .frame(width: 400, height: 500)
}
