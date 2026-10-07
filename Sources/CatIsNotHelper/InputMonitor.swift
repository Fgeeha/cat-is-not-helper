import AppKit
import ApplicationServices

/// Слушает клавиатуру и мышь глобально. Считает только факт нажатия,
/// какие именно клавиши нажаты — не запоминает и не записывает.
final class InputMonitor {
    var onKey: ((Paw) -> Void)?
    var onClick: ((Paw) -> Void)?

    private var monitors: [Any] = []
    private var lastPaw: Paw = .right

    /// Клавиши левой половины клавиатуры (коды macOS) — для них котик бьёт левой лапой.
    private static let leftKeys: Set<UInt16> = [
        0, 1, 2, 3, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 17, // a s d f g z x c v b q w e r t
        18, 19, 20, 21, 23, // 1 2 3 4 5
        48, 50, 53, 55, 56, 57, 58, 59, 63, // tab ` esc cmd shift caps opt ctrl fn
    ]

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return }
            let paw: Paw
            if event.keyCode == 49 { // пробел — чередуем
                paw = lastPaw == .left ? .right : .left
            } else {
                paw = Self.leftKeys.contains(event.keyCode) ? .left : .right
            }
            lastPaw = paw
            onKey?(paw)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onClick?(.right)
        default:
            break
        }
    }
}
