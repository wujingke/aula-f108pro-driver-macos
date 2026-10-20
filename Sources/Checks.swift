import AppKit

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ToolError("自检失败：\(message)") }
}

func runDriverTests(resources: DriverResources) throws {
    try selfTest()
    try checkWirelessTransport()
    try checkWirelessSettings(layout: resources.layout)
    try require(resources.image("img_thumb.png").size == NSSize(width: 80, height: 20), "96 DPI 圆点精灵图须按像素坐标裁切")
    try require(resources.image("btn_checkbox.png").size == NSSize(width: 240, height: 30), "96 DPI 复选框图片坐标")
    var light = LightSettings()
    light.color = 0x12ab34; light.brightness = 3; light.speed = 2; light.direction = 1
    let lightPacket = try KeyboardProtocol.light(light)
    try require(Array(lightPacket[0...3]) == [11, 0x12, 0xab, 0x34], "灯光模式和 RGB 顺序")
    try require(Array(lightPacket[8...15]) == [1, 3, 2, 1, 0, 0, 0xaa, 0x55], "灯光参数位置和结束标记")
    var system = SystemSettings(); system.disableAltTab = true; system.sleep = 3; system.response = 5
    let systemPacket = try KeyboardProtocol.system(system)
    try require(systemPacket[4] == 1 && systemPacket[6] == 3 && systemPacket[8] == 5, "系统配置编码")
    let key = resources.layout.first(where: { $0.name == "A" })!
    let map = [String(key.index): KeyBinding(kind: "key", value: 4, modifiers: 3, label: "Ctrl+Shift+A")]
    let bindingPacket = try KeyboardProtocol.bindings(map, macros: [], layout: resources.layout)
    try require(Array(bindingPacket[key.index * 4..<key.index * 4 + 4]) == [2, 3, 4, 0], "改键与修饰键编码")
    try require(bindingPacket.count == 576 && Array(bindingPacket.suffix(2)) == [0xaa, 0x55], "改键分包及结束标记")
    let colors = try KeyboardProtocol.colors([String(key.index): 0x12ab34], layout: resources.layout)
    try require(Array(colors[key.lightIndex * 4..<key.lightIndex * 4 + 4]) == [UInt8(key.lightIndex), 0x12, 0xab, 0x34], "逐键 RGB 索引")
    let macro = KeyboardMacro(name: "A", steps: [MacroStep(kind: "keyDown", usage: 4, delay: 100, label: "A"),
                                                MacroStep(kind: "keyUp", usage: 4, delay: 120, label: "A")])
    let macros = try KeyboardProtocol.macros([macro])
    try require(Array(macros.prefix(4)) == [0x90, 1, 0, 0], "宏索引表偏移 400")
    try require(Array(macros[400..<408]) == [4, 0, 0, 0, 0, 0, 0, 0], "宏事件计数")
    try require(Array(macros[408..<416]) == [0, 0, 4, 0xb0, 100, 0, 0, 0x50], "宏键盘按下和延时")
    try require(macros.count % 64 == 0 && Array(macros.suffix(2)) == [0xaa, 0x55], "宏数据分包")
    let document = ScreenDocument()
    document.frames = [ScreenFrame(color: 0xff0000)]
    try require(Array(document.frames[0].rgb565.prefix(2)) == [0, 0xf8], "RGB565 红色字节序")
    try require(Array(ScreenFrame(color: 0x00ff00).rgb565.prefix(2)) == [0xe0, 7], "RGB565 绿色字节序")
    try require(Array(ScreenFrame(color: 0x0000ff).rgb565.prefix(2)) == [0x1f, 0], "RGB565 蓝色字节序")
    let screenData = try document.packetData()
    try require(screenData[0] == 1 && screenData[1] == 5 && Array(screenData[256..<258]) == [0, 0xf8], "屏幕帧数、20 ms 单位和像素偏移")
    try require(screenData.count % 4096 == 0, "屏幕 4096 字节分块")
    try testProfileRoundTrip(resources)
    print("驱动自检通过：灯效、系统设置、改键、逐键 RGB、宏编码、RGB565、屏幕分包、配置导入边界。")
}

