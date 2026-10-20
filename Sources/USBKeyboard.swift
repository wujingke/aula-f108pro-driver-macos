import Foundation
import IOKit
import IOKit.hid

// Protocol observations: analysis/usb-protocol-functions.json; Windows report-ID prefix is excluded.
enum KeyboardProtocol {
    static func command(_ code: UInt8, blocks: Int = 0, option: UInt8 = 0) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 64)
        data[0] = 4; data[1] = code; data[2] = option
        data[8] = UInt8(blocks & 255); data[9] = UInt8((blocks >> 8) & 255)
        return data
    }

    static func light(_ settings: LightSettings) throws -> [UInt8] {
        guard (0...20).contains(settings.mode), (0...5).contains(settings.brightness),
              (0...5).contains(settings.speed), (0...3).contains(settings.direction) else {
            throw ToolError("灯光参数超出设备范围。")
        }
        var data = [UInt8](repeating: 0, count: 64)
        data[0] = UInt8(settings.mode)
        data[1] = UInt8((settings.color >> 16) & 255)
        data[2] = UInt8((settings.color >> 8) & 255)
        data[3] = UInt8(settings.color & 255)
        data[8] = settings.colorful ? 1 : 0
        data[9] = UInt8(settings.brightness); data[10] = UInt8(settings.speed)
        data[11] = UInt8(settings.direction); data[14] = 0xaa; data[15] = 0x55
        return data
    }

    static func system(_ settings: SystemSettings) throws -> [UInt8] {
        guard (0...3).contains(settings.sleep), (1...5).contains(settings.response) else {
            throw ToolError("休眠或响应时间参数无效。")
        }
        var data = [UInt8](repeating: 0, count: 64)
        data[1] = 1
        data[2] = settings.disableWin ? 1 : 0
        data[3] = settings.disableAltF4 ? 1 : 0
        data[4] = settings.disableAltTab ? 1 : 0
        data[5] = settings.fnSwitch ? 1 : 0
        data[6] = UInt8(settings.sleep); data[8] = UInt8(settings.response)
        data[62] = 0xaa; data[63] = 0x55
        return data
    }

    static func colors(_ colors: [String: UInt32], layout: [KeyboardKey]) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 576)
        for key in layout {
            guard (1..<143).contains(key.lightIndex) else { throw ToolError("灯光索引超出范围。") }
            let offset = key.lightIndex * 4
            let color = colors[String(key.index)] ?? 0
            guard color <= 0xffffff else { throw ToolError("颜色无效。") }
            data[offset] = UInt8(key.lightIndex)
            data[offset + 1] = UInt8((color >> 16) & 255)
            data[offset + 2] = UInt8((color >> 8) & 255)
            data[offset + 3] = UInt8(color & 255)
        }
        data[574] = 0xaa; data[575] = 0x55
        return data
    }

    static func bindings(_ bindings: [String: KeyBinding], macros: [KeyboardMacro], layout: [KeyboardKey]) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 576)
        for key in layout {
            guard let binding = bindings[String(key.index)] else { continue }
            guard (1..<143).contains(key.index) else { throw ToolError("按键索引超出范围。") }
            let offset = key.index * 4
            switch binding.kind {
            case "default": break
            case "disabled": data[offset] = 5; data[offset + 1] = 3
            case "key":
                guard (0...255).contains(binding.value), (0...255).contains(binding.modifiers) else {
                    throw ToolError("按键值超出 HID 范围。")
                }
                data[offset] = 2; data[offset + 1] = UInt8(binding.modifiers)
                if (0xe0...0xe7).contains(binding.value), binding.modifiers == 0 {
                    data[offset + 1] = 1 << UInt8(binding.value - 0xe0)
                } else { data[offset + 2] = UInt8(binding.value) }
            case "media":
                guard (0...65535).contains(binding.value) else { throw ToolError("多媒体键无效。") }
                data[offset] = 3; data[offset + 1] = UInt8(binding.value & 255)
                data[offset + 2] = UInt8((binding.value >> 8) & 255)
            case "mouse":
                guard (1...8).contains(binding.value) else { throw ToolError("鼠标功能无效。") }
                let actions: [[UInt8]] = [[1, 1], [1, 4], [1, 2], [1, 3], [3, 1], [3, 255], [1, 8], [1, 16]]
                data[offset] = 1
                data[offset + 1] = actions[binding.value - 1][0]; data[offset + 2] = actions[binding.value - 1][1]
            case "macro":
                guard let index = macros.firstIndex(where: { $0.id == binding.macroID }), index < 100,
                      (1...255).contains(binding.repeatCount) else { throw ToolError("宏或循环次数无效。") }
                data[offset] = 6; data[offset + 1] = UInt8(index)
                data[offset + 2] = 1; data[offset + 3] = UInt8(binding.repeatCount)
            default: throw ToolError("不支持的按键功能：\(binding.kind)")
            }
        }
        data[574] = 0xaa; data[575] = 0x55
        return data
    }

    static func macroBody(_ macros: [KeyboardMacro]) throws -> [UInt8] {
        guard macros.count <= 100 else { throw ToolError("最多支持 100 个宏。") }
        guard (macros.count + macros.reduce(0) { $0 + $1.steps.count }) * 8 <= 0xa8c else {
            throw ToolError("宏动作总量超过键盘存储空间。")
        }
        var data = [UInt8](repeating: 0, count: 400)
        for (index, macro) in macros.enumerated() {
            let start = data.count
            data[index * 4] = UInt8(start & 255); data[index * 4 + 1] = UInt8((start >> 8) & 255)
            var events = [UInt8]()
            for step in macro.steps {
                guard (10...65535).contains(step.delay), (0...255).contains(step.usage) else {
                    throw ToolError("宏动作或延时超出设备范围。")
                }
                let flags: [String: UInt8] = ["keyDown": 0xb0, "keyUp": 0x30, "mouseDown": 0x90, "mouseUp": 0x10]
                if step.kind != "delay" {
                    guard let flag = flags[step.kind] else { throw ToolError("未知宏动作。") }
                    events += [0, 0, UInt8(step.usage), flag]
                }
                events += [UInt8(step.delay & 255), UInt8((step.delay >> 8) & 255), 0, 0x50]
            }
            let count = events.count / 4
            data += [UInt8(count & 255), UInt8((count >> 8) & 255), 0, 0, 0, 0, 0, 0] + events
        }
        return data
    }

    static func macros(_ macros: [KeyboardMacro]) throws -> [UInt8] {
        var data = try macroBody(macros)
        let blockCount = (data.count + 63) / 64 + 1
        data += [UInt8](repeating: 0, count: blockCount * 64 - data.count)
        data[data.count - 2] = 0xaa; data[data.count - 1] = 0x55
        return data
    }
}

