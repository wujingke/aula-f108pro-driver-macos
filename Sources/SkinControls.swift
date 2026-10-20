import AppKit

final class SkinPopupCell: NSPopUpButtonCell {
    var sprite: NSImage!
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let index = !isEnabled ? 3 : (isHighlighted ? 1 : 0)
        let width = sprite.size.width / 4
        sprite.draw(in: cellFrame, from: NSRect(x: CGFloat(index) * width, y: 0, width: width, height: sprite.size.height),
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13),
                                                        .foregroundColor: isEnabled ? NSColor.white : NSColor.gray]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: cellFrame.minX + 9, y: cellFrame.midY - height / 2,
                                            width: cellFrame.width - 34, height: height + 2), withAttributes: attributes)
    }
}

final class SkinCheckboxCell: NSButtonCell {
    var sprite: NSImage!
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let index = !isEnabled ? (state == .on ? 7 : 3) : (state == .on ? 2 : (isHighlighted ? 1 : 0))
        let size = sprite.size.width / 8
        sprite.draw(in: NSRect(x: cellFrame.minX, y: cellFrame.midY - 15, width: 30, height: 30),
                    from: NSRect(x: CGFloat(index) * size, y: 0, width: size, height: 30),
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: cellFrame.minX + 34, y: cellFrame.midY - height / 2,
                                            width: cellFrame.width - 34, height: height + 2), withAttributes: attributes)
    }
}

final class SkinSlider: NSControl {
    private var emptyTrack: NSImage!
    private var filledTrack: NSImage!
    private var knobs = [NSImage]()
    private var value: Double = 0
    var minValue: Double = 0 { didSet { doubleValue = value } }
    var maxValue: Double = 5 { didSet { doubleValue = value } }
    var numberOfTickMarks = 6 { didSet { needsDisplay = true } }
    override var isHighlighted: Bool { didSet { needsDisplay = true } }
    let knobThickness: CGFloat = 20
    var bar: NSImage! {
        didSet {
            filledTrack = crop(bar, rect: CGRect(x: 2, y: 7, width: 236, height: 8))
            emptyTrack = crop(bar, rect: CGRect(x: 2, y: 26, width: 236, height: 8))
            needsDisplay = true
        }
    }
    var thumb: NSImage! {
        didSet {
            knobs = (0..<4).map { crop(thumb, rect: CGRect(x: $0 * 20, y: 0, width: 20, height: 20)) }
            needsDisplay = true
        }
    }
    override var doubleValue: Double {
        get { value }
        set {
            value = max(minValue, min(maxValue, newValue.rounded()))
            setAccessibilityValue(value)
            setNeedsDisplay(bounds)
        }
    }
    override var integerValue: Int {
        get { Int(value) }
        set { doubleValue = Double(newValue) }
    }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { isEnabled }

    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = NSActionCell()
        wantsLayer = true
        layer?.isOpaque = false; layer?.backgroundColor = NSColor.clear.cgColor
        focusRingType = .exterior
        setAccessibilityRole(.slider)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var track: NSRect {
        NSRect(x: 10, y: bounds.midY - 5, width: max(1, bounds.width - 20), height: 8)
    }
    private var fraction: Double {
        maxValue > minValue ? max(0, min(1, (value - minValue) / (maxValue - minValue))) : 0
    }

    private func crop(_ image: NSImage, rect: CGRect) -> NSImage {
        guard let bitmap = image.representations.first as? NSBitmapImageRep,
              let frame = bitmap.cgImage?.cropping(to: rect) else {
            preconditionFailure("Invalid original slider sprite")
        }
        return NSImage(cgImage: frame, size: rect.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard emptyTrack != nil, filledTrack != nil, knobs.count == 4 else { return }
        // Full invalidation on a transparent backing layer prevents tracking remnants.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.imageInterpolation = .high
        emptyTrack.draw(in: track, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)).addClip()
        filledTrack.draw(in: track, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        if numberOfTickMarks > 1 {
            NSColor.white.withAlphaComponent(0.4).setStroke()
            let ticks = NSBezierPath()
            for index in 0..<numberOfTickMarks {
                let posX = track.minX + track.width * CGFloat(index) / CGFloat(numberOfTickMarks - 1)
                ticks.move(to: NSPoint(x: posX, y: bounds.maxY - 3))
                ticks.line(to: NSPoint(x: posX, y: bounds.maxY))
            }
            ticks.lineWidth = 0.5; ticks.stroke()
        }
        let knob = NSRect(x: track.minX + track.width * fraction - 10, y: track.midY - 10, width: 20, height: 20)
        knobs[isEnabled ? (isHighlighted ? 1 : 0) : 3].draw(
            in: knob, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if window?.firstResponder === self {
            NSColor(rgb: 0xff9c00).setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()
        }
    }

    private func update(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        changeValue(minValue + Double((point.x - track.minX) / track.width) * (maxValue - minValue))
    }
    private func changeValue(_ next: Double) {
        let previous = integerValue
        doubleValue = next
        if previous != integerValue { sendAction(action, to: target) }
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isHighlighted = true; update(from: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, isHighlighted else { return }
        update(from: event)
    }
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, isHighlighted else { return }
        update(from: event); isHighlighted = false
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 125: changeValue(value - 1)
        case 124, 126: changeValue(value + 1)
        case 115: changeValue(minValue)
        case 119: changeValue(maxValue)
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }; changeValue(value + 1); return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }; changeValue(value - 1); return true
    }
}
