import AppKit
import ApplicationServices

final class HotkeyManager {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPressed = false

    private static let rightOptionKeyCode: UInt16 = 61

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    func checkAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == Self.rightOptionKeyCode else { return }

        let optionHeld = event.modifierFlags.contains(.option)

        if optionHeld && !isPressed {
            isPressed = true
            onHotkeyDown?()
        } else if !optionHeld && isPressed {
            isPressed = false
            onHotkeyUp?()
        }
    }
}
