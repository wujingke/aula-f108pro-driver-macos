import AppKit

extension DriverController {
    func renderScreen() {
        renderScreenFrames()
        renderScreenTools()
        renderScreenContent()
    }

    private func renderScreenFrames() {
        label("TFT屏", frame: NSRect(x: 25, y: 24, width: 250, height: 35), in: content, size: 20)
        label("LED屏预览 · 240 × 135", frame: NSRect(x: 340, y: 35, width: 500, height: 30), in: content, size: 18)
        if !screen.frames.isEmpty {
            popup(screen.frames.enumerated().map { "第 \($0.offset + 1) 帧 · \($0.element.delay) ms" }, selected: screen.selected,
                  rect: NSRect(x: 25, y: 85, width: 240, height: 30), title: "屏幕动画帧") { [weak self] value in self?.screen.selected = value; self?.render() }
        } else {
            label("请导入图片或 GIF，\n也可以新建一帧。", frame: NSRect(x: 25, y: 85, width: 240, height: 70), in: content, size: 14)
        }
        button("导入", rect: NSRect(x: 25, y: 175, width: 110, height: 30)) { [weak self] in
            guard let self else { return }
            openPanel(types: [.image]) { [weak self] url in
                guard let self else { return }
                do { try screen.load(url); render(); setStatus("已导入 \(screen.frames.count) 帧。") } catch { present(error) }
            }
        }
        button("新建一帧", rect: NSRect(x: 145, y: 175, width: 110, height: 30)) { [weak self] in
            guard let self else { return }
            guard screen.frames.count < 141 else { setStatus("最大允许 141 帧。", error: true); return }
            screen.frames.append(ScreenFrame()); screen.selected = screen.frames.count - 1; render()
        }
        button("复制前一帧", rect: NSRect(x: 25, y: 225, width: 110, height: 30)) { [weak self] in
            guard let self, let frame = screen.current else { self?.setStatus("请先添加图片帧。", error: true); return }
            guard screen.frames.count < 141 else { setStatus("最大允许 141 帧。", error: true); return }
            screen.frames.insert(frame, at: screen.selected + 1); screen.selected += 1; render()
        }
        button("删除选中帧", rect: NSRect(x: 145, y: 225, width: 110, height: 30)) { [weak self] in
            guard let self, !screen.frames.isEmpty else { return }
            screen.frames.remove(at: screen.selected); screen.selected = max(0, min(screen.selected, screen.frames.count - 1)); render()
        }
    }

    private func renderScreenTools() {
        colorWell(paintColor, rect: NSRect(x: 25, y: 295, width: 100, height: 35), title: "画笔及文字颜色") { [weak self] color in
            self?.paintColor = color; self?.screenCanvas?.color = color
        }
        popup(["画笔-细", "画笔-中", "画笔-粗"], selected: 0, rect: NSRect(x: 145, y: 297, width: 110, height: 30), title: "画笔粗细") { [weak self] value in
            self?.screenCanvas?.brush = [1, 3, 5][value]
        }
        button("画笔", rect: NSRect(x: 25, y: 350, width: 70, height: 30)) { [weak self] in self?.screenCanvas?.erasing = false; self?.setStatus("画笔：在图片上拖动绘制。") }
        button("橡皮擦", rect: NSRect(x: 105, y: 350, width: 70, height: 30)) { [weak self] in self?.screenCanvas?.erasing = true; self?.setStatus("橡皮擦：在图片上拖动擦除。") }
        button("撤销", rect: NSRect(x: 185, y: 350, width: 70, height: 30)) { [weak self] in
            guard let self, let previous = screen.undoFrame else { return }
            let current = screen.current; screen.current = previous; screen.undoFrame = current; screenCanvas?.needsDisplay = true
        }
        button("添加文本", rect: NSRect(x: 25, y: 405, width: 230, height: 30)) { [weak self] in self?.addScreenText() }
        if let frame = screen.current {
            label("当前帧延时（20–5100 ms）", frame: NSRect(x: 25, y: 460, width: 240, height: 25), in: content, size: 13)
            editor(String(frame.delay), rect: NSRect(x: 25, y: 490, width: 110, height: 28), title: "屏幕帧延时") { [weak self] text in
                guard let self, let delay = Int(text), (20...5100).contains(delay) else { self?.setStatus("延时必须为 20–5100 ms。", error: true); return }
                screen.frames[screen.selected].delay = delay
            }
            button("应用到所有帧", rect: NSRect(x: 145, y: 490, width: 110, height: 28)) { [weak self] in
                guard let self, let current = screen.current else { return }
                for index in screen.frames.indices { screen.frames[index].delay = current.delay }
                render()
            }
        }
    }

