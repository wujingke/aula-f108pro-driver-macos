import Foundation
import IOKit.hid

enum KeyboardConnection: String, CaseIterable, Sendable {
    case automatic = "自动选择"
    case usb = "USB 有线"
    case wireless = "2.4G 接收器"
}

final class KeyboardDevice: @unchecked Sendable {
    let usb = USBKeyboard()
    let wireless = WirelessKeyboard()
    private let lock = NSLock()
    private var preferred = KeyboardConnection.automatic

    var preferredConnection: KeyboardConnection {
        get { lock.lock(); defer { lock.unlock() }; return preferred }
        set { lock.lock(); defer { lock.unlock() }; preferred = newValue }
    }
    var currentConnection: KeyboardConnection { selection().kind }
    var supportsScreenUpload: Bool { currentConnection != .wireless }
    var supportsLiveFrames: Bool { currentConnection != .wireless }

    private func selection() -> (kind: KeyboardConnection, devices: [IOHIDDevice]) {
        switch preferredConnection {
        case .usb: return (.usb, usb.configurationDevices())
        case .wireless: return (.wireless, wireless.configurationDevices())
        case .automatic:
            let wired = usb.configurationDevices()
            if !wired.isEmpty { return (.usb, wired) }
            let radio = wireless.configurationDevices()
            return radio.isEmpty ? (.usb, []) : (.wireless, radio)
        }
    }

    func configurationDevices() -> [IOHIDDevice] { selection().devices }
    func syncTime() throws {
        if currentConnection == .wireless { try wireless.syncTime() } else { try usb.syncTime() }
    }
    func applyLight(_ settings: LightSettings) throws {
        if currentConnection == .wireless { try wireless.applyLight(settings) } else { try usb.applyLight(settings) }
    }
    func applySystem(_ settings: SystemSettings) throws {
        if currentConnection == .wireless { try wireless.applySystem(settings) } else { try usb.applySystem(settings) }
    }
    func applyColors(_ colors: [String: UInt32], layout: [KeyboardKey]) throws {
        if currentConnection == .wireless { try wireless.applyColors(colors, layout: layout) }
        else { try usb.applyColors(colors, layout: layout) }
    }
    func applyBindings(_ profile: DriverProfile, fnLayer: Bool, layout: [KeyboardKey]) throws {
        if currentConnection == .wireless { try wireless.applyBindings(profile, fnLayer: fnLayer, layout: layout) }
        else { try usb.applyBindings(profile, fnLayer: fnLayer, layout: layout) }
    }
    func applyMacros(_ macros: [KeyboardMacro]) throws {
        if currentConnection == .wireless { try wireless.applyMacros(macros) } else { try usb.applyMacros(macros) }
    }
    func displayColors(_ colors: [String: UInt32], layout: [KeyboardKey]) throws {
        guard supportsLiveFrames else { throw ToolError("原驱动的 2.4G 菜单不支持实时逐键帧，请使用有线模式。") }
        try usb.displayColors(colors, layout: layout)
    }
    func displayMusic(_ bands: [Float], colors: [String: UInt32], layout: [KeyboardKey]) throws {
        if currentConnection == .wireless { try wireless.displaySpectrum(bands) }
        else { try usb.displayColors(colors, layout: layout) }
    }
    func uploadScreen(_ data: [UInt8], progress: (Int) -> Void) throws {
        guard supportsScreenUpload else { throw ToolError("原驱动的 2.4G 菜单不支持屏幕上传，请切换为 USB 有线模式。") }
        try usb.uploadScreen(data, progress: progress)
    }
}
