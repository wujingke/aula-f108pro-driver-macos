import AppKit

@MainActor
func checkSliderDragging(_ resources: DriverResources, parent: NSView, output: URL) throws {
    func makeSlider() -> SkinSlider {
        let slider = SkinSlider(frame: NSRect(x: 18, y: 10, width: 330, height: 28))
        slider.bar = resources.image("img_slider_back.png"); slider.thumb = resources.image("img_thumb.png")
        slider.minValue = 0; slider.maxValue = 5
        parent.addSubview(slider)
        return slider
    }
    let slider = makeSlider()
    defer { slider.removeFromSuperview() }
    var changes = 0
    let target = ActionTarget { changes += 1 }
    defer { withExtendedLifetime(target) {} }
    slider.target = target; slider.action = #selector(ActionTarget.invoke(_:))
    func mouse(_ type: NSEvent.EventType, value: Int) throws -> NSEvent {
        let point = slider.convert(NSPoint(x: 10 + 310 * Double(value) / 5, y: 13), to: nil)
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                            windowNumber: parent.window!.windowNumber, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 1) else {
            throw ToolError("无法创建滑块拖动回归事件。")
        }
        return event
    }
    slider.mouseDown(with: try mouse(.leftMouseDown, value: 5))
    for value in [4, 3, 2, 1, 0, 2, 4, 1, 5, 3, 0, 5, 2] {
        slider.mouseDragged(with: try mouse(.leftMouseDragged, value: value))
        parent.window?.makeFirstResponder(nil)
        guard slider.integerValue == value else { throw ToolError("滑块连续拖动取值错误。") }
        let actual = try renderedSlider(slider)
        let reference = makeSlider()
        reference.integerValue = value; reference.isHighlighted = true
        let expected = try renderedSlider(reference)
        reference.removeFromSuperview()
        guard pixels(actual) == pixels(expected) else { throw ToolError("滑块连续拖动后存在残影，当前值：\(value)。") }
    }
    slider.mouseUp(with: try mouse(.leftMouseUp, value: 2))
    guard !slider.isHighlighted, changes >= 13 else { throw ToolError("滑块松开状态或连续变更回调错误。") }
    guard slider.accessibilityPerformIncrement(), slider.integerValue == 3,
          slider.accessibilityPerformDecrement(), slider.integerValue == 2 else {
        throw ToolError("滑块辅助功能增减操作失败。")
    }
    let final = try renderedSlider(slider)
    guard let png = final.representation(using: .png, properties: [:]) else { throw ToolError("滑块拖动回归图片编码失败。") }
    try png.write(to: output.appendingPathComponent("slider-drag-regression.png"))
    print("滑块连续拖动回归通过：13 次往返移动、逐帧与干净绘制比较、松开及增减回调。")
}

@MainActor
private func renderedSlider(_ slider: SkinSlider) throws -> NSBitmapImageRep {
    slider.displayIfNeeded(); slider.layer?.displayIfNeeded()
    guard let layer = slider.layer,
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 660, pixelsHigh: 56, bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 2640, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw ToolError("无法读取滑块当前图层。")
    }
    context.cgContext.clear(CGRect(x: 0, y: 0, width: 660, height: 56))
    context.cgContext.scaleBy(x: 2, y: 2)
    layer.render(in: context.cgContext)
    guard let center = bitmap.colorAt(x: 330, y: 28), center.alphaComponent > 0.9 else {
        throw ToolError("滑块图层尚未绘制，不能将空图层当作回归通过。")
    }
    return bitmap
}

private func pixels(_ bitmap: NSBitmapImageRep) -> Data {
    Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
}
