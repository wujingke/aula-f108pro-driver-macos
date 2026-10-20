import Foundation
import IOKit
import IOKit.hid

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// DeviceDriver.exe 0x423b10, transported by 0x44edc0 / 0x451330.
func timeReports(at date: Date, calendar: Calendar) throws -> [[UInt8]] {
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
    guard let year = parts.year, (2000...2255).contains(year),
          let month = parts.month, let day = parts.day, let hour = parts.hour,
          let minute = parts.minute, let second = parts.second, let weekday = parts.weekday else {
        throw ToolError("日期无法编码：年份必须在 2000–2255 之间。")
    }
    var begin = [UInt8](repeating: 0, count: 64)
    begin[0] = 0x04; begin[1] = 0x18
    var prepare = [UInt8](repeating: 0, count: 64)
    prepare[0] = 0x04; prepare[1] = 0x28; prepare[8] = 1
    var clock = [UInt8](repeating: 0, count: 64)
    // The supplied F108Pro layout supports one screen animation slot.
    clock[1] = 1; clock[2] = 0x5a
    clock[3] = UInt8(year - 2000); clock[4] = UInt8(month); clock[5] = UInt8(day)
    clock[6] = UInt8(hour); clock[7] = UInt8(minute); clock[8] = UInt8(second)
    clock[10] = UInt8(weekday - 1) // Windows SYSTEMTIME: Sunday = 0.
    clock[62] = 0xaa; clock[63] = 0x55
    var end = [UInt8](repeating: 0, count: 64)
    end[0] = 0x04; end[1] = 0x02
    return [begin, prepare, clock, end]
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func property(_ device: IOHIDDevice, _ key: String) -> AnyObject? {
    IOHIDDeviceGetProperty(device, key as CFString)
}

func number(_ device: IOHIDDevice, _ key: String) -> Int? {
    (property(device, key) as? NSNumber)?.intValue
}

func interfaceNumber(_ device: IOHIDDevice) -> Int? {
    var entry = IOHIDDeviceGetService(device)
    guard entry != 0 else { return nil }
    IOObjectRetain(entry)
    defer { IOObjectRelease(entry) }
    while true {
        if let value = IORegistryEntryCreateCFProperty(entry, "bInterfaceNumber" as CFString,
                                                     kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
            return value.intValue
        }
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        IOObjectRelease(entry)
        entry = parent
    }
}

func devices(_ manager: IOHIDManager) -> [IOHIDDevice] {
    let matches: [[String: Int]] = [
        [kIOHIDVendorIDKey: 0x0c45, kIOHIDProductIDKey: 0x800a],
        [kIOHIDVendorIDKey: 0x05ac, kIOHIDProductIDKey: 0x024f]
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
    return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
}

func description(_ device: IOHIDDevice) -> String {
    let name = property(device, kIOHIDProductKey) as? String ?? "未声明名称"
    let transport = property(device, kIOHIDTransportKey) as? String ?? "未声明连接类型"
    let iface = interfaceNumber(device).map(String.init) ?? "未知"
    let feature = number(device, kIOHIDMaxFeatureReportSizeKey).map(String.init) ?? "未知"
    let input = number(device, kIOHIDMaxInputReportSizeKey).map(String.init) ?? "未知"
    return "\(name) | \(transport) | interface=\(iface) | feature=\(feature) | input=\(input)"
}

func check(_ status: IOReturn, _ action: String) throws {
    guard status == kIOReturnSuccess else {
        throw ToolError(String(format: "%@失败：IOReturn=0x%08X", action, status))
    }
}

func replyMatches(_ reply: [UInt8], payload: [UInt8]) -> Bool {
    guard reply.count == 64, payload.count == 64 else { return false }
    if payload[0] == 0, payload[2] == 0x5a { return reply == payload }
    return reply[3] == 1
}

func send(_ payload: [UInt8], to device: IOHIDDevice) throws {
    Thread.sleep(forTimeInterval: 0.035)
    // Unnumbered report: macOS gets 64 payload bytes; Windows prepends an extra zero report ID.
    let status = payload.withUnsafeBufferPointer {
        IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
    }
    try check(status, "发送校时报文")
    Thread.sleep(forTimeInterval: 0.035)
    var reply = [UInt8](repeating: 0, count: 64)
    var length = reply.count
    // Windows IOCTL_HID_GET_FEATURE = 0x000b0192 (function 100, METHOD_OUT_DIRECT).
    let readStatus = reply.withUnsafeMutableBufferPointer {
        IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &length)
    }
    try check(readStatus, "读取键盘应答")
    print("Feature 应答：\(hex(Array(reply.prefix(12)))) …（\(length) bytes）")
    guard replyMatches(Array(reply.prefix(length)), payload: payload) else {
        throw ToolError("键盘应答未通过校验（length=\(length)）：\(hex(Array(reply.prefix(length))))")
    }
}

func selfTest() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let leapDay = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29, hour: 23, minute: 59, second: 58))!
    let reports = try timeReports(at: leapDay, calendar: calendar)
    var expected = [UInt8](repeating: 0, count: 64)
    expected.replaceSubrange(0...10, with: [0, 1, 0x5a, 24, 2, 29, 23, 59, 58, 0, 4])
    expected[62] = 0xaa; expected[63] = 0x55
    guard reports.count == 4, reports.allSatisfy({ $0.count == 64 }), reports[2] == expected,
          reports[0][0...1] == [4, 0x18], reports[1][8] == 1, reports[3][0...1] == [4, 2] else {
        throw ToolError("校时报文自检失败。")
    }
    var commandReply = reports[0]
    commandReply[3] = 1
    var wrongClock = expected
    wrongClock[3] &+= 1
    guard replyMatches(commandReply, payload: reports[0]), replyMatches(expected, payload: expected),
          !replyMatches(reports[0], payload: reports[0]), !replyMatches(wrongClock, payload: expected),
          !replyMatches([], payload: expected) else {
        throw ToolError("应答校验自检失败。")
    }
    let sunday = calendar.date(from: DateComponents(year: 2000, month: 1, day: 2))!
    guard try timeReports(at: sunday, calendar: calendar)[2][10] == 0 else {
        throw ToolError("星期编码自检失败。")
    }
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let local = try timeReports(at: leapDay, calendar: calendar)[2]
    guard Array(local[4...8]) == [3, 1, 7, 59, 58], local[10] == 5 else {
        throw ToolError("本地时区转换自检失败。")
    }
    let oldDate = calendar.date(from: DateComponents(year: 1999, month: 12, day: 31))!
    do {
        _ = try timeReports(at: oldDate, calendar: calendar)
    } catch {
        print("报文自检通过：闰日、跨日时区转换、Sunday=0、年份边界。")
        return
    }
    throw ToolError("年份边界自检失败。")
}

