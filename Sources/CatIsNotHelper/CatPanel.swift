import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Контейнер, который ловит клики/перетаскивание/drag&drop поверх SwiftUI-котика.
final class CatContainerView: NSView {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDropFiles: (([URL]) -> Void)?
    var menuProvider: (() -> NSMenu)?

    private var dragging = false
    private var downPoint = NSPoint.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragging = false
        downPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        let p = event.locationInWindow
        if hypot(p.x - downPoint.x, p.y - downPoint.y) > 3 {
            dragging = true
            window?.performDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !dragging else { return }
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: Drag & drop картинок

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = imageURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    private func imageURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }
}

/// Прозрачная плавающая панель с котиком. Не активирует приложение при клике,
/// чтобы фокус оставался там, где ты печатаешь.
final class CatPanel: NSPanel {
    let container: CatContainerView
    private let frameName = "CatPanel"

    init(state: CatState, settings: AppSettings) {
        let size = CatView.size(for: settings.scale)
        container = CatContainerView(frame: NSRect(origin: .zero, size: size))
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        animationBehavior = .none

        let hosting = NSHostingView(rootView: CatView(state: state, settings: settings))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        contentView = container

        placeInitially()
        apply(settings)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ settings: AppSettings) {
        level = settings.alwaysOnTop ? .floating : .normal
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        behavior.insert(settings.allSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        collectionBehavior = behavior

        let size = CatView.size(for: settings.scale)
        if frame.size != size {
            var f = frame
            f.size = size
            setFrame(f, display: true)
            keepOnScreen()
        }
    }

    private func placeInitially() {
        if setFrameUsingName(frameName) {
            setFrameAutosaveName(frameName)
            return
        }
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            let origin = NSPoint(x: v.maxX - frame.width - 24, y: v.minY + 16)
            setFrameOrigin(origin)
        }
        setFrameAutosaveName(frameName)
    }

    private func keepOnScreen() {
        guard let screen = screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        var f = frame
        f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
        f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
        if f != frame { setFrame(f, display: true) }
    }
}
