import AppKit

@main
enum HardwareCheck {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else { throw ToolError("用法：hardware-check time | live | restore | read-colors") }
            let keyboard = USBKeyboard()
            guard keyboard.configurationDevices().count == 1 else { throw ToolError("需要唯一的 F108Pro USB 配置接口。") }
            switch CommandLine.arguments[1] {
            case "time":
                try keyboard.syncTime()
                print("PASS: GUI 共用 USB 后端的校时命令及时间回显。")
            case "restore":
                try restore(keyboard)
            case "live":
                let layoutURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("build/AULA F108Pro.app/Contents/Resources/Assets/keyboard.json")
                let layout = try JSONDecoder().decode([KeyboardKey].self, from: Data(contentsOf: layoutURL))
                guard layout.count == 104 else { throw ToolError("测试布局必须包含 104 个键位。") }
                var failure: Error?
                do {
                    for color: UInt32 in [0x003060, 0x006030] {
                        let colors = Dictionary(uniqueKeysWithValues: layout.map { (String($0.index), color) })
                        try keyboard.displayColors(colors, layout: layout)
                        print(String(format: "PASS: 实时灯光 %06X，开始和结束命令均得到确认。", color))
                        Thread.sleep(forTimeInterval: 1)
                    }
                } catch { failure = error }
                do { try restore(keyboard) } catch {
                    throw ToolError("测试后的灯效恢复命令失败：\(error)；原测试错误：\(String(describing: failure))")
                }
                if let failure { throw failure }
                print("PASS: 两次实时推送完成；已确认保存灯效的恢复命令。灯光视觉效果需人工观察。")
            case "read-colors":
                try readColors(keyboard)
            default: throw ToolError("未知测试项。")
            }
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func readColors(_ keyboard: USBKeyboard) throws {
        let bytes = try keyboard.withDevice {
            do {
                try keyboard.control(KeyboardProtocol.command(0xf5, blocks: 9))
                var data = Data()
                for _ in 0..<9 {
                    Thread.sleep(forTimeInterval: 0.003)
                    data.append(contentsOf: try keyboard.readFeature())
                }
                try keyboard.finish()
                return data
            } catch {
                let original = error
                do { try keyboard.finish() } catch { print("读取后的收尾失败：\(error)") }
                throw original
            }
        }
        try bytes.write(to: URL(fileURLWithPath: "analysis/hardware-user-colors.bin"))
        print("PASS: 只读用户灯光数据 \(bytes.count) bytes；头部：\(hex(Array(bytes.prefix(32))))")
    }

    private static func restore(_ keyboard: USBKeyboard) throws {
        _ = try keyboard.withDevice { try keyboard.control(KeyboardProtocol.command(0xf0)) }
        print("PASS: 04 F0 恢复保存灯效，设备应答通过。")
    }
}