#if !F108_APP
func runCLI() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 1 else {
        print("用法：f108-time --list | --dry-run | --sync | --self-test")
        if !args.isEmpty { throw ToolError("参数错误。") }
        return
    }
    if args[0] == "--self-test" { try selfTest(); return }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    if args[0] == "--dry-run" {
        let date = Date()
        print("本地时间：\(date.formatted(date: .numeric, time: .standard))（\(calendar.timeZone.identifier)）")
        for (index, report) in try timeReports(at: date, calendar: calendar).enumerated() {
            print("\(index + 1). Feature report ID=0, payload=64: \(hex(report))")
        }
        return
    }
    guard ["--list", "--sync"].contains(args[0]) else { throw ToolError("未知参数：\(args[0])") }
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let found = devices(manager)
    if args[0] == "--list" {
        if found.isEmpty { print("未发现匹配的 F108Pro HID 设备。") }
        for device in found { print(description(device)) }
        return
    }
    let candidates = found.filter {
        number($0, kIOHIDVendorIDKey) == 0x0c45 && number($0, kIOHIDProductIDKey) == 0x800a &&
        property($0, kIOHIDTransportKey) as? String == "USB" && interfaceNumber($0) == 3 &&
        number($0, kIOHIDPrimaryUsagePageKey) == 0xff13 &&
        number($0, kIOHIDMaxFeatureReportSizeKey) == 64
    }
    guard candidates.count == 1 else {
        for device in found { print(description(device)) }
        throw ToolError("需要唯一的 F108Pro USB 配置接口（0C45:800A, interface 3, usage page FF13, Feature=64）。请切换有线模式。当前候选数：\(candidates.count)。")
    }
    let device = candidates[0]
    try check(IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)), "打开键盘配置接口")
    defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    print(description(device))
    let date = Date()
    let reports = try timeReports(at: date, calendar: calendar)
    do {
        for report in reports { try send(report, to: device) }
    } catch {
        let syncError = error
        do { try send(reports[3], to: device) } catch {
            FileHandle.standardError.write(Data("收尾命令也失败：\(error)\n".utf8))
        }
        throw syncError
    }
    print("校时序列已完成：\(date.formatted(date: .numeric, time: .standard))（\(calendar.timeZone.identifier)）。")
    print("3 条命令应答及时间报文回显已校验；请确认键盘屏幕，尚无独立的时钟读回验证。")
}

@main
enum F108TimeMain {
    static func main() {
        do { try runCLI() } catch {
            FileHandle.standardError.write(Data("错误：\(error)\n".utf8))
            exit(1)
        }
    }
}
#endif
