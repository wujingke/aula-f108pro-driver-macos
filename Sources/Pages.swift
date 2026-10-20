import AppKit
import ServiceManagement
import UniformTypeIdentifiers

extension DriverController {
    func renderHome() {
        picture(resources.image("home_bkg.png"), frame: content.bounds, in: content)
        label("AULA F108Pro", frame: NSRect(x: 380, y: 45, width: 600, height: 55), in: content, size: 34)
        let image = connected ? "device/home_keyboard_connected.png" : "device/home_keyboard_disconnected.png"
        picture(resources.image(image), frame: NSRect(x: 120, y: 100, width: 1000, height: 400), in: content)
        button("进入我的专属配置", rect: NSRect(x: 390, y: 510, width: 220, height: 36)) { [weak self] in self?.select(.keys) }
        button("时间校正", rect: NSRect(x: 635, y: 510, width: 180, height: 36)) { [weak self] in
            guard let self else { return }; perform("时间校正") { try self.keyboard.syncTime() }
        }
        label(keyboard.currentConnection.rawValue, frame: NSRect(x: 500, y: 563, width: 300, height: 30), in: content, size: 14, color: .lightGray)
    }

    func renderKeys() {
        profilePicker()
        let view = addKeyboard()
        view.bindings = fnLayer ? store.current.fnKeys : store.current.keys
        let index = selectedKeys.first
        let current = index.flatMap { (fnLayer ? store.current.fnKeys : store.current.keys)[String($0)] }
        let choices = ["默认按键", "禁用按键", "单键 / 组合键", "多媒体", "鼠标功能", "宏定义"]
        let kinds = ["default", "disabled", "key", "media", "mouse", "macro"]
        let kind = current?.kind ?? "key"
        let binding = current ?? KeyBinding(kind: kind, value: 4, label: "A")
        label("按键类型", frame: NSRect(x: 25, y: 120, width: 240, height: 25), in: content)
        _ = popup(choices, selected: kinds.firstIndex(of: kind)!, rect: NSRect(x: 25, y: 150, width: 240, height: 30), title: "按键类型") { [weak self] selected in
            guard let self else { return }
            selectBindingKind(kinds[selected], label: choices[selected])
        }
        label("按键功能", frame: NSRect(x: 25, y: 200, width: 240, height: 25), in: content)
        switch kind {
        case "key":
            let keys = resources.layout.filter { $0.usage != 0xaf }
            _ = popup(keys.map(\.name), selected: keys.firstIndex(where: { $0.usage == binding.value }) ?? 0,
                  rect: NSRect(x: 25, y: 235, width: 240, height: 30), title: "目标按键") { [weak self] selected in
                var changed = binding; changed.value = keys[selected].usage; changed.label = keys[selected].name
                self?.saveBinding(changed)
            }
            for (offset, item) in [(1, "Ctrl"), (2, "Shift"), (4, "Alt"), (8, "Command")].enumerated() {
                checkBox(item.1, value: binding.modifiers & item.0 != 0,
                         rect: NSRect(x: 25 + offset % 2 * 120, y: 282 + offset / 2 * 34, width: 120, height: 28)) { [weak self] enabled in
                    var changed = binding
                    changed.modifiers = enabled ? binding.modifiers | item.0 : binding.modifiers & ~item.0
                    self?.saveBinding(changed)
                }
            }
        case "media":
            let values = [0xcd, 0xb7, 0xb6, 0xb5, 0xe9, 0xea, 0xe2]
            let names = ["播放/暂停", "停止", "上一首", "下一首", "音量 +", "音量 -", "静音"]
            _ = popup(names, selected: values.firstIndex(of: binding.value) ?? 0, rect: NSRect(x: 25, y: 235, width: 240, height: 30), title: "多媒体功能") { [weak self] selected in
                self?.saveBinding(KeyBinding(kind: "media", value: values[selected], label: names[selected]))
            }
        case "mouse":
            let names = ["左键单击", "中键单击", "右键单击", "双击", "向上滚动", "向下滚动", "鼠标按钮4", "鼠标按钮5"]
            _ = popup(names, selected: max(0, binding.value - 1), rect: NSRect(x: 25, y: 235, width: 240, height: 30), title: "鼠标功能") { [weak self] selected in
                self?.saveBinding(KeyBinding(kind: "mouse", value: selected + 1, label: names[selected]))
            }
        case "macro":
            let macros = store.current.macros
            if macros.isEmpty {
                label("请先在宏管理器中新建宏。", frame: NSRect(x: 25, y: 235, width: 240, height: 60), in: content, size: 13)
                button("打开宏管理器", rect: NSRect(x: 25, y: 310, width: 200, height: 32)) { [weak self] in self?.select(.macros) }
            } else {
                _ = popup(macros.map(\.name), selected: macros.firstIndex(where: { $0.id == binding.macroID }) ?? 0,
                      rect: NSRect(x: 25, y: 235, width: 240, height: 30), title: "选择宏") { [weak self] selected in
                    self?.saveBinding(KeyBinding(kind: "macro", value: 0, macroID: macros[selected].id, label: macros[selected].name))
                }
                label("循环次数（1–255）", frame: NSRect(x: 25, y: 285, width: 240, height: 25), in: content, size: 13)
                _ = editor(String(binding.repeatCount), rect: NSRect(x: 25, y: 315, width: 100, height: 28), title: "宏循环次数") { [weak self] text in
                    guard let self, let value = Int(text), (1...255).contains(value) else { self?.setStatus("循环次数必须为 1–255。", error: true); return }
                    var changed = binding; changed.repeatCount = value; saveBinding(changed)
                }
            }
        default:
            label(kind == "disabled" ? "选中按键将被禁用。" : "使用键盘固件的默认功能。", frame: NSRect(x: 25, y: 235, width: 240, height: 70), in: content, size: 13)
        }
        button("单键", rect: NSRect(x: 360, y: 420, width: 160, height: 30), sprite: fnLayer ? "img_btn_layer_n.png" : "img_btn_layer_p.png") { [weak self] in
            self?.fnLayer = false; self?.render()
        }
        button("Fn 组合键", rect: NSRect(x: 535, y: 420, width: 160, height: 30), sprite: fnLayer ? "img_btn_layer_p.png" : "img_btn_layer_n.png") { [weak self] in
            self?.fnLayer = true; self?.render()
        }
        label(selectedKeyDescription(), frame: NSRect(x: 360, y: 470, width: 760, height: 65), in: content, size: 14)
        button("新建", rect: NSRect(x: 25, y: 420, width: 72, height: 30)) { [weak self] in self?.store.add(); self?.persist(); self?.render() }
        button("导入", rect: NSRect(x: 105, y: 420, width: 72, height: 30)) { [weak self] in self?.importProfiles() }
        button("导出", rect: NSRect(x: 185, y: 420, width: 72, height: 30)) { [weak self] in self?.exportProfiles() }
        button("重命名", rect: NSRect(x: 25, y: 465, width: 110, height: 30)) { [weak self] in self?.renameProfile() }
        button("删除", rect: NSRect(x: 147, y: 465, width: 110, height: 30)) { [weak self] in
            guard let self else { return }
            do { try store.removeCurrent(); persist(); render() } catch { present(error) }
        }
        button("应用", rect: NSRect(x: 1010, y: 565, width: 100, height: 30), sprite: "btn_apply.png") { [weak self] in
            guard let self else { return }
            let profile = store.current, layer = fnLayer
            confirm("将以“\(profile.name)”覆盖键盘的\(layer ? "Fn 组合键" : "单键")配置。未在此方案定义的键将恢复默认；现有键盘映射尚未读入本方案。") { [weak self] in
                guard let self else { return }
                perform("写入按键配置") {
                    if (layer ? profile.fnKeys : profile.keys).values.contains(where: { $0.kind == "macro" }) { try self.keyboard.applyMacros(profile.macros) }
                    try self.keyboard.applyBindings(profile, fnLayer: layer, layout: self.resources.layout)
                }
            }
        }
    }

