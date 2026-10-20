import Foundation

// Native evidence: analysis/wireless-protocol-functions.json. Offsets exclude Windows' zero Report ID.
extension WirelessProtocol {
    static func light(_ settings: LightSettings) throws -> [UInt8] {
        let usb = try KeyboardProtocol.light(settings)
        var data = packet(command: 5, subcommand: 0x10)
        data.replaceSubrange(3..<15, with: usb[0..<12])
        data[17] = 0xaa; data[18] = 0x55
        return data
    }

    static func system(_ settings: SystemSettings) throws -> [UInt8] {
        let usb = try KeyboardProtocol.system(settings)
        var data = packet(command: 7, subcommand: 0x10)
        data.replaceSubrange(4..<13, with: usb[1..<10])
        data[17] = 0xaa; data[18] = 0x55
        return data
    }

    static func time(at date: Date, calendar: Calendar) throws -> [UInt8] {
        let clock = try timeReports(at: date, calendar: calendar)[2]
        var data = packet(command: 0x0c, subcommand: 0x10)
        data.replaceSubrange(4..<14, with: clock[1..<11])
        data[17] = 0xaa; data[18] = 0x55
        return data
    }

    static func bindings(_ profile: DriverProfile, fnLayer: Bool, layout: [KeyboardKey]) throws -> [[UInt8]] {
        let data = try KeyboardProtocol.bindings(fnLayer ? profile.fnKeys : profile.keys, macros: profile.macros, layout: layout)
        return try chunks(data, command: fnLayer ? 0x12 : 0x10)
    }

    static func colors(_ colors: [String: UInt32], layout: [KeyboardKey]) throws -> [[UInt8]] {
        var mode = packet(command: 5, subcommand: 0x10)
        mode[3] = 0x80; mode[12] = 5; mode[17] = 0xaa; mode[18] = 0x55
        return try [mode] + chunks(KeyboardProtocol.colors(colors, layout: layout), command: 0x14)
    }

    static func macros(_ macros: [KeyboardMacro]) throws -> [[UInt8]] {
        let body = try KeyboardProtocol.macroBody(macros)
        let count = (body.count + 27) / 28 + 1
        var data = body + [UInt8](repeating: 0, count: count * 28 - body.count)
        data[data.count - 2] = 0xaa; data[data.count - 1] = 0x55
        return try chunks(data, command: 9, lastCount: body.count % 28)
    }

    static func spectrum(_ bands: [Float]) throws -> [UInt8] {
        guard bands.count == 21, bands.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ToolError("2.4G 音乐律动需要 21 个有效的频谱值。")
        }
        var data = packet(command: 0x0b, subcommand: 0x1c)
        data[3] = 1; data[4] = 0; data[5] = 100
        // 0x433443–0x43345e encodes column height against the six keyboard rows.
        data.replaceSubrange(6..<27, with: bands.map { UInt8(($0 * 6).rounded()) })
        return data
    }

    private static func chunks(_ data: [UInt8], command: UInt8, lastCount: Int? = nil) throws -> [[UInt8]] {
        guard !data.isEmpty, data.count <= 28 * 256 else { throw ToolError("2.4G 数据超出分包范围。") }
        if let lastCount, !(0...28).contains(lastCount) { throw ToolError("2.4G 尾包长度无效。") }
        var result = [[UInt8]]()
        for offset in stride(from: 0, to: data.count, by: 28) {
            let count = min(28, data.count - offset)
            var report = packet(command: command, subcommand: UInt8(count))
            report[2] = UInt8(offset / 28)
            report.replaceSubrange(3..<3 + count, with: data[offset..<offset + count])
            if offset + count == data.count, let lastCount { report[1] = UInt8(lastCount) }
            result.append(report)
        }
        return result
    }
}

extension WirelessKeyboard {
    func syncTime() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        try execute([WirelessProtocol.time(at: Date(), calendar: calendar)])
    }
    func applyLight(_ settings: LightSettings) throws { try execute([WirelessProtocol.light(settings)]) }
    func applySystem(_ settings: SystemSettings) throws { try execute([WirelessProtocol.system(settings)]) }
    func applyColors(_ colors: [String: UInt32], layout: [KeyboardKey]) throws { try execute(WirelessProtocol.colors(colors, layout: layout)) }
    func applyBindings(_ profile: DriverProfile, fnLayer: Bool, layout: [KeyboardKey]) throws {
        try execute(WirelessProtocol.bindings(profile, fnLayer: fnLayer, layout: layout))
    }
    func applyMacros(_ macros: [KeyboardMacro]) throws { try execute(WirelessProtocol.macros(macros)) }
    func displaySpectrum(_ bands: [Float]) throws { try execute([WirelessProtocol.spectrum(bands)]) }
}
