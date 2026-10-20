import Foundation
import IOKit
import IOKit.hid

private final class BulkReply {
    var bytes: [UInt8]?
    var status: IOReturn = kIOReturnSuccess
}

extension USBKeyboard {
    // 0x432920: live RGB is a sequential list of index/R/G/B tuples, eight 64-byte reports.
    func displayColors(_ colors: [String: UInt32], layout: [KeyboardKey]) throws {
        var payload = [UInt8](repeating: 0, count: 512)
        guard layout.count <= 128 else { throw ToolError("实时灯光键位数超出协议范围。") }
        for (index, key) in layout.enumerated() {
            let color = colors[String(key.index)] ?? 0
            payload[index * 4] = UInt8(key.lightIndex)
            payload[index * 4 + 1] = UInt8((color >> 16) & 255)
            payload[index * 4 + 2] = UInt8((color >> 8) & 255)
            payload[index * 4 + 3] = UInt8(color & 255)
        }
        try withDevice {
            do {
                try liveCommand(KeyboardProtocol.command(0x20, blocks: 8))
                for offset in stride(from: 0, to: payload.count, by: 64) {
                    try write(Array(payload[offset..<offset + 64]), delay: 0.002)
                }
                try liveCommand(KeyboardProtocol.command(2))
            } catch {
                let original = error
                do { try finish() } catch { log("实时灯光收尾失败：\(error)") }
                throw original
            }
        }
    }

    private func liveCommand(_ payload: [UInt8]) throws {
        try write(payload, delay: 0.005)
        Thread.sleep(forTimeInterval: 0.005)
        let reply = try readFeature()
        guard reply[0] == payload[0], reply[1] == payload[1], reply[3] == 1 else {
            throw ToolError("实时灯光命令未确认：\(hex(Array(reply.prefix(12))))")
        }
    }

    // 0x422b50 / 0x44f1c0: 4096-byte output reports on the FF68 bulk interface.
    func uploadScreen(_ data: [UInt8], progress: (Int) -> Void) throws {
        guard !data.isEmpty, data.count % 4096 == 0, data.count <= 256 + 141 * 64800 + 4096 else {
            throw ToolError("屏幕数据长度无效。")
        }
        let matches = allDevices().filter {
            number($0, kIOHIDVendorIDKey) == 0x0c45 && number($0, kIOHIDProductIDKey) == 0x800a &&
            property($0, kIOHIDTransportKey) as? String == "USB" &&
            number($0, kIOHIDPrimaryUsagePageKey) == 0xff68 && number($0, kIOHIDPrimaryUsageKey) == 0x61 &&
            number($0, kIOHIDMaxOutputReportSizeKey) == 4096
        }
        guard matches.count == 1 else { throw ToolError("未找到唯一的 F108Pro USB 屏幕上传接口。") }
        let bulk = matches[0]
        try check(IOHIDDeviceOpen(bulk, IOOptionBits(kIOHIDOptionsTypeNone)), "打开屏幕上传接口")
        defer { IOHIDDeviceClose(bulk, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let loop = CFRunLoopGetCurrent() else { throw ToolError("无法创建上传应答运行循环。") }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffer.initialize(repeating: 0, count: 64)
        let reply = BulkReply()
        IOHIDDeviceRegisterInputReportCallback(bulk, buffer, 64, { context, status, _, _, _, bytes, length in
            guard let context else { return }
            let result = Unmanaged<BulkReply>.fromOpaque(context).takeUnretainedValue()
            result.status = status
            result.bytes = Array(UnsafeBufferPointer(start: bytes, count: min(64, max(0, length))))
        }, Unmanaged.passUnretained(reply).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(bulk, loop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(bulk, loop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(bulk, buffer, 64, nil, nil)
            buffer.deinitialize(count: 64); buffer.deallocate()
        }
        try transaction {
            try control(KeyboardProtocol.command(0x18))
            // The supplied macOS LCD tool uploads the user animation with selector zero.
            try control(KeyboardProtocol.command(0x72, blocks: data.count / 4096, option: 0))
            let count = data.count / 4096
            for index in 0..<count {
                reply.bytes = nil
                let packet = Array(data[index * 4096..<(index + 1) * 4096])
                try check(packet.withUnsafeBufferPointer {
                    IOHIDDeviceSetReport(bulk, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
                }, "上传屏幕数据块 \(index + 1)")
                let deadline = Date().addingTimeInterval(0.5)
                while reply.bytes == nil, Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.01, true) }
                try check(reply.status, "读取屏幕上传应答")
                guard let bytes = reply.bytes, bytes.count >= 2, bytes[0] == 1, bytes[1] == 0x5a else {
                    throw ToolError("屏幕数据块 \(index + 1) 超时或应答不是 01 5A。")
                }
                progress((index + 1) * 100 / count)
            }
        }
    }
}
