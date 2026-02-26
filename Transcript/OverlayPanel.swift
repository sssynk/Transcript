import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    init(state: AppState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        let hosting = NSHostingView(rootView: PillView(state: state))
        contentView = hosting

        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let x = screen.frame.midX - frame.width / 2
        let startY = screen.frame.minY + 24
        let endY = screen.frame.minY + 52

        setFrameOrigin(NSPoint(x: x, y: startY))
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrameOrigin(NSPoint(x: x, y: endY))
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }) {
            self.orderOut(nil)
        }
    }
}
