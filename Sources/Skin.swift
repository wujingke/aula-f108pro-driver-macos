import AppKit
import CoreText

final class DriverResources {
    let root: URL
    let layout: [KeyboardKey]
    let language: [String: String]
    private var images: [String: NSImage] = [:]

    init() throws {
        guard let resources = Bundle.main.resourceURL else { throw ToolError("应用资源目录不存在。") }
        root = resources.appendingPathComponent("Assets")
        layout = try JSONDecoder().decode([KeyboardKey].self, from: Data(contentsOf: root.appendingPathComponent("keyboard.json")))
        language = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("language.json")))
        guard layout.count == 104 else { throw ToolError("键盘布局资源不完整。") }
        for name in ["OpenSans-Regular", "OpenSans-Semibold", "OpenSans-Light", "OpenSans-ExtraBold"] {
            var error: Unmanaged<CFError>?
            let url = root.appendingPathComponent("font/\(name).ttf")
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), let failure = error?.takeRetainedValue() {
                throw ToolError("字体加载失败：\(failure)")
            }
        }
    }

    func image(_ path: String) -> NSImage {
        if let image = images[path] { return image }
        let url = root.appendingPathComponent(path.hasPrefix("device/") ? path : "skins/theme1/\(path)")
        guard let image = NSImage(contentsOf: url) else { preconditionFailure("Missing original skin image: \(path)") }
        // Windows skin coordinates are pixels; ignore embedded 96-DPI point sizes on macOS.
        guard let bitmap = image.representations.first as? NSBitmapImageRep else {
            preconditionFailure("Skin image is not a bitmap: \(path)")
        }
        image.size = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        images[path] = image
        return image
    }

    func text(_ identifier: Int) -> String {
        guard let value = language[String(identifier)] else { preconditionFailure("Missing original language string: \(identifier)") }
        return value
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class BackgroundView: FlippedView {
    let image: NSImage
    init(frame: NSRect, image: NSImage) { self.image = image; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func mouseDown(with event: NSEvent) {
        if convert(event.locationInWindow, from: nil).y < 60 { window?.performDrag(with: event) }
    }
}

final class SkinButton: NSButton {
    var sprite: NSImage?
    var icon: NSImage?
    var spriteFrames = 4
    var active = false { didSet { needsDisplay = true } }
    var accent: NSColor = NSColor(rgb: 0xff9c00)
    var handler: (() -> Void)?
    var showBackground = true

    init(title: String, frame: NSRect, sprite: NSImage? = nil, action: @escaping () -> Void) {
        self.sprite = sprite
        super.init(frame: frame)
        self.title = title
        isBordered = false
        font = NSFont(name: "OpenSans-Semibold", size: 14) ?? .systemFont(ofSize: 14)
        setButtonType(.momentaryChange)
        target = self; self.action = #selector(invoke)
        handler = action
        focusRingType = .exterior
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { handler?() }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func draw(_ dirtyRect: NSRect) {
        let highlighted = cell?.isHighlighted == true
        if let sprite {
            let index = !isEnabled ? 3 : (active ? 2 : (highlighted ? 1 : 0))
            let width = sprite.size.width / CGFloat(spriteFrames)
            sprite.draw(in: bounds, from: NSRect(x: CGFloat(index) * width, y: 0, width: width, height: sprite.size.height),
                        operation: .sourceOver, fraction: isEnabled ? 1 : 0.45, respectFlipped: true, hints: nil)
        } else if showBackground {
            (active || highlighted ? accent.withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.09)).setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            path.fill()
            (active ? accent : NSColor.white.withAlphaComponent(0.3)).setStroke(); path.stroke()
        }
        if let icon {
            let size = min(bounds.width, bounds.height)
            icon.draw(in: NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if !title.isEmpty {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let color = isEnabled ? (active ? accent : NSColor.white) : NSColor.lightGray
            let attributes: [NSAttributedString.Key: Any] = [.font: font!, .foregroundColor: color, .paragraphStyle: paragraph]
            let height = (title as NSString).size(withAttributes: attributes).height
            (title as NSString).draw(in: NSRect(x: 3, y: (bounds.height - height) / 2, width: bounds.width - 6, height: height + 2),
                                     withAttributes: attributes)
        }
        if window?.firstResponder === self {
            accent.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
            ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class KeyboardView: FlippedView {
    let layout: [KeyboardKey]
    let background: NSImage
    var selected = Set<Int>() { didSet { updateSelection() } }
    var colors: [String: UInt32] = [:] { didSet { needsDisplay = true } }
    var bindings: [String: KeyBinding] = [:] { didSet { needsDisplay = true } }
    var onSelection: ((Set<Int>) -> Void)?
    var multiple = false
    private var buttons: [Int: SkinButton] = [:]

    init(frame: NSRect, resources: DriverResources) {
        layout = resources.layout
        background = resources.image("keyboard/img_keyboard_layout.png")
        super.init(frame: frame)
        for key in layout {
            let button = SkinButton(title: "", frame: key.rect) { }
            button.showBackground = false
            button.setAccessibilityLabel("按键 \(key.name)")
            button.toolTip = key.name
            button.handler = { [weak self] in
                guard let self else { return }
                if multiple {
                    if selected.contains(key.index) { selected.remove(key.index) } else { selected.insert(key.index) }
                } else { selected = [key.index] }
                onSelection?(selected)
            }
            addSubview(button); buttons[key.index] = button
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        background.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        for key in layout {
            if let color = colors[String(key.index)] {
                NSColor(rgb: color, alpha: 0.45).setFill()
                NSBezierPath(roundedRect: key.rect, xRadius: 3, yRadius: 3).fill()
            }
            if let binding = bindings[String(key.index)], binding.kind != "default" {
                NSColor(rgb: 0xff9c00).setFill()
                NSBezierPath(ovalIn: NSRect(x: key.rect.maxX - 7, y: key.rect.minY + 2, width: 5, height: 5)).fill()
            }
            if selected.contains(key.index) {
                NSColor(rgb: 0xffab00).setStroke()
                let path = NSBezierPath(roundedRect: key.rect.insetBy(dx: -1, dy: -1), xRadius: 3, yRadius: 3)
                path.lineWidth = 2; path.stroke()
            }
        }
    }
    private func updateSelection() {
        for (index, button) in buttons { button.setAccessibilityValue(selected.contains(index) ? "已选中" : "未选中") }
        needsDisplay = true
    }
}

@discardableResult
func label(_ text: String, frame: NSRect, in parent: NSView, size: CGFloat = 14, color: NSColor = .white) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.frame = frame
    field.font = NSFont(name: "OpenSans-Regular", size: size) ?? .systemFont(ofSize: size)
    field.textColor = color
    field.isSelectable = false
    parent.addSubview(field)
    return field
}

@discardableResult
func picture(_ image: NSImage, frame: NSRect, in parent: NSView) -> NSImageView {
    let view = NSImageView(frame: frame)
    view.image = image; view.imageScaling = .scaleAxesIndependently
    view.setAccessibilityElement(false)
    parent.addSubview(view)
    return view
}

final class ActionTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke(_ sender: Any?) { action() }
}

final class OriginalWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