// Active HID sessions are protected by ioLock; discovery uses a separate manager per call.
final class USBKeyboard: @unchecked Sendable {
    private let ioLock = NSRecursiveLock()
    private var active: IOHIDDevice?
    let log: @Sendable (String) -> Void = { print($0) }

    func allDevices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        return devices(manager)
    }

    func configurationDevices() -> [IOHIDDevice] {
        allDevices().filter {
            number($0, kIOHIDVendorIDKey) == 0x0c45 && number($0, kIOHIDProductIDKey) == 0x800a &&
            property($0, kIOHIDTransportKey) as? String == "USB" &&
            number($0, kIOHIDPrimaryUsagePageKey) == 0xff13 && number($0, kIOHIDPrimaryUsageKey) == 1 &&
            number($0, kIOHIDMaxFeatureReportSizeKey) == 64
        }
    }

    func withDevice<T>(_ body: () throws -> T) throws -> T {
        ioLock.lock(); defer { ioLock.unlock() }
        let found = configurationDevices()
        guard found.count == 1 else { throw ToolError("请通过 USB 连接一台 F108Pro，并切换为有线模式。") }
        try check(IOHIDDeviceOpen(found[0], IOOptionBits(kIOHIDOptionsTypeNone)), "打开 USB 配置接口")
        active = found[0]
        defer { IOHIDDeviceClose(found[0], IOOptionBits(kIOHIDOptionsTypeNone)); active = nil }
        return try body()
    }

    func write(_ payload: [UInt8], delay: TimeInterval = 0.035) throws {
        ioLock.lock(); defer { ioLock.unlock() }
        guard let device = active, payload.count == 64 else { throw ToolError("USB 会话未打开或报文长度错误。") }
        Thread.sleep(forTimeInterval: delay)
        try check(payload.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
        }, "写入 USB Feature Report")
    }

    func readFeature() throws -> [UInt8] {
        ioLock.lock(); defer { ioLock.unlock() }
        guard let device = active else { throw ToolError("USB 会话未打开。") }
        var reply = [UInt8](repeating: 0, count: 64)
        var length = reply.count
        try check(reply.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &length)
        }, "读取 USB Feature Report")
        guard length == 64 else { throw ToolError("设备返回了短报文：\(length) bytes。") }
        return reply
    }

    @discardableResult
    func control(_ payload: [UInt8]) throws -> [UInt8] {
        try write(payload)
        Thread.sleep(forTimeInterval: 0.035)
        let reply = try readFeature()
        guard reply[0] == payload[0], reply[1] == payload[1], reply[3] == 1 else {
            throw ToolError("USB 命令未成功：\(hex(Array(reply.prefix(16))))")
        }
        log("USB \(hex(Array(payload.prefix(10)))) → ACK")
        return reply
    }

    func finish() throws { try control(KeyboardProtocol.command(2)) }

    func transaction(_ body: () throws -> Void) throws {
        try withDevice {
            do { try body(); try finish() } catch {
                let original = error
                do { try finish() } catch { log("收尾失败：\(error)") }
                throw original
            }
        }
    }

    func syncTime() throws {
        try withDevice {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let reports = try timeReports(at: Date(), calendar: calendar)
            do {
                try control(reports[0]); try control(reports[1]); try write(reports[2])
                Thread.sleep(forTimeInterval: 0.035)
                guard try readFeature() == reports[2] else { throw ToolError("日期时间回显不匹配。") }
                try control(reports[3])
            } catch {
                let original = error
                do { try finish() } catch { log("收尾失败：\(error)") }
                throw original
            }
        }
    }

    func applyLight(_ settings: LightSettings) throws {
        let payload = try KeyboardProtocol.light(settings)
        try transaction {
            try control(KeyboardProtocol.command(0x18))
            try control(KeyboardProtocol.command(0x13, blocks: 1))
            try write(payload)
        }
        try withDevice { try write(KeyboardProtocol.command(0xf0)) }
    }

    func applySystem(_ settings: SystemSettings) throws {
        let payload = try KeyboardProtocol.system(settings)
        try transaction {
            try control(KeyboardProtocol.command(0x18))
            try control(KeyboardProtocol.command(0x17, blocks: 1, option: 1))
            try write(payload)
        }
    }

    func applyColors(_ colors: [String: UInt32], layout: [KeyboardKey]) throws {
        let payload = try KeyboardProtocol.colors(colors, layout: layout)
        var modePayload = [UInt8](repeating: 0, count: 64)
        modePayload[0] = 0x80; modePayload[9] = 5; modePayload[14] = 0xaa; modePayload[15] = 0x55
        try transaction {
            try control(KeyboardProtocol.command(0x18))
            try control(KeyboardProtocol.command(0x13, blocks: 1))
            try write(modePayload)
        }
        try transaction {
            try control(KeyboardProtocol.command(0x18))
            try control(KeyboardProtocol.command(0x23, blocks: 9))
            try writeBlocks(payload)
        }
        try withDevice { try write(KeyboardProtocol.command(0xf0)) }
    }

    func applyBindings(_ profile: DriverProfile, fnLayer: Bool, layout: [KeyboardKey]) throws {
        let payload = try KeyboardProtocol.bindings(fnLayer ? profile.fnKeys : profile.keys, macros: profile.macros, layout: layout)
        try transaction {
            try control(KeyboardProtocol.command(0x18))
            try control(KeyboardProtocol.command(fnLayer ? 0x27 : 0x11, blocks: 9))
            try writeBlocks(payload)
        }
        _ = try withDevice { try control(KeyboardProtocol.command(0xf0)) }
    }

    func applyMacros(_ macros: [KeyboardMacro]) throws {
        let payload = try KeyboardProtocol.macros(macros)
        try transaction {
            try control(KeyboardProtocol.command(0x19))
            try control(KeyboardProtocol.command(0x15, blocks: payload.count / 64))
            Thread.sleep(forTimeInterval: 0.03)
            try writeBlocks(payload)
            Thread.sleep(forTimeInterval: 0.03)
        }
    }

    private func writeBlocks(_ payload: [UInt8]) throws {
        guard !payload.isEmpty, payload.count % 64 == 0 else { throw ToolError("分包数据长度无效。") }
        for offset in stride(from: 0, to: payload.count, by: 64) {
            try write(Array(payload[offset..<offset + 64]))
        }
    }
}
