import AppKit

func checkWirelessSettings(layout: [KeyboardKey]) throws {
    try checkWirelessControls()
    try checkWirelessTables(layout: layout)
    let device = KeyboardDevice()
    device.preferredConnection = .wireless
    try requireWireless(!device.supportsScreenUpload && !device.supportsLiveFrames, "无线模式须保留原驱动的 TFT 和实时帧限制")
    print("2.4G 离线自检通过：原生偏移、固定校验向量、普通/Fn 分包、RGB、宏、六行频谱及模式限制。未发送设备命令。")
}

private func requireWireless(_ valid: @autoclosure () -> Bool, _ message: String) throws {
    guard valid() else { throw ToolError("2.4G 自检失败：\(message)") }
}

private func checkWirelessControls() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29, hour: 23, minute: 59, second: 58))!
    let time = try WirelessProtocol.seal(WirelessProtocol.time(at: date, calendar: calendar))
    let expectedTime: [UInt8] = [0x0c, 0x10, 0, 0, 1, 0x5a, 24, 2, 29, 23, 59, 58, 0, 4, 0, 0, 0, 0xaa, 0x55] +
                               [UInt8](repeating: 0, count: 12) + [0x3d]
    try requireWireless(time == expectedTime, "0x423c40 校时帧及独立校验常量")
    var light = LightSettings(); light.color = 0x12ab34; light.brightness = 3; light.speed = 2; light.direction = 1
    let actualLight = try WirelessProtocol.seal(WirelessProtocol.light(light))
    let expectedLight: [UInt8] = [5, 0x10, 0, 11, 0x12, 0xab, 0x34, 0, 0, 0, 0, 1, 3, 2, 1, 0, 0, 0xaa, 0x55] +
                                [UInt8](repeating: 0, count: 12) + [0x17]
    try requireWireless(actualLight == expectedLight, "0x42b1e0 灯光帧及校验常量")
    var settings = SystemSettings(); settings.disableAltTab = true; settings.sleep = 3; settings.response = 5
    let system = try WirelessProtocol.seal(WirelessProtocol.system(settings))
    try requireWireless(Array(system.prefix(5)) == [7, 0x10, 0, 0, 1] && system[7] == 1 &&
                        system[9] == 3 && system[11] == 5 && system[31] == 0x20, "0x4144a0 系统配置偏移")
    let spectrum = try WirelessProtocol.spectrum([0, 0.5, 1] + [Float](repeating: 0, count: 18))
    try requireWireless(Array(spectrum.prefix(9)) == [0x0b, 0x1c, 0, 1, 0, 100, 0, 3, 6], "0x432b60 六行频谱")
    var rejected = false
    do { _ = try WirelessProtocol.spectrum([.nan]) } catch { rejected = true }
    try requireWireless(rejected, "无效频谱必须拒绝")
}

private func checkWirelessTables(layout: [KeyboardKey]) throws {
    var profile = DriverProfile()
    profile.keys["56"] = KeyBinding(kind: "key", value: 4, modifiers: 3, label: "Ctrl+Shift+A")
    let normal = try WirelessProtocol.bindings(profile, fnLayer: false, layout: layout)
    let fn = try WirelessProtocol.bindings(profile, fnLayer: true, layout: layout)
    try requireWireless(normal.count == 21 && normal.allSatisfy({ $0.count == 32 }), "普通层分为21个32字节报文")
    try requireWireless(Array(normal[0].prefix(3)) == [0x10, 28, 0] && Array(normal[20].prefix(3)) == [0x10, 16, 20], "普通层命令、尾包长度和序号")
    try requireWireless(Array(fn[0].prefix(3)) == [0x12, 28, 0] && Array(fn[20].prefix(3)) == [0x12, 16, 20], "Fn 层独立命令")
    try requireWireless(Array(normal[8][3..<7]) == [2, 3, 4, 0] && Array(normal[20][17...18]) == [0xaa, 0x55], "键位数据及结束标记")
    let colors = try WirelessProtocol.colors(["56": 0x12ab34], layout: layout)
    try requireWireless(colors.count == 22 && colors[0][0] == 5 && colors[0][3] == 0x80 && colors[0][12] == 5, "用户灯光模式设置")
    try requireWireless(Array(colors[9].prefix(7)) == [0x14, 28, 8, 56, 0x12, 0xab, 0x34], "逐键 RGB 分包")
    let macro = KeyboardMacro(name: "A", steps: [MacroStep(kind: "keyDown", usage: 4, delay: 100, label: "A"),
                                                MacroStep(kind: "keyUp", usage: 4, delay: 120, label: "A")])
    let macros = try WirelessProtocol.macros([macro])
    try requireWireless(macros.count == 17 && Array(macros[0].prefix(7)) == [9, 28, 0, 0x90, 1, 0, 0], "宏索引表及额外结束帧")
    try requireWireless(Array(macros[16].prefix(3)) == [9, 4, 16] && Array(macros[16][29...30]) == [0xaa, 0x55], "原宏协议尾包长度和标记位置")
}

@MainActor
func checkWirelessUI(_ controller: DriverController, output: URL) throws {
    guard let picker = controller.connectionPicker else { throw ToolError("连接选择器不存在。") }
    picker.selectItem(at: 2)
    try requireWireless(picker.sendAction(picker.action, to: picker.target), "连接选择器动作")
    try requireWireless(controller.keyboard.preferredConnection == .wireless, "选择器须实际切换配置后端")
    let pages = DriverPage.allCases.filter { ![.screen, .liveLight].contains($0) }
    for page in pages {
        controller.page = page; controller.render()
        try requireWireless(controller.navButtons.count == 7, "无线菜单须保留7个原生支持页面")
        try requireWireless(controller.navButtons.first(where: { $0.toolTip == page.title })?.active == true, "无线菜单选中状态")
        guard let bitmap = controller.root.bitmapImageRepForCachingDisplay(in: controller.root.bounds) else {
            throw ToolError("无法创建无线页面预览。")
        }
        controller.root.cacheDisplay(in: controller.root.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ToolError("无线预览编码失败。") }
        try png.write(to: output.appendingPathComponent("wireless-\(page.icon).png"))
    }
    controller.page = .screen; controller.render()
    try requireWireless(controller.page == .home, "无线模式不能误入屏幕上传页")
    controller.page = .liveLight; controller.render()
    try requireWireless(controller.page == .home, "无线模式不能误入有线实时帧页")
    controller.keyboard.preferredConnection = .usb; controller.page = .home; controller.render()
    print("2.4G 选择器、7页导航及无线功能限制检查通过，未发送设备命令。")
}
