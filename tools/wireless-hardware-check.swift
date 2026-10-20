import AppKit

@main
enum WirelessHardwareCheck {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else { throw ToolError("用法：wireless-hardware-check probe | time | light") }
            let keyboard = WirelessKeyboard()
            let matches = keyboard.configurationDevices()
            guard matches.count == 1 else { throw ToolError("需要唯一的 F108Pro 2.4G 配置接口。") }
            print(description(matches[0]))
            switch CommandLine.arguments[1] {
            case "probe":
                let replies = try keyboard.execute([WirelessProtocol.packet(command: 2)])
                print("PASS: 2.4G 无配置改动握手；应答：\(hex(replies[0]))")
            case "time":
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
                let packet = try WirelessProtocol.time(at: Date(), calendar: calendar)
                let replies = try keyboard.execute([packet])
                print("PASS: 2.4G 校时命令头匹配；应答：\(hex(replies[0]))。屏幕显示尚需人工确认。")
            case "light":
                try testLights(keyboard)
            default: throw ToolError("未知测试项。")
            }
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func testLights(_ keyboard: WirelessKeyboard) throws {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/AULA F108Pro.app/Contents/Resources/Assets/keyboard.json")
        let layout = try JSONDecoder().decode([KeyboardKey].self, from: Data(contentsOf: url))
        let store = try ProfileStore(layout: layout)
        let restore = store.current.light
        print("结束后恢复应用中当前本地灯光方案：mode=\(restore.mode), brightness=\(restore.brightness), speed=\(restore.speed)。")
        var failure: Error?
        do {
            for color: UInt32 in [0x003060, 0x006030] {
                var settings = LightSettings()
                settings.mode = 1; settings.colorful = false; settings.color = color
                let replies = try keyboard.execute([WirelessProtocol.light(settings)])
                print(String(format: "PASS: 2.4G 灯效 %06X；应答：%@", color, hex(replies[0])))
                Thread.sleep(forTimeInterval: 1)
            }
        } catch { failure = error }
        do { try keyboard.applyLight(restore) } catch { throw ToolError("恢复本地灯光方案失败：\(error)；测试错误：\(String(describing: failure))") }
        if let failure { throw failure }
        print("PASS: 2.4G 两次灯效命令和恢复本地方案均收到匹配应答。视觉效果需人工确认。")
    }
}
