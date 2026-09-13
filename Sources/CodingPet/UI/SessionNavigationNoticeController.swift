import AppKit
import SwiftUI

@MainActor
final class SessionNavigationNoticeController {
    private static let noticeSize = NSSize(width: 286, height: 62)
    private static let screenMargin: CGFloat = 12
    private static let anchorSpacing: CGFloat = 12

    private let panel: NSPanel
    private var dismissalTask: Task<Void, Never>?

    init() {
        panel = FocusPreservingPanel(
            contentRect: NSRect(origin: .zero, size: Self.noticeSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: SessionNavigationNoticeView())
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show(
        beside anchorFrame: NSRect,
        alignedTo point: NSPoint = NSEvent.mouseLocation
    ) {
        dismissalTask?.cancel()
        position(beside: anchorFrame, alignedTo: point)
        panel.orderFrontRegardless()

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func position(beside anchorFrame: NSRect, alignedTo point: NSPoint) {
        let anchorCenter = NSPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        guard let visibleFrame = screen(containing: anchorCenter)?.visibleFrame else {
            return
        }
        panel.setFrame(
            Self.noticeFrame(
                beside: anchorFrame,
                visibleFrame: visibleFrame,
                preferredCenterY: point.y
            ),
            display: true
        )
    }

    static func noticeFrame(
        beside anchorFrame: NSRect,
        visibleFrame: NSRect,
        preferredCenterY: CGFloat
    ) -> NSRect {
        let minimumX = visibleFrame.minX + screenMargin
        let maximumX = visibleFrame.maxX - noticeSize.width - screenMargin
        let leftX = anchorFrame.minX - noticeSize.width - anchorSpacing
        let rightX = anchorFrame.maxX + anchorSpacing

        let x: CGFloat
        if leftX >= minimumX {
            x = leftX
        } else if rightX <= maximumX {
            x = rightX
        } else {
            x = abs(leftX - minimumX) <= abs(rightX - maximumX)
                ? minimumX
                : maximumX
        }

        let minimumY = visibleFrame.minY + screenMargin
        let maximumY = visibleFrame.maxY - noticeSize.height - screenMargin
        let y = min(
            max(preferredCenterY - noticeSize.height / 2, minimumY),
            maximumY
        )
        return NSRect(origin: NSPoint(x: x, y: y), size: noticeSize)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

struct SessionNavigationNoticeView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Can’t open Claude session directly")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Open this session from Claude Desktop.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 278, height: 54)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card.opacity(0.92))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
        .padding(4)
        .frame(width: 286, height: 62)
        .accessibilityElement(children: .combine)
    }
}
