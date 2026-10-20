import Foundation
import IOKit
import IOKit.hid

enum WirelessProtocol {
    // Windows uses 33 bytes including its zero Report ID; macOS sends the remaining 32.
    static func packet(command: UInt8, subcommand: UInt8 = 0) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[0] = command; bytes[1] = subcommand
        return bytes
    }

    static func seal(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count == 32 else { throw ToolError("2.4G 报文必须为 32 字节。") }
        var result = bytes
        result[31] = result.prefix(31).reduce(UInt8(0), &+)
        return result
    }
}

final class WirelessKeyboard: @unchecked Sendable {
    private let lock = NSLock()

    func configurationDevices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        return devices(manager).filter {
            number($0, kIOHIDVendorIDKey) == 0x05ac && number($0, kIOHIDProductIDKey) == 0x024f &&
            property($0, kIOHIDTransportKey) as? String == "USB" && interfaceNumber($0) == 3 &&
            number($0, kIOHIDMaxOutputReportSizeKey) == 32 &&
            number($0, kIOHIDMaxInputReportSizeKey) == 32
        }
    }

    @discardableResult
    func execute(_ packets: [[UInt8]]) throws -> [[UInt8]] {
        guard !packets.isEmpty else { throw ToolError("2.4G 设置报文为空。") }
        let sealed = try packets.map(WirelessProtocol.seal)
        lock.lock(); defer { lock.unlock() }
        let matches = configurationDevices()
        guard matches.count == 1 else {
            throw ToolError("未找到唯一的 F108Pro 2.4G 配置接口。需要配套接收器的 interface 3、32 字节输出通道；相同 VID/PID 的普通键盘接口不能用于设置。")
        }
        guard let loop = CFRunLoopGetCurrent() else { throw ToolError("无法建立 2.4G 应答运行循环。") }
        try check(IOHIDDeviceOpen(matches[0], IOOptionBits(kIOHIDOptionsTypeNone)), "打开 2.4G 接收器配置接口")
        let session = WirelessSession(device: matches[0], loop: loop)
        defer { session.close() }
        if sealed[0][0] != 2 {
            _ = try session.send(WirelessProtocol.seal(WirelessProtocol.packet(command: 2)))
        }
        return try sealed.map { try session.send($0) }
    }
}

private final class WirelessSession {
    let device: IOHIDDevice
    let loop: CFRunLoop
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    var replies = [[UInt8]]()
    var inputStatus = kIOReturnSuccess
    var overflow = false
    var closed = false

    init(device: IOHIDDevice, loop: CFRunLoop) {
        self.device = device; self.loop = loop
        buffer.initialize(repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, status, _, _, _, bytes, length in
            guard let context else { return }
            let session = Unmanaged<WirelessSession>.fromOpaque(context).takeUnretainedValue()
            session.inputStatus = status
            guard (3...64).contains(length), session.replies.count < 32 else { session.overflow = true; return }
            session.replies.append(Array(UnsafeBufferPointer(start: bytes, count: length)))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
    }

    func send(_ packet: [UInt8]) throws -> [UInt8] {
        guard packet.count == 32 else { throw ToolError("2.4G 报文长度错误。") }
        replies.removeAll(); inputStatus = kIOReturnSuccess; overflow = false
        try check(packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }, "发送 2.4G 设置")
        let deadline = Date().addingTimeInterval(0.5)
        var observed = [[UInt8]]()
        while Date() < deadline {
            try check(inputStatus, "读取 2.4G 接收器应答")
            guard !overflow else { throw ToolError("2.4G 接收器返回了异常报文。") }
            if let reply = replies.first(where: { Array($0.prefix(3)) == Array(packet.prefix(3)) }) { return reply }
            observed.append(contentsOf: replies.prefix(max(0, 4 - observed.count)))
            replies.removeAll()
            CFRunLoopRunInMode(.defaultMode, 0.005, true)
        }
        let received = observed.isEmpty ? "未收到输入报文" : observed.map { hex($0) }.joined(separator: "; ")
        throw ToolError("2.4G 命令未收到匹配应答：\(hex(Array(packet.prefix(4))))；\(received)。")
    }

    func close() {
        guard !closed else { return }; closed = true
        IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        buffer.deinitialize(count: 64); buffer.deallocate()
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit { close() }
}
