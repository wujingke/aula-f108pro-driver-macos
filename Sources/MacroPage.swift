import AppKit

extension DriverController {
    func renderMacros() {
        profilePicker()
        let macros = store.current.macros
        selectedMacro = min(selectedMacro, max(0, macros.count - 1))
        if !macros.isEmpty {
            popup(macros.map(\.name), selected: selectedMacro, rect: NSRect(x: 25, y: 125, width: 240, height: 32), title: "宏列表") { [weak self] value in
                self?.selectedMacro = value; self?.selectedStep = 0; self?.render()
            }
            editor(macros[selectedMacro].name, rect: NSRect(x: 25, y: 180, width: 240, height: 28), title: "宏名称") { [weak self] text in
                guard let self, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                store.current.macros[selectedMacro].name = text; persist()
            }
        }
        button("新建", rect: NSRect(x: 25, y: 240, width: 110, height: 30)) { [weak self] in
            guard let self, store.current.macros.count < 100 else { return }
            store.current.macros.append(KeyboardMacro(name: "新建宏 \(macros.count + 1)"))
            selectedMacro = store.current.macros.count - 1; persist(); render()
        }
        button("删除", rect: NSRect(x: 145, y: 240, width: 110, height: 30)) { [weak self] in
            guard let self, !store.current.macros.isEmpty else { return }
            let identifier = store.current.macros[selectedMacro].id
            store.current.macros.remove(at: selectedMacro)
            store.current.keys = store.current.keys.filter { $0.value.macroID != identifier }
            store.current.fnKeys = store.current.fnKeys.filter { $0.value.macroID != identifier }
            selectedMacro = max(0, selectedMacro - 1); persist(); render()
        }
        button(recorder == nil ? "开始录制" : "停止录制", rect: NSRect(x: 25, y: 305, width: 230, height: 35)) { [weak self] in self?.toggleRecording() }
        button("导入", rect: NSRect(x: 25, y: 365, width: 110, height: 30)) { [weak self] in self?.importProfiles() }
        button("导出", rect: NSRect(x: 145, y: 365, width: 110, height: 30)) { [weak self] in self?.exportProfiles() }
        label("录制键盘和鼠标动作。Esc 停止录制。宏存储在本地，保存到键盘后可在改键页绑定。",
              frame: NSRect(x: 25, y: 425, width: 240, height: 110), in: content, size: 13, color: .lightGray)
        label("动作记录列表", frame: NSRect(x: 340, y: 35, width: 700, height: 30), in: content, size: 20)
        let scroll = NSScrollView(frame: NSRect(x: 340, y: 85, width: 760, height: 375))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = true; scroll.backgroundColor = NSColor(rgb: 0x18131f)
        let steps = macros.isEmpty ? [] : macros[selectedMacro].steps
        let list = FlippedView(frame: NSRect(x: 0, y: 0, width: 740, height: max(375, steps.count * 34)))
        for (index, step) in steps.enumerated() {
            let names = ["keyDown": "按下", "keyUp": "松开", "mouseDown": "按下", "mouseUp": "松开", "delay": "延时"]
            let row = button("\(index + 1).   \(step.label)    \(names[step.kind]!)    \(step.delay) ms",
                             rect: NSRect(x: 0, y: index * 34, width: 735, height: 32), parent: list) { [weak self] in
                self?.selectedStep = index; self?.render()
            }
            row.active = selectedStep == index
        }
        scroll.documentView = list; content.addSubview(scroll)
        button("插入按键", rect: NSRect(x: 340, y: 480, width: 115, height: 30)) { [weak self] in self?.insertMacroKey() }
        button("插入延时", rect: NSRect(x: 465, y: 480, width: 115, height: 30)) { [weak self] in
            self?.appendMacroStep(MacroStep(kind: "delay", usage: 0, delay: 100, label: "延时"))
        }
        button("向上移动", rect: NSRect(x: 590, y: 480, width: 115, height: 30)) { [weak self] in self?.moveMacroStep(-1) }
        button("向下移动", rect: NSRect(x: 715, y: 480, width: 115, height: 30)) { [weak self] in self?.moveMacroStep(1) }
        button("删除动作", rect: NSRect(x: 840, y: 480, width: 115, height: 30)) { [weak self] in
            guard let self, !store.current.macros.isEmpty, store.current.macros[selectedMacro].steps.indices.contains(selectedStep) else { return }
            store.current.macros[selectedMacro].steps.remove(at: selectedStep); selectedStep = max(0, selectedStep - 1); persist(); render()
        }
        if steps.indices.contains(selectedStep) {
            editor(String(steps[selectedStep].delay), rect: NSRect(x: 340, y: 535, width: 115, height: 28), title: "动作延时毫秒") { [weak self] text in
                guard let self, let value = Int(text), (10...65535).contains(value) else { self?.setStatus("动作延时必须为 10–65535 ms。", error: true); return }
                store.current.macros[selectedMacro].steps[selectedStep].delay = value; persist(); render()
            }
        }
        button("保存到键盘", rect: NSRect(x: 970, y: 565, width: 130, height: 30)) { [weak self] in
            guard let self else { return }; let macros = store.current.macros
            confirm("将覆盖键盘现有宏库。请确认此方案包含需要保留的全部宏。") { [weak self] in
                guard let self else { return }; perform("保存宏库") { try self.keyboard.applyMacros(macros) }
            }
        }
    }

