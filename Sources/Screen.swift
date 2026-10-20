import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ScreenFrame {
    var rgba: [UInt8]
    var delay = 100

    init(color: UInt32 = 0, delay: Int = 100) {
        self.delay = delay
        rgba = Array(repeating: [UInt8((color >> 16) & 255), UInt8((color >> 8) & 255), UInt8(color & 255), 255], count: 240 * 135).flatMap { $0 }
    }

    init(image: CGImage, delay: Int) throws {
        self.delay = delay
        rgba = [UInt8](repeating: 0, count: 240 * 135 * 4)
        let success = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 240, height: 135, bitsPerComponent: 8,
                                          bytesPerRow: 240 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(NSColor.black.cgColor); context.fill(CGRect(x: 0, y: 0, width: 240, height: 135))
            context.interpolationQuality = .high
            let factor = min(240 / CGFloat(image.width), 135 / CGFloat(image.height))
            let width = CGFloat(image.width) * factor, height = CGFloat(image.height) * factor
            context.draw(image, in: CGRect(x: (240 - width) / 2, y: (135 - height) / 2, width: width, height: height))
            return true
        }
        guard success else { throw ToolError("无法创建屏幕图片缓冲区。") }
    }

    var cgImage: CGImage {
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(width: 240, height: 135, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 960,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    var image: NSImage { NSImage(cgImage: cgImage, size: NSSize(width: 240, height: 135)) }

    // MUI DLL 0x1003bd94–0x1003bdd2 emits little-endian RGB565, top row first.
    var rgb565: [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(64800)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let value = UInt16(rgba[index] & 0xf8) << 8 | UInt16(rgba[index + 1] & 0xfc) << 3 | UInt16(rgba[index + 2]) >> 3
            result += [UInt8(value & 255), UInt8(value >> 8)]
        }
        return result
    }
}

final class ScreenDocument {
    var frames = [ScreenFrame]()
    var selected = 0
    var undoFrame: ScreenFrame?
    var current: ScreenFrame? {
        get { frames.indices.contains(selected) ? frames[selected] : nil }
        set { if let newValue, frames.indices.contains(selected) { frames[selected] = newValue } }
    }

    func load(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= 100 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ToolError("无法读取图片或文件超过 100 MB。") }
        let count = CGImageSourceGetCount(source)
        guard (1...141).contains(count) else { throw ToolError("屏幕动画必须为 1–141 帧，当前为 \(count) 帧。") }
        var imported = [ScreenFrame]()
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw ToolError("第 \(index + 1) 帧无法解码。") }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let seconds = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ??
                          (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
            let delay = min(5100, max(20, Int((seconds * 1000).rounded())))
            imported.append(try ScreenFrame(image: image, delay: delay))
        }
        frames = imported; selected = 0; undoFrame = nil
    }

    func saveGIF(_ url: URL) throws {
        guard !frames.isEmpty, let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw ToolError("无法创建 GIF，请先添加图片帧。")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame.cgImage,
                                      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(frame.delay) / 1000]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ToolError("GIF 保存失败。") }
    }

    func addText(_ text: String, size: CGFloat, color: NSColor) throws {
        guard var frame = current else { throw ToolError("请先添加图片帧。") }
        undoFrame = frame
        let bitmap = NSBitmapImageRep(cgImage: frame.cgImage)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw ToolError("无法创建文字绘制上下文。") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: NSRect(x: 4, y: 45, width: 232, height: max(44, size * 1.5)),
                               withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: paragraph])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { throw ToolError("文字绘制失败。") }
        frame = try ScreenFrame(image: image, delay: frame.delay)
        current = frame
    }

    func packetData() throws -> [UInt8] {
        guard (1...141).contains(frames.count) else { throw ToolError("上传需要 1–141 帧图片。") }
        var header = [UInt8](repeating: 0xff, count: 256)
        header[0] = UInt8(frames.count)
        for (index, frame) in frames.enumerated() {
            guard frame.rgba.count == 240 * 135 * 4, (20...5100).contains(frame.delay) else { throw ToolError("屏幕帧尺寸或时长无效。") }
            header[index + 1] = UInt8(max(1, min(255, frame.delay / 20)))
        }
        var data = header + frames.flatMap(\.rgb565)
        let padding = (4096 - data.count % 4096) % 4096
        data += [UInt8](repeating: 0xff, count: padding)
        return data
    }
}

final class PixelCanvas: FlippedView {
    let document: ScreenDocument
    var color = NSColor.white
    var brush = 1
    var erasing = false
    var onChange: (() -> Void)?

    init(frame: NSRect, document: ScreenDocument) {
        self.document = document
        super.init(frame: frame)
        setAccessibilityLabel("240×135 屏幕图片编辑器")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        document.current?.image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSColor(rgb: 0xff9c00).setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
    override func mouseDown(with event: NSEvent) {
        document.undoFrame = document.current
        paint(event)
    }
    override func mouseDragged(with event: NSEvent) { paint(event) }
    private func paint(_ event: NSEvent) {
        guard var frame = document.current else { return }
        let point = convert(event.locationInWindow, from: nil)
        let column = Int(point.x * 240 / bounds.width), row = Int(point.y * 135 / bounds.height)
        guard (0..<240).contains(column), (0..<135).contains(row) else { return }
        let rgb = erasing ? UInt32(0) : color.rgbValue
        for posY in max(0, row - brush / 2)...min(134, row + brush / 2) {
            for posX in max(0, column - brush / 2)...min(239, column + brush / 2) {
                let offset = (posY * 240 + posX) * 4
                frame.rgba[offset] = UInt8((rgb >> 16) & 255); frame.rgba[offset + 1] = UInt8((rgb >> 8) & 255)
                frame.rgba[offset + 2] = UInt8(rgb & 255); frame.rgba[offset + 3] = 255
            }
        }
        document.current = frame; needsDisplay = true; onChange?()
    }
}
