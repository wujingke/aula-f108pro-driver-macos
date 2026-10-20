import AppKit

struct KeyboardKey: Codable {
    let usage: Int
    let name: String
    let index: Int
    let lightIndex: Int
    let posX: Int
    let posY: Int
    let width: Int
    let height: Int
    let fnDisabled: Bool
    var rect: NSRect { NSRect(x: posX, y: posY, width: width, height: height) }
}

struct LightSettings: Codable, Equatable {
    var mode = 11
    var brightness = 5
    var speed = 3
    var direction = 0
    var colorful = true
    var color: UInt32 = 0xff7700
}

struct SystemSettings: Codable, Equatable {
    var disableWin = false
    var disableAltF4 = false
    var disableAltTab = false
    var fnSwitch = false
    var sleep = 1
    var response = 1
}

struct KeyBinding: Codable, Equatable {
    var kind: String
    var value: Int
    var modifiers: Int = 0
    var macroID: UUID?
    var repeatCount: Int = 1
    var label: String
}

struct MacroStep: Codable, Equatable {
    var kind: String
    var usage: Int
    var delay: Int
    var label: String
}

struct KeyboardMacro: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var steps: [MacroStep] = []
}

struct LightFrame: Codable, Equatable {
    var colors: [String: UInt32] = [:]
    var duration = 100
}

struct DriverProfile: Codable, Identifiable {
    var id = UUID()
    var name = "我的专属配置 1"
    var light = LightSettings()
    var system = SystemSettings()
    var keys: [String: KeyBinding] = [:]
    var fnKeys: [String: KeyBinding] = [:]
    var colors: [String: UInt32] = [:]
    var frames: [LightFrame] = [LightFrame()]
    var macros: [KeyboardMacro] = []

    func validate(layout: [KeyboardKey]) throws {
        let indices = Set(layout.map(\.index))
        guard (0...20).contains(light.mode), (0...5).contains(light.brightness),
              (0...5).contains(light.speed), (0...3).contains(light.direction), light.color <= 0xffffff,
              (0...3).contains(system.sleep), (1...5).contains(system.response),
              macros.count <= 100, frames.count <= 141,
              (macros.count + macros.reduce(0, { $0 + $1.steps.count })) * 8 <= 0xa8c else {
            throw ToolError("配置文件含有不支持的参数。")
        }
        let macroIDs = Set(macros.map(\.id))
        guard macroIDs.count == macros.count else { throw ToolError("宏标识重复。") }
        for bindings in [keys, fnKeys] {
            for (key, binding) in bindings {
                guard let index = Int(key), indices.contains(index),
                      ["default", "disabled", "key", "media", "mouse", "macro"].contains(binding.kind),
                      (0...255).contains(binding.modifiers), (0...65535).contains(binding.value),
                      (1...255).contains(binding.repeatCount) else { throw ToolError("按键配置无效：\(key)") }
                if binding.kind == "key", !(0...255).contains(binding.value) { throw ToolError("HID 按键值超出范围。") }
                if binding.kind == "mouse", !(1...8).contains(binding.value) { throw ToolError("鼠标功能超出范围。") }
                if binding.kind == "macro" {
                    guard let identifier = binding.macroID, macroIDs.contains(identifier) else {
                        throw ToolError("按键引用的宏不存在。")
                    }
                }
            }
        }
        for frame in frames {
            guard (20...5000).contains(frame.duration) else { throw ToolError("灯光帧时长必须为 20–5000 ms。") }
            try Self.validateColors(frame.colors, indices: indices)
        }
        try Self.validateColors(colors, indices: indices)
        for macro in macros {
            guard !macro.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolError("宏名称不能为空。")
            }
            for step in macro.steps {
                guard ["keyDown", "keyUp", "mouseDown", "mouseUp", "delay"].contains(step.kind),
                      (0...255).contains(step.usage), (10...65535).contains(step.delay) else {
                    throw ToolError("宏动作或延时无效。")
                }
            }
        }
    }

    private static func validateColors(_ colors: [String: UInt32], indices: Set<Int>) throws {
        for (key, color) in colors {
            guard let index = Int(key), indices.contains(index), color <= 0xffffff else {
                throw ToolError("逐键灯光配置无效：\(key)")
            }
        }
    }
}

struct ProfileFile: Codable {
    var format = "aula-f108pro-macos"
    var version = 1
    var profiles: [DriverProfile]
    var selected: UUID
}

final class ProfileStore {
    private(set) var profiles: [DriverProfile]
    var selected: UUID
    let url: URL
    let layout: [KeyboardKey]
    var current: DriverProfile {
        get { profiles.first(where: { $0.id == selected })! }
        set {
            guard let index = profiles.firstIndex(where: { $0.id == selected }) else { preconditionFailure("Selected profile is missing") }
            profiles[index] = newValue
        }
    }

    init(layout: [KeyboardKey], ephemeral: Bool = false) throws {
        self.layout = layout
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: !ephemeral)
            .appendingPathComponent("AULA F108Pro macOS", isDirectory: true)
        url = folder.appendingPathComponent("profiles.json")
        let initial = DriverProfile()
        profiles = [initial]
        selected = initial.id
        if !ephemeral, FileManager.default.fileExists(atPath: url.path) { try load(from: url) }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try export(to: url)
    }

    func export(to url: URL) throws {
        for profile in profiles { try profile.validate(layout: layout) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ProfileFile(profiles: profiles, selected: selected)).write(to: url, options: .atomic)
    }

    func load(from url: URL) throws {
        let document = try JSONDecoder().decode(ProfileFile.self, from: Data(contentsOf: url))
        guard document.format == "aula-f108pro-macos", document.version == 1,
              !document.profiles.isEmpty, document.profiles.count <= 100,
              Set(document.profiles.map(\.id)).count == document.profiles.count,
              document.profiles.contains(where: { $0.id == document.selected }) else {
            throw ToolError("配置文件格式或版本不支持。")
        }
        for profile in document.profiles { try profile.validate(layout: layout) }
        profiles = document.profiles
        selected = document.selected
    }

    func add() {
        var profile = current
        profile.id = UUID()
        profile.name = "我的专属配置 \(profiles.count + 1)"
        profiles.append(profile)
        selected = profile.id
    }

    func removeCurrent() throws {
        guard profiles.count > 1 else { throw ToolError("至少保留一个配置。") }
        profiles.removeAll { $0.id == selected }
        selected = profiles[0].id
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }

    var rgbValue: UInt32 {
        let color = usingColorSpace(.sRGB)!
        return UInt32((color.redComponent * 255).rounded()) << 16 |
               UInt32((color.greenComponent * 255).rounded()) << 8 | UInt32((color.blueComponent * 255).rounded())
    }
}
