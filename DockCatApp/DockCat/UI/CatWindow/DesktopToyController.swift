import AppKit

@MainActor
final class DesktopToyController {
    private struct Item {
        let panel: NSPanel
        let timer: Timer?
    }

    private var items: [UUID: Item] = [:]
    var onUse: ((PetToyKind, CGPoint) -> Void)?

    func place(_ kind: PetToyKind, near point: CGPoint) {
        let id = UUID()
        let size = kind == .box ? CGSize(width: 82, height: 66) : CGSize(width: 58, height: 58)
        let view = DesktopToyView(frame: NSRect(origin: .zero, size: size), kind: kind)
        let panel = NSPanel(
            contentRect: NSRect(origin: point, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = kind != .laser
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        view.onDrag = { [weak panel] delta in
            guard let panel else { return }
            panel.setFrameOrigin(CGPoint(x: panel.frame.origin.x + delta.x, y: panel.frame.origin.y + delta.y))
        }
        view.onUse = { [weak self, weak panel] in
            guard let panel else { return }
            self?.onUse?(kind, CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        }
        view.onClose = { [weak self] in self?.remove(id) }

        var timer: Timer?
        if kind == .laser {
            panel.ignoresMouseEvents = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self, weak panel] _ in
                Task { @MainActor in
                    guard let self, let panel else { return }
                    let mouse = NSEvent.mouseLocation
                    panel.setFrameOrigin(CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2))
                    self.onUse?(kind, mouse)
                }
            }
        }
        items[id] = Item(panel: panel, timer: timer)
        panel.orderFrontRegardless()
    }

    func clear() {
        for item in items.values {
            item.timer?.invalidate()
            item.panel.orderOut(nil)
            item.panel.close()
        }
        items.removeAll()
    }

    func setHidden(_ hidden: Bool) {
        for item in items.values {
            if hidden { item.panel.orderOut(nil) } else { item.panel.orderFrontRegardless() }
        }
    }

    private func remove(_ id: UUID) {
        guard let item = items.removeValue(forKey: id) else { return }
        item.timer?.invalidate()
        item.panel.orderOut(nil)
        item.panel.close()
    }
}

@MainActor
private final class DesktopToyView: NSView {
    let kind: PetToyKind
    var onDrag: ((CGPoint) -> Void)?
    var onUse: (() -> Void)?
    var onClose: (() -> Void)?
    private var lastScreenPoint: CGPoint?

    init(frame: NSRect, kind: PetToyKind) {
        self.kind = kind
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { lastScreenPoint = NSEvent.mouseLocation }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if let previous = lastScreenPoint {
            onDrag?(CGPoint(x: point.x - previous.x, y: point.y - previous.y))
        }
        lastScreenPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        lastScreenPoint = nil
        onUse?()
    }

    override func rightMouseDown(with event: NSEvent) { onClose?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch kind {
        case .ball:
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 10, dy: 10)).fill()
            NSColor.white.withAlphaComponent(0.8).setStroke()
            let shine = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 8, y: bounds.midY + 4, width: 8, height: 8))
            shine.lineWidth = 2
            shine.stroke()
        case .laser:
            NSColor.systemRed.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 13, dy: 13)).fill()
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 22, dy: 22)).fill()
        default:
            NSColor.windowBackgroundColor.withAlphaComponent(0.82).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14).fill()
            let emoji: String = switch kind {
            case .wand: "🪶"
            case .box: "📦"
            case .food: "🍚"
            case .water: "💧"
            default: "🧸"
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: kind == .box ? 37 : 30)]
            let size = emoji.size(withAttributes: attributes)
            emoji.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