    func appendMacroStep(_ step: MacroStep) {
        guard !store.current.macros.isEmpty else { setStatus("请先新建宏。", error: true); return }
        store.current.macros[selectedMacro].steps.append(step)
        selectedStep = store.current.macros[selectedMacro].steps.count - 1; persist(); render()
    }

    func moveMacroStep(_ offset: Int) {
        guard !store.current.macros.isEmpty else { return }
        let steps = store.current.macros[selectedMacro].steps
        guard steps.indices.contains(selectedStep), steps.indices.contains(selectedStep + offset) else { return }
        store.current.macros[selectedMacro].steps.swapAt(selectedStep, selectedStep + offset)
        selectedStep += offset; persist(); render()
    }

    func insertMacroKey() {
        guard !store.current.macros.isEmpty else { setStatus("请先新建宏。", error: true); return }
        let alert = NSAlert(); alert.messageText = "插入按键"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        let keys = resources.layout.filter { $0.usage != 0xaf }; popup.addItems(withTitles: keys.map(\.name))
        alert.accessoryView = popup; alert.addButton(withTitle: "插入"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let key = keys[popup.indexOfSelectedItem]
            store.current.macros[selectedMacro].steps += [MacroStep(kind: "keyDown", usage: key.usage, delay: 100, label: key.name),
                                                         MacroStep(kind: "keyUp", usage: key.usage, delay: 100, label: key.name)]
            persist(); render()
        }
    }

    func toggleRecording() {
        if let recorder { recorder.stop(); self.recorder = nil; persist(); render(); return }
        guard !store.current.macros.isEmpty else { setStatus("请先新建宏。", error: true); return }
        let capture = MacroRecorder(onStep: { [weak self] step, previousDelay in
            guard let self else { return }
            if store.current.macros.reduce(0, { $0 + $1.steps.count }) >= 330 {
                recorder?.stop(); recorder = nil; setStatus("宏空间即将不足，已停止录制。", error: true); return
            }
            if let previousDelay, !store.current.macros[selectedMacro].steps.isEmpty {
                let last = store.current.macros[selectedMacro].steps.count - 1
                store.current.macros[selectedMacro].steps[last].delay = previousDelay
            }
            store.current.macros[selectedMacro].steps.append(step)
            setStatus("录制中：\(store.current.macros[selectedMacro].steps.count) 个动作。Esc 停止。")
        }, onStop: { [weak self] in
            self?.recorder = nil; self?.persist(); self?.render()
        })
        do { try capture.start(); recorder = capture; render(); setStatus("宏录制中，Esc 停止。") } catch { present(error) }
    }
}