    private func renderScreenContent() {
        let canvas = PixelCanvas(frame: NSRect(x: 340, y: 90, width: 720, height: 405), document: screen)
        canvas.color = paintColor; screenCanvas = canvas; content.addSubview(canvas)
        if screen.frames.isEmpty {
            label("图片编辑", frame: NSRect(x: 620, y: 270, width: 200, height: 40), in: content, size: 22, color: .lightGray)
        }
        button(previewTimer == nil ? "效果预览" : "停止预览", rect: NSRect(x: 340, y: 525, width: 135, height: 32)) { [weak self] in self?.toggleScreenPreview() }
        button("导出GIF", rect: NSRect(x: 495, y: 525, width: 135, height: 32)) { [weak self] in
            guard let self else { return }
            savePanel(name: "F108Pro 动画.gif", type: .gif) { [weak self] url in
                guard let self else { return }; do { try screen.saveGIF(url); setStatus("GIF 已保存。") } catch { present(error) }
            }
        }
        button("时间校正", rect: NSRect(x: 650, y: 525, width: 135, height: 32)) { [weak self] in
            guard let self else { return }; perform("时间校正") { try self.keyboard.syncTime() }
        }
        button("上传到键盘", rect: NSRect(x: 925, y: 565, width: 135, height: 32)) { [weak self] in
            guard let self else { return }
            do {
                let payload = try screen.packetData()
                confirm("将以当前 \(screen.frames.count) 帧动画替换键盘屏幕中的动画。上传期间请保持 USB 连接。") { [weak self] in
                    guard let self else { return }
                    let uploader = self.keyboard
                    perform("上传屏幕动画") { [weak self] in
                        try uploader.uploadScreen(payload) { progress in
                            DispatchQueue.main.async { [weak self] in self?.setStatus("动画上传：\(progress)%") }
                        }
                    }
                }
            } catch { present(error) }
        }
        label("\(screen.frames.count)/141 帧", frame: NSRect(x: 930, y: 525, width: 140, height: 30), in: content, size: 13, color: .lightGray)
    }

    func addScreenText() {
        guard screen.current != nil else { setStatus("请先添加图片帧。", error: true); return }
        let alert = NSAlert(); alert.messageText = "添加文本"
        let field = NSTextField(string: ""); field.frame = NSRect(x: 0, y: 0, width: 320, height: 30)
        field.placeholderString = "输入文字"; alert.accessoryView = field
        alert.addButton(withTitle: "添加文本"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do { try screen.addText(field.stringValue, size: 24, color: paintColor); screenCanvas?.needsDisplay = true } catch { present(error) }
        }
    }

    private func tickScreenPreview() {
        guard previewTimer != nil, Date() >= nextScreenFrame, !screen.frames.isEmpty else { return }
        screen.selected = (screen.selected + 1) % screen.frames.count
        nextScreenFrame = Date().addingTimeInterval(Double(screen.frames[screen.selected].delay) / 1000)
        screenCanvas?.needsDisplay = true
    }

    func toggleScreenPreview() {
        if let previewTimer { previewTimer.invalidate(); self.previewTimer = nil; render(); return }
        guard !screen.frames.isEmpty else { setStatus("请先添加图片帧。", error: true); return }
        let selected = screen.selected
        nextScreenFrame = .distantPast
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickScreenPreview() }
        }
        render()
        setStatus("动画预览中。停止后可继续编辑；起始帧为第 \(selected + 1) 帧。")
    }
}
