import SwiftUI

// MARK: - Guide Step

struct GuideStep {
    let id: String                // Unique key for "shown" tracking
    let title: String
    let message: String
    let pointTo: Anchor<CGRect>?  // Target element anchor (set at runtime)
    let arrowEdge: Edge           // Which side of the tooltip the arrow points from
}

// MARK: - Guide Anchor Preference

struct GuideAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - View Extension

extension View {
    /// Mark a view as a guide target with a unique ID.
    func guideAnchor(_ id: String) -> some View {
        self.anchorPreference(key: GuideAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - GuideOverlay

/// Full-screen overlay that dims everything except the spotlight target.
/// Shows a tooltip with title, message, and a pointing arrow.
struct GuideOverlay: View {
    let stepId: String
    let title: String
    let message: String
    let arrowEdge: Edge
    let anchors: [String: Anchor<CGRect>]
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let targetRect = anchors[stepId].map { proxy[$0] }

            ZStack {
                // Dim background with spotlight cutout
                if let rect = targetRect {
                    spotlightMask(rect: rect, in: proxy.size)
                } else {
                    Color.black.opacity(0.6)
                }

                // Tooltip + arrow
                if let rect = targetRect {
                    tooltipView
                        .position(tooltipPosition(targetRect: rect, containerSize: proxy.size))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
        }
    }

    // MARK: - Spotlight Mask

    private func spotlightMask(rect: CGRect, in size: CGSize) -> some View {
        let inset: CGFloat = -8
        let spotlightRect = rect.insetBy(dx: inset, dy: inset)

        return Canvas { context, canvasSize in
            // Full dark overlay
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(.black.opacity(0.6))
            )
            // Punch out the spotlight
            context.blendMode = .destinationOut
            let spotlightPath = RoundedRectangle(cornerRadius: 10, style: .continuous)
                .path(in: spotlightRect)
            context.fill(spotlightPath, with: .color(.white))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Tooltip

    private var tooltipView: some View {
        VStack(spacing: 6) {
            // Arrow pointing up/down depending on position
            if arrowEdge == .top {
                arrowShape
                    .rotationEffect(.degrees(0))
                    .foregroundColor(Color(white: 0.15))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Text(L10n.isChinese ? "点击任意处关闭" : "Tap anywhere to dismiss")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(12)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.15))
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)

            if arrowEdge == .bottom {
                arrowShape
                    .rotationEffect(.degrees(180))
                    .foregroundColor(Color(white: 0.15))
            }
        }
    }

    private var arrowShape: some View {
        Triangle()
            .frame(width: 14, height: 8)
    }

    // MARK: - Position

    private func tooltipPosition(targetRect: CGRect, containerSize: CGSize) -> CGPoint {
        let x = min(max(targetRect.midX, 130), containerSize.width - 130)

        if arrowEdge == .top {
            // Tooltip below target
            let y = targetRect.maxY + 24
            return CGPoint(x: x, y: y)
        } else {
            // Tooltip above target
            let y = targetRect.minY - 24
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Guide Manager

/// Tracks which guides have been shown. Persisted via UserDefaults.
enum GuideManager {
    private static let prefix = "cc_stats_guide_shown_"

    static func hasShown(_ stepId: String) -> Bool {
        UserDefaults.standard.bool(forKey: prefix + stepId)
    }

    static func markShown(_ stepId: String) {
        UserDefaults.standard.set(true, forKey: prefix + stepId)
    }

    static func reset(_ stepId: String) {
        UserDefaults.standard.removeObject(forKey: prefix + stepId)
    }

    static func resetAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
