import AppKit
import UniformTypeIdentifiers

enum DriverPage: Int, CaseIterable {
    case home, keys, macros, light, screen, userLight, liveLight, music, settings
    var title: String {
        ["主菜单", "我的专属配置", "宏管理器", "灯光模式", "TFT屏", "用户灯光", "实时灯效", "音乐律动", "系统配置"][rawValue]
    }
    var icon: String {
        ["home", "customkey", "macro", "light", "tft", "userlight", "customlight", "music", "config"][rawValue]
    }
}

@MainActor
final class DriverController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let resources: DriverResources
    let store: ProfileStore
    let keyboard = KeyboardDevice()
    let worker = DispatchQueue(label: "com.aula.f108pro.usb")
    let screen = ScreenDocument()
    var window: OriginalWindow!
    var root: BackgroundView!
    var content = FlippedView()
    var statusField: NSTextField!
    var connectionField: NSTextField?
    var connectionPicker: NSPopUpButton?
    var renderedConnection = KeyboardConnection.usb
    var connectionTimer: Timer?
    var hardwareButtons = [SkinButton]()
    var connected = false
    var statusText = "配置为本地方案；点击应用后写入键盘。"
    var page = DriverPage.home
    var actionTargets = [ActionTarget]()
    var navButtons = [SkinButton]()
    var selectedKeys = Set<Int>()
    var fnLayer = false
    var selectedMacro = 0
    var selectedStep = 0
    var selectedLightFrame = 0
    var paintColor = NSColor(rgb: 0xff9c00)
    var keyboardView: KeyboardView?
    var screenCanvas: PixelCanvas?
    var busy = false
    var playbackTimer: Timer?
    var previewTimer: Timer?
    var frameInFlight = false
    var frameCursor = 0
    var nextPlaybackFrame = Date.distantPast
    var nextScreenFrame = Date.distantPast
    var recorder: MacroRecorder?
    var audio: SystemAudioCapture?
    var lastBands = [Float](repeating: 0, count: 21)
    let ephemeral: Bool

    init(ephemeral: Bool = false) throws {
        self.ephemeral = ephemeral
        resources = try DriverResources()
        store = try ProfileStore(layout: resources.layout, ephemeral: ephemeral)
        super.init()
        NSApp.applicationIconImage = NSImage(contentsOf: resources.root.appendingPathComponent("skins/theme1/DeviceDriver.ico"))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createWindow()
        render()
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshConnection() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        connectionTimer?.invalidate()
        playbackTimer?.invalidate(); previewTimer?.invalidate(); recorder?.stop()
        audio?.stop()
    }

    func createWindow() {
        window = OriginalWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                                styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AULA F108Pro"
        window.isMovableByWindowBackground = false
        window.delegate = self
        root = BackgroundView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), image: resources.image("main_bkg.png"))
        window.contentView = root
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 AULA F108Pro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    func render() {
        guard root != nil else { return }
        root.subviews.forEach { $0.removeFromSuperview() }
        actionTargets.removeAll(); navButtons.removeAll(); hardwareButtons.removeAll()
        keyboardView = nil; screenCanvas = nil
        picture(resources.image("logo/logo.png"), frame: NSRect(x: 27, y: 16, width: 67, height: 26), in: root)
        label("AULA F108Pro", frame: NSRect(x: 330, y: 16, width: 360, height: 30), in: root, size: 20)
        renderConnectionHeader()
        if renderedConnection == .wireless, [.screen, .liveLight].contains(page) { page = .home }
        button("", rect: NSRect(x: 1190, y: 15, width: 30, height: 30), sprite: "main_sysbtn_min.png", parent: root) { [weak self] in
            self?.window.miniaturize(nil)
        }.setAccessibilityLabel("最小化")
        button("", rect: NSRect(x: 1230, y: 15, width: 30, height: 30), sprite: "main_sysbtn_close.png", parent: root) {
            NSApp.terminate(nil)
        }.setAccessibilityLabel("关闭")
        let pages = DriverPage.allCases.filter { renderedConnection != .wireless || ![.screen, .liveLight].contains($0) }
        for (index, item) in pages.enumerated() {
            let nav = button("", rect: NSRect(x: 10, y: 75 + index * 62, width: 40, height: 40),
                             sprite: "icon/tab_\(item.icon).png", parent: root) { [weak self] in self?.select(item) }
            nav.active = page == item; nav.toolTip = item.title; nav.setAccessibilityLabel(item.title)
            navButtons.append(nav)
        }
        content = FlippedView(frame: NSRect(x: 60, y: 60, width: 1220, height: 620))
        root.addSubview(content)
        switch page {
        case .home: renderHome()
        case .keys: renderKeys()
        case .macros: self.renderMacros()
        case .light: renderLight()
        case .screen: self.renderScreen()
        case .userLight: renderUserLight()
        case .liveLight: renderLiveLight()
        case .music: renderMusic()
        case .settings: renderSettings()
        }
        statusField = label(statusText, frame: NSRect(x: 85, y: 681, width: 1160, height: 30), in: root, size: 12, color: .lightGray)
        if busy { statusField.textColor = NSColor(rgb: 0xffad37) }
    }

    private func renderConnectionHeader() {
        renderedConnection = keyboard.currentConnection
        connected = keyboard.configurationDevices().count == 1
        connectionField = label(connectionStatusText,
                                frame: NSRect(x: 1000, y: 21, width: 175, height: 22), in: root, size: 13,
                                color: connected ? NSColor(rgb: 0xffae35) : .lightGray)
        let icon = renderedConnection == .wireless ? "icon/24g_mode.png" : "icon/usb_mode.png"
        picture(resources.image(icon), frame: NSRect(x: 963, y: 15, width: 30, height: 30), in: root)
        let choices = KeyboardConnection.allCases
        connectionPicker = popup(choices.map(\.rawValue), selected: choices.firstIndex(of: keyboard.preferredConnection)!,
                                 rect: NSRect(x: 775, y: 15, width: 175, height: 30), title: "设置连接方式", parent: root) { [weak self] index in
            guard let self, !busy, playbackTimer == nil else { return }
            keyboard.preferredConnection = choices[index]
            stopPlayback(); selectedKeys.removeAll(); render()
            setStatus("已选择\(choices[index].rawValue)。")
        }
        connectionPicker?.isEnabled = !busy && playbackTimer == nil
    }

    func select(_ next: DriverPage) {
        guard !busy else { setStatus("设备操作中，请等待完成。"); return }
        self.stopPlayback()
        recorder?.stop(); recorder = nil
        page = next; selectedKeys.removeAll(); render()
    }

    private var connectionStatusText: String {
        guard connected else { return "请连接 · \(renderedConnection.rawValue)" }
        return renderedConnection == .wireless ? "2.4G 接收器已接入" : "已连接 · USB 有线"
    }

    func refreshConnection() {
        if !busy {
            if keyboard.currentConnection != renderedConnection {
                stopPlayback(); render(); return
            }
            connected = keyboard.configurationDevices().count == 1
        }
        connectionField?.stringValue = connectionStatusText
        connectionField?.textColor = connected ? NSColor(rgb: 0xffae35) : .lightGray
        connectionPicker?.isEnabled = !busy && playbackTimer == nil
        for button in hardwareButtons { button.isEnabled = connected && !busy }
    }

    func setStatus(_ text: String, error: Bool = false) {
        statusText = text
        statusField?.stringValue = text
        statusField?.textColor = error ? NSColor(rgb: 0xff9696) : NSColor.lightGray
    }

    func persist() {
        guard !ephemeral else { return }
        do { try store.save() } catch { present(error) }
    }

    func present(_ error: Error) {
        setStatus(String(describing: error), error: true)
        let alert = NSAlert(); alert.messageText = "操作未完成"; alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    func perform(_ title: String, operation: @escaping () throws -> Void) {
        guard !busy else { setStatus("请等待当前设备操作完成。"); return }
        busy = true; setStatus("\(title)…")
        refreshConnection()
        worker.async { [weak self] in
            do {
                try operation()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.busy = false; self.setStatus("\(title)完成。")
                    self.refreshConnection()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.busy = false; self.present(error)
                    self.refreshConnection()
                }
            }
        }
    }

    func confirm(_ message: String, action: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = "写入键盘"; alert.informativeText = message
        alert.addButton(withTitle: "写入"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { action() } }
    }

    @discardableResult
    func button(_ title: String, rect: NSRect, sprite: String? = nil, parent: NSView? = nil,
                action: @escaping () -> Void) -> SkinButton {
        let control = SkinButton(title: title, frame: rect, sprite: sprite.map(resources.image), action: action)
        if ["应用", "时间校正", "上传到键盘", "保存到键盘", "开始音乐律动", "播放"].contains(title) {
            hardwareButtons.append(control); control.isEnabled = connected && !busy
        }
        (parent ?? content).addSubview(control)
        return control
    }

    @discardableResult
    func popup(_ items: [String], selected: Int, rect: NSRect, title: String, parent: NSView? = nil,
               action: @escaping (Int) -> Void) -> NSPopUpButton {
        let control = NSPopUpButton(frame: rect, pullsDown: false)
        let cell = SkinPopupCell(textCell: "", pullsDown: false)
        cell.sprite = resources.image("img_combobox.png"); control.cell = cell
        control.addItems(withTitles: items)
        control.selectItem(at: selected)
        control.font = .systemFont(ofSize: 13)
        control.appearance = NSAppearance(named: .darkAqua)
        control.setAccessibilityLabel(title)
        let target = ActionTarget { action(control.indexOfSelectedItem) }
        actionTargets.append(target); control.target = target; control.action = #selector(ActionTarget.invoke(_:))
        (parent ?? content).addSubview(control)
        return control
    }

    func checkBox(_ title: String, value: Bool, rect: NSRect, action: @escaping (Bool) -> Void) {
        let control = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        let cell = SkinCheckboxCell(textCell: title)
        cell.sprite = resources.image("btn_checkbox.png"); control.cell = cell; control.setButtonType(.switch)
        control.frame = rect; control.state = value ? .on : .off
        control.contentTintColor = .white; control.appearance = NSAppearance(named: .darkAqua)
        let target = ActionTarget { action(control.state == .on) }
        actionTargets.append(target); control.target = target; control.action = #selector(ActionTarget.invoke(_:))
        content.addSubview(control)
    }

    func slider(_ title: String, value: Int, range: ClosedRange<Int>, rect: NSRect, action: @escaping (Int) -> Void) {
        label(title, frame: NSRect(x: rect.minX, y: rect.minY - 23, width: rect.width, height: 22), in: content, size: 13)
        let control = SkinSlider(frame: rect)
        control.bar = resources.image("img_slider_back.png"); control.thumb = resources.image("img_thumb.png")
        control.minValue = Double(range.lowerBound); control.maxValue = Double(range.upperBound)
        control.integerValue = value; control.numberOfTickMarks = range.count
        control.appearance = NSAppearance(named: .darkAqua); control.setAccessibilityLabel(title)
        let target = ActionTarget { action(control.integerValue) }
        actionTargets.append(target); control.target = target; control.action = #selector(ActionTarget.invoke(_:))
        content.addSubview(control)
    }

    @discardableResult
    func colorWell(_ color: NSColor, rect: NSRect, title: String, action: @escaping (NSColor) -> Void) -> NSColorWell {
        let control = NSColorWell(frame: rect); control.color = color; control.setAccessibilityLabel(title)
        let target = ActionTarget { action(control.color) }
        actionTargets.append(target); control.target = target; control.action = #selector(ActionTarget.invoke(_:))
        content.addSubview(control)
        return control
    }

    @discardableResult
    func editor(_ value: String, rect: NSRect, title: String, action: @escaping (String) -> Void) -> NSTextField {
        let control = NSTextField(string: value); control.frame = rect; control.font = .systemFont(ofSize: 14)
        control.appearance = NSAppearance(named: .darkAqua); control.setAccessibilityLabel(title)
        let target = ActionTarget { action(control.stringValue) }
        actionTargets.append(target); control.target = target; control.action = #selector(ActionTarget.invoke(_:))
        content.addSubview(control)
        return control
    }

    func profilePicker() {
        label(page.title, frame: NSRect(x: 25, y: 24, width: 275, height: 30), in: content, size: 20)
        popup(store.profiles.map(\.name), selected: store.profiles.firstIndex(where: { $0.id == store.selected })!,
              rect: NSRect(x: 25, y: 70, width: 240, height: 30), title: "配置方案") { [weak self] index in
            guard let self else { return }; store.selected = store.profiles[index].id; persist(); render()
        }
    }

    @discardableResult
    func addKeyboard(multiple: Bool = false) -> KeyboardView {
        let view = KeyboardView(frame: NSRect(x: 325, y: 90, width: 800, height: 300), resources: resources)
        view.multiple = multiple; view.selected = selectedKeys
        view.onSelection = { [weak self] selected in self?.selectedKeys = selected; self?.selectionChanged() }
        content.addSubview(view); keyboardView = view
        return view
    }

    func selectionChanged() {
        if page == .keys, let first = selectedKeys.first,
           let key = resources.layout.first(where: { $0.index == first }) {
            setStatus("已选择 \(key.name)。请选择左侧功能并保存到本地方案，然后应用到键盘。")
            render()
        } else if page == .userLight || page == .liveLight {
            setStatus("已选择 \(selectedKeys.count) 个按键；点击着色应用当前颜色。")
        }
    }

    func openPanel(types: [UTType], completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = types; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in if response == .OK, let url = panel.url { completion(url) } }
    }

    func savePanel(name: String, type: UTType, completion: @escaping (URL) -> Void) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = name
        panel.beginSheetModal(for: window) { response in if response == .OK, let url = panel.url { completion(url) } }
    }

    func importProfiles() {
        openPanel(types: [.json]) { [weak self] url in
            guard let self else { return }
            do { try store.load(from: url); persist(); render() } catch { present(error) }
        }
    }

    func exportProfiles() {
        savePanel(name: "F108Pro 配置.json", type: .json) { [weak self] url in
            guard let self else { return }; do { try store.export(to: url); setStatus("配置已导出。") } catch { present(error) }
        }
    }
}

@main
@MainActor
enum F108ProMain {
    static func main() {
        do {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let testing = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--ui-test")
            let controller = try DriverController(ephemeral: testing)
            if CommandLine.arguments.contains("--self-test") {
                try runDriverTests(resources: controller.resources)
                return
            }
            if CommandLine.arguments.contains("--ui-test") {
                try runUITests(controller)
                return
            }
            app.delegate = controller
            app.run()
        } catch {
            FileHandle.standardError.write(Data("AULA F108Pro：\(error)\n".utf8))
            exit(1)
        }
    }
}