private func testProfileRoundTrip(_ resources: DriverResources) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("f108-self-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: folder) } catch { print("自检临时目录清理失败：\(error)") } }
    let store = try ProfileStore(layout: resources.layout, ephemeral: true)
    let file = folder.appendingPathComponent("test.json")
    try store.export(to: file)
    try store.load(from: file)
    try require(store.profiles.count == 1, "配置往返")
    var invalid = ProfileFile(profiles: store.profiles, selected: store.selected)
    invalid.version = 999
    try JSONEncoder().encode(invalid).write(to: file)
    var rejected = false
    do { try store.load(from: file) } catch { rejected = true }
    try require(rejected, "未知配置版本必须被拒绝")
    let gif = folder.appendingPathComponent("test.gif")
    let document = ScreenDocument(); document.frames = [ScreenFrame(color: 0x12ab34, delay: 120)]
    try document.saveGIF(gif); try document.load(gif)
    try require(document.frames.count == 1 && document.frames[0].delay == 120, "GIF 帧和延时往返")
}

@MainActor
func runUITests(_ controller: DriverController) throws {
    controller.createWindow()
    controller.keyboard.preferredConnection = .usb
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/previews")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for page in DriverPage.allCases {
        controller.page = page; controller.render()
        controller.root.layoutSubtreeIfNeeded()
        try require(controller.navButtons.count == DriverPage.allCases.count, "导航页数量")
        try require(controller.navButtons[page.rawValue].active, "导航选中状态")
        if let keyboard = controller.keyboardView {
            try require(keyboard.subviews.count == 104, "104 个可操作键位")
            for child in keyboard.subviews { try require(keyboard.bounds.contains(child.frame), "按键点击范围") }
        }
        guard let bitmap = controller.root.bitmapImageRepForCachingDisplay(in: controller.root.bounds) else {
            throw ToolError("无法生成界面预览。")
        }
        controller.root.cacheDisplay(in: controller.root.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ToolError("界面预览编码失败。") }
        try png.write(to: output.appendingPathComponent("\(page.rawValue)-\(page.icon).png"))
        print("UI 检查通过：\(page.title)")
    }
    controller.page = .keys; controller.selectedKeys = [56]; controller.render()
    controller.saveBinding(KeyBinding(kind: "disabled", value: 0, label: "禁用按键"))
    try require(controller.store.current.keys["56"]?.kind == "disabled", "按键编辑交互")
    try checkSliderRendering(controller.resources, parent: controller.root, output: output)
    try checkWirelessUI(controller, output: output)
    controller.window.close()
    print("9 个页面及按键编辑检查通过，预览已保存至 \(output.path)。未向设备写入。")
}

@MainActor
private func checkSliderRendering(_ resources: DriverResources, parent: NSView, output: URL) throws {
    let panel = FlippedView(frame: NSRect(x: 0, y: 0, width: 420, height: 270))
    panel.wantsLayer = true; panel.layer?.backgroundColor = NSColor(rgb: 0x241830).cgColor
    parent.addSubview(panel)
    defer { panel.removeFromSuperview() }
    for (row, state) in [(0, false), (3, false), (5, false), (0, true), (3, true), (5, true)].enumerated() {
        let slider = SkinSlider(frame: NSRect(x: 18, y: row * 44 + 10, width: 330, height: 28))
        slider.bar = resources.image("img_slider_back.png"); slider.thumb = resources.image("img_thumb.png")
        slider.minValue = 0; slider.maxValue = 5; slider.integerValue = state.0
        slider.isHighlighted = state.1; panel.addSubview(slider)
        try require(slider.knobThickness == 20, "滑块绘制与点击区域的圆点直径必须一致")
        label("\(state.0) \(state.1 ? "按下" : "正常")", frame: NSRect(x: 355, y: row * 44 + 14, width: 65, height: 25), in: panel, size: 12)
    }
    guard let bitmap = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) else { throw ToolError("无法生成滑块回归预览。") }
    panel.cacheDisplay(in: panel.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ToolError("滑块预览编码失败。") }
    try png.write(to: output.appendingPathComponent("sliders-regression.png"))
    print("滑块回归检查通过：最小/中间/最大位置，正常/按下两种状态。")
    try checkSliderDragging(resources, parent: parent, output: output)
}

private func checkWirelessTransport() throws {
    let probe = try WirelessProtocol.seal(WirelessProtocol.packet(command: 2))
    try require(probe.count == 32 && probe[0] == 2 && probe[31] == 2, "2.4G 去除零 Report ID 后的握手报文长度和校验和")
    let overflow = try WirelessProtocol.seal([UInt8](repeating: 255, count: 32))
    try require(overflow[31] == 0xe1, "2.4G 校验和按低八位回绕")
    var rejected = false
    do { _ = try WirelessProtocol.seal([0, 1]) } catch { rejected = true }
    try require(rejected, "2.4G 短报文必须拒绝")
}
