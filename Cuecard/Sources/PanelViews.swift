import AppKit

@MainActor
final class ReadingScrollView: NSScrollView {
    var userDidScroll: (() -> Void)?
    var documentDidFit: (() -> Void)?
    private var fitting = false

    override func scrollWheel(with event: NSEvent) {
        userDidScroll?()
        super.scrollWheel(with: event)
    }

    override func tile() {
        super.tile()
        fitDocument()
    }

    func fitDocument() {
        guard !fitting, let text = documentView as? NSTextView,
              let container = text.textContainer, let layout = text.layoutManager else { return }
        let viewport = contentView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        fitting = true
        defer {
            fitting = false
            documentDidFit?()
        }

        if text.frame.width != viewport.width {
            text.setFrameSize(NSSize(width: viewport.width, height: text.frame.height))
        }
        // The reader's document height follows the text layout, including wrapped lines.
        layout.ensureLayout(for: container)
        guard !text.isEditable else { return }
        let height = max(viewport.height, ceil(layout.usedRect(for: container).maxY
                                             + text.textContainerOrigin.y + text.textContainerInset.height))
        if text.frame.height != height {
            text.setFrameSize(NSSize(width: viewport.width, height: height))
        }
    }

    var scrollLimit: CGFloat {
        guard let view = documentView else { return 0 }
        return max(0, view.frame.height - contentView.bounds.height)
    }

    func move(to offset: CGFloat) {
        contentView.scroll(to: NSPoint(x: 0, y: min(max(offset, 0), scrollLimit)))
        reflectScrolledClipView(contentView)
    }
}

@MainActor
final class PanelButton: NSButton {
    enum Treatment { case plain, filled, primary }
    var treatment: Treatment = .plain { didSet { needsDisplay = true } }
    private var pointerInside = false
    private var hoverArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(29, size.width + (title.isEmpty ? 0 : 15)), height: 29)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled {
            let fill: NSColor
            switch treatment {
            case .plain: fill = .labelColor.withAlphaComponent(pointerInside ? 0.09 : 0)
            case .filled: fill = .labelColor.withAlphaComponent(pointerInside ? 0.13 : 0.07)
            case .primary: fill = .controlAccentColor.withAlphaComponent(pointerInside ? 0.23 : 0.15)
            }
            let down = cell?.isHighlighted == true
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            (down ? NSColor.labelColor.withAlphaComponent(0.18) : fill).setFill()
            path.fill()
        }
        cell?.draw(withFrame: bounds.insetBy(dx: title.isEmpty ? 4 : 8, dy: 0), in: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { pointerInside = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointerInside = false; needsDisplay = true }
}

@MainActor
final class ReaderCard: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 15, yRadius: 15)
        (dark ? NSColor.black.withAlphaComponent(0.23) : NSColor.white.withAlphaComponent(0.60)).setFill()
        outline.fill()
        NSColor.labelColor.withAlphaComponent(dark ? 0.13 : 0.09).setStroke()
        outline.stroke()
    }
}

@MainActor
final class ReadingProgress: NSView {
    var fraction: Double = 0 { didSet { if oldValue != fraction { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
        if fraction > 0 {
            NSColor.controlAccentColor.withAlphaComponent(0.75).setFill()
            let fill = NSRect(x: 0, y: 0, width: max(1, bounds.width * fraction), height: bounds.height)
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