    func selectedKeyDescription() -> String {
        guard let index = selectedKeys.first, let key = resources.layout.first(where: { $0.index == index }) else {
            return "点击键盘上的按键，选择需要设置的功能。橙色圆点表示本地方案中的自定义键。"
        }
        let value = (fnLayer ? store.current.fnKeys : store.current.keys)[String(index)]?.label ?? "默认按键"
        return "\(fnLayer ? "Fn + " : "")\(key.name) → \(value)"
    }

    func selectBindingKind(_ kind: String, label: String) {
        var binding = KeyBinding(kind: kind, value: 0, label: label)
        if kind == "key" { binding.value = 4; binding.label = "A" }
        if kind == "media" { binding.value = 0xcd; binding.label = "播放/暂停" }
        if kind == "mouse" { binding.value = 1; binding.label = "左键单击" }
        if kind == "macro" {
            guard let macro = store.current.macros.first else { select(.macros); return }
            binding.macroID = macro.id; binding.label = macro.name
        }
        saveBinding(binding)
    }

    func saveBinding(_ binding: KeyBinding) {
        guard !selectedKeys.isEmpty else { setStatus("请先点击键盘选择按键。", error: true); return }
        var profile = store.current
        for index in selectedKeys {
            if fnLayer { profile.fnKeys[String(index)] = binding } else { profile.keys[String(index)] = binding }
        }
        do { try profile.validate(layout: resources.layout) } catch { present(error); return }
        store.current = profile; persist(); render()
    }

