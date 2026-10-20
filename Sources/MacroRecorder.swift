import AppKit
import ApplicationServices

final class MacroRecorder {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastTimestamp: TimeInterval?
    var onStep: (MacroStep, Int?) -> Void
    var onStop: () -> Void

    init(onStep: @escaping (MacroStep, Int?) -> Void, onStop: @escaping () -> Void) {
        self.onStep = onStep; self.onStop = onStop
    }

    func start() throws {
        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else {
            throw ToolError("宏录制需要输入监控权限。请在系统设置 → 隐私与安全性 → 输入监控中允许 AULA F108Pro，然后重新打开应用。")
        }
        let keys: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        let all = keys.union([.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp])
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: all) { [weak self] event in self?.record(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: keys) { [weak self] event in
            if event.keyCode == 53, event.type == .keyDown { self?.stop(); return nil }
            self?.record(event); return nil
        }
        guard globalMonitor != nil, localMonitor != nil else { stop(); throw ToolError("无法注册宏录制事件。") }
    }

    func stop() {
        let wasRecording = globalMonitor != nil || localMonitor != nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil; lastTimestamp = nil
        if wasRecording { onStop() }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func record(_ event: NSEvent) {
        let kind: String
        let usage: Int
        let name: String
        if [.keyDown, .keyUp, .flagsChanged].contains(event.type) {
            guard let key = Self.hidUsage[event.keyCode], !event.isARepeat else { return }
            usage = key
            name = event.charactersIgnoringModifiers?.uppercased() ?? Self.modifierNames[event.keyCode] ?? "HID \(key)"
            if event.type == .flagsChanged {
                let mask: NSEvent.ModifierFlags
                switch key {
                case 0xe0, 0xe4: mask = .control
                case 0xe1, 0xe5: mask = .shift
                case 0xe2, 0xe6: mask = .option
                default: mask = .command
                }
                kind = event.modifierFlags.contains(mask) ? "keyDown" : "keyUp"
            } else { kind = event.type == .keyDown ? "keyDown" : "keyUp" }
        } else {
            guard event.buttonNumber < 3 else { return }
            usage = [1, 2, 4][event.buttonNumber]
            name = ["鼠标左键", "鼠标右键", "鼠标中键"][event.buttonNumber]
            kind = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) ? "mouseDown" : "mouseUp"
        }
        let previousDelay = lastTimestamp.map { min(65535, max(10, Int((event.timestamp - $0) * 1000))) }
        lastTimestamp = event.timestamp
        onStep(MacroStep(kind: kind, usage: usage, delay: 100, label: name), previousDelay)
    }

    static let modifierNames: [UInt16: String] = [54: "Command R", 55: "Command L", 56: "Shift L", 60: "Shift R",
                                                58: "Option L", 61: "Option R", 59: "Control L", 62: "Control R"]
    static let hidUsage: [UInt16: Int] = [
        0: 4, 1: 22, 2: 7, 3: 9, 4: 11, 5: 10, 6: 29, 7: 27, 8: 6, 9: 25, 11: 5,
        12: 20, 13: 26, 14: 8, 15: 21, 16: 28, 17: 23, 18: 30, 19: 31, 20: 32, 21: 33,
        22: 35, 23: 34, 24: 46, 25: 38, 26: 36, 27: 45, 28: 37, 29: 39, 30: 48, 31: 18,
        32: 24, 33: 47, 34: 12, 35: 19, 36: 40, 37: 15, 38: 13, 39: 52, 40: 14, 41: 51,
        42: 49, 43: 54, 44: 56, 45: 17, 46: 16, 47: 55, 48: 43, 49: 44, 50: 53, 51: 42,
        53: 41, 54: 231, 55: 227, 56: 225, 57: 57, 58: 226, 59: 224, 60: 229, 61: 230, 62: 228,
        65: 99, 67: 85, 69: 87, 75: 84, 76: 88, 78: 86, 81: 103, 82: 98, 83: 89, 84: 90,
        85: 91, 86: 92, 87: 93, 88: 94, 89: 95, 91: 96, 92: 97,
        96: 62, 97: 63, 98: 64, 99: 60, 100: 65, 101: 66, 103: 68, 109: 67,
        111: 69, 114: 73, 115: 74, 116: 75, 117: 76, 118: 61, 119: 77, 120: 59, 121: 78,
        122: 58, 123: 80, 124: 79, 125: 81, 126: 82
    ]
}