    func renameProfile() {
        let alert = NSAlert(); alert.messageText = "重命名配置"
        let field = NSTextField(string: store.current.name); field.frame = NSRect(x: 0, y: 0, width: 300, height: 28)
        alert.accessoryView = field; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { setStatus("名称不能为空。", error: true); return }
            store.current.name = name; persist(); render()
        }
    }

    func renderLight() {
        profilePicker()
        let modeNames = ["默认灯效"] + (521...540).map(resources.text)
        _ = popup(modeNames, selected: store.current.light.mode, rect: NSRect(x: 25, y: 125, width: 240, height: 32), title: "灯光模式") { [weak self] value in
            self?.store.current.light.mode = value; self?.persist()
        }
        let view = addKeyboard()
        view.colors = Dictionary(uniqueKeysWithValues: resources.layout.map { (String($0.index), store.current.light.color) })
        _ = colorWell(NSColor(rgb: store.current.light.color), rect: NSRect(x: 25, y: 205, width: 100, height: 35), title: "灯光颜色") { [weak self] color in
            guard let self else { return }
            store.current.light.color = color.rgbValue
            keyboardView?.colors = Dictionary(uniqueKeysWithValues: resources.layout.map { (String($0.index), color.rgbValue) })
            persist()
        }
        checkBox("多彩", value: store.current.light.colorful, rect: NSRect(x: 145, y: 207, width: 110, height: 30)) { [weak self] value in
            self?.store.current.light.colorful = value; self?.persist()
        }
        slider("灯光亮度", value: store.current.light.brightness, range: 0...5, rect: NSRect(x: 25, y: 300, width: 240, height: 25)) { [weak self] value in
            self?.store.current.light.brightness = value; self?.persist()
        }
        slider("灯光速度", value: store.current.light.speed, range: 0...5, rect: NSRect(x: 25, y: 375, width: 240, height: 25)) { [weak self] value in
            self?.store.current.light.speed = value; self?.persist()
        }
        _ = popup(["默认方向", "向左", "向右", "反向"], selected: store.current.light.direction,
              rect: NSRect(x: 25, y: 450, width: 240, height: 30), title: "灯光方向") { [weak self] value in
            self?.store.current.light.direction = value; self?.persist()
        }
        button("应用", rect: NSRect(x: 1010, y: 565, width: 100, height: 30), sprite: "btn_apply.png") { [weak self] in
            guard let self else { return }; let settings = store.current.light
            perform("应用灯光模式") { try self.keyboard.applyLight(settings) }
        }
    }

    func renderUserLight() {
        profilePicker()
        let view = addKeyboard(multiple: true); view.colors = store.current.colors
        label("自定义灯光", frame: NSRect(x: 25, y: 125, width: 240, height: 30), in: content, size: 17)
        _ = colorWell(paintColor, rect: NSRect(x: 25, y: 175, width: 100, height: 38), title: "逐键颜色") { [weak self] color in self?.paintColor = color }
        button("全选", rect: NSRect(x: 25, y: 240, width: 110, height: 30)) { [weak self] in
            guard let self else { return }; selectedKeys = Set(resources.layout.map(\.index)); keyboardView?.selected = selectedKeys
        }
        button("清除选择", rect: NSRect(x: 145, y: 240, width: 110, height: 30)) { [weak self] in self?.selectedKeys.removeAll(); self?.keyboardView?.selected = [] }
        button("着色", rect: NSRect(x: 25, y: 290, width: 110, height: 32)) { [weak self] in self?.paintKeys(live: false, clear: false) }
        button("熄灭", rect: NSRect(x: 145, y: 290, width: 110, height: 32)) { [weak self] in self?.paintKeys(live: false, clear: true) }
        button("导入", rect: NSRect(x: 25, y: 365, width: 110, height: 30)) { [weak self] in self?.importProfiles() }
        button("导出", rect: NSRect(x: 145, y: 365, width: 110, height: 30)) { [weak self] in self?.exportProfiles() }
        label("选择一个或多个按键后着色。未着色的按键在此方案中为熄灭。", frame: NSRect(x: 355, y: 435, width: 730, height: 60), in: content)
        button("应用", rect: NSRect(x: 1010, y: 565, width: 100, height: 30), sprite: "btn_apply.png") { [weak self] in
            guard let self else { return }; let colors = store.current.colors
            perform("应用用户灯光") { try self.keyboard.applyColors(colors, layout: self.resources.layout) }
        }
    }

    func paintKeys(live: Bool, clear: Bool) {
        guard !selectedKeys.isEmpty else { setStatus("请先选择按键。", error: true); return }
        let color = clear ? UInt32(0) : paintColor.rgbValue
        for index in selectedKeys {
            if live { store.current.frames[selectedLightFrame].colors[String(index)] = color }
            else { store.current.colors[String(index)] = color }
        }
        keyboardView?.colors = live ? store.current.frames[selectedLightFrame].colors : store.current.colors
        persist()
    }

    func renderLiveLight() {
        profilePicker()
        if store.current.frames.isEmpty { store.current.frames = [LightFrame()] }
        selectedLightFrame = min(selectedLightFrame, store.current.frames.count - 1)
        let view = addKeyboard(multiple: true); view.colors = store.current.frames[selectedLightFrame].colors
        let items = store.current.frames.enumerated().map { "第 \($0.offset + 1) 帧 · \($0.element.duration) ms" }
        _ = popup(items, selected: selectedLightFrame, rect: NSRect(x: 25, y: 125, width: 240, height: 30), title: "灯光帧") { [weak self] value in
            self?.selectedLightFrame = value; self?.render()
        }
        _ = colorWell(paintColor, rect: NSRect(x: 25, y: 185, width: 100, height: 35), title: "帧颜色") { [weak self] color in self?.paintColor = color }
        button("全选", rect: NSRect(x: 145, y: 185, width: 110, height: 32)) { [weak self] in
            guard let self else { return }; selectedKeys = Set(resources.layout.map(\.index)); keyboardView?.selected = selectedKeys
        }
        button("着色", rect: NSRect(x: 25, y: 240, width: 110, height: 30)) { [weak self] in self?.paintKeys(live: true, clear: false) }
        button("熄灭", rect: NSRect(x: 145, y: 240, width: 110, height: 30)) { [weak self] in self?.paintKeys(live: true, clear: true) }
        label("帧延时（20–5000 ms）", frame: NSRect(x: 25, y: 300, width: 240, height: 25), in: content, size: 13)
        _ = editor(String(store.current.frames[selectedLightFrame].duration), rect: NSRect(x: 25, y: 330, width: 120, height: 28), title: "灯光帧延时") { [weak self] text in
            guard let self, let value = Int(text), (20...5000).contains(value) else { self?.setStatus("延时必须为 20–5000 ms。", error: true); return }
            store.current.frames[selectedLightFrame].duration = value; persist()
        }
        button("新建帧", rect: NSRect(x: 25, y: 385, width: 110, height: 30)) { [weak self] in
            guard let self, store.current.frames.count < 141 else { return }
            store.current.frames.append(LightFrame()); selectedLightFrame = store.current.frames.count - 1; persist(); render()
        }
        button("复制帧", rect: NSRect(x: 145, y: 385, width: 110, height: 30)) { [weak self] in
            guard let self, store.current.frames.count < 141 else { return }
            store.current.frames.append(store.current.frames[selectedLightFrame]); selectedLightFrame = store.current.frames.count - 1; persist(); render()
        }
        button("删除帧", rect: NSRect(x: 25, y: 430, width: 110, height: 30)) { [weak self] in
            guard let self, store.current.frames.count > 1 else { return }
            store.current.frames.remove(at: selectedLightFrame); selectedLightFrame = max(0, selectedLightFrame - 1); persist(); render()
        }
        button(playbackTimer == nil ? "播放" : "停止", rect: NSRect(x: 1010, y: 565, width: 100, height: 30), sprite: "btn_apply.png") { [weak self] in
            guard let self else { return }; if playbackTimer == nil { startPlayback(music: false) } else { stopPlayback(); render() }
        }
        button("导入", rect: NSRect(x: 360, y: 470, width: 110, height: 30)) { [weak self] in self?.importProfiles() }
        button("导出", rect: NSRect(x: 485, y: 470, width: 110, height: 30)) { [weak self] in self?.exportProfiles() }
        label("播放期间由 Mac 持续向键盘推送灯光帧。", frame: NSRect(x: 360, y: 425, width: 700, height: 30), in: content)
    }

    func renderMusic() {
        profilePicker()
        addKeyboard().colors = [:]
        label("音乐律动", frame: NSRect(x: 25, y: 130, width: 240, height: 35), in: content, size: 18)
        label("采集 Mac 系统音频生成灯效。首次开始时需要在系统设置允许屏幕与系统音频录制。", frame: NSRect(x: 25, y: 185, width: 240, height: 115), in: content, size: 13)
        slider("振幅", value: 2, range: 1...5, rect: NSRect(x: 25, y: 350, width: 240, height: 25)) { [weak self] value in self?.audio?.gain = Float(value) / 2 }
        button(playbackTimer == nil ? "开始音乐律动" : "停止", rect: NSRect(x: 25, y: 420, width: 240, height: 35)) { [weak self] in
            guard let self else { return }; if playbackTimer == nil { startPlayback(music: true) } else { stopPlayback(); render() }
        }
    }

    func renderSettings() {
        profilePicker()
        let settings = store.current.system
        label("键盘休眠时间设定", frame: NSRect(x: 340, y: 75, width: 250, height: 30), in: content, size: 17)
        _ = popup(["不休眠", "1分钟", "5分钟", "30分钟"], selected: settings.sleep,
              rect: NSRect(x: 340, y: 120, width: 260, height: 32), title: "休眠时间") { [weak self] value in self?.store.current.system.sleep = value; self?.persist() }
        label("按键响应时间", frame: NSRect(x: 720, y: 75, width: 260, height: 30), in: content, size: 17)
        _ = popup(["一档", "二档", "三档", "四档", "五档"], selected: settings.response - 1,
              rect: NSRect(x: 720, y: 120, width: 260, height: 32), title: "按键响应档位") { [weak self] value in self?.store.current.system.response = value + 1; self?.persist() }
        label("响应档位过低可能引起按键连击，如出现连击请调高档位。", frame: NSRect(x: 720, y: 170, width: 350, height: 55), in: content, size: 13, color: .lightGray)
        checkBox("禁用 Window键", value: settings.disableWin, rect: NSRect(x: 340, y: 250, width: 300, height: 32)) { [weak self] value in self?.store.current.system.disableWin = value; self?.persist() }
        checkBox("禁用 ALT + F4", value: settings.disableAltF4, rect: NSRect(x: 340, y: 305, width: 300, height: 32)) { [weak self] value in
            self?.store.current.system.disableAltF4 = value; self?.persist()
        }
        checkBox("禁用 ALT + TAB", value: settings.disableAltTab, rect: NSRect(x: 340, y: 360, width: 300, height: 32)) { [weak self] value in
            self?.store.current.system.disableAltTab = value; self?.persist()
        }
        checkBox("Fn 开关功能", value: settings.fnSwitch, rect: NSRect(x: 720, y: 250, width: 300, height: 32)) { [weak self] value in self?.store.current.system.fnSwitch = value; self?.persist() }
        checkBox("开机启动", value: SMAppService.mainApp.status == .enabled,
                 rect: NSRect(x: 25, y: 140, width: 240, height: 32)) { [weak self] enabled in
            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { self?.present(error) }
        }
        button("时间校正", rect: NSRect(x: 25, y: 210, width: 220, height: 35)) { [weak self] in
            guard let self else { return }; perform("时间校正") { try self.keyboard.syncTime() }
        }
        button("应用", rect: NSRect(x: 1010, y: 565, width: 100, height: 30), sprite: "btn_apply.png") { [weak self] in
            guard let self else { return }; let settings = store.current.system
            perform("应用系统配置") { try self.keyboard.applySystem(settings) }
        }
    }
}
