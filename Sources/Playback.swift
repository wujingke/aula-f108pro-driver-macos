import AppKit

extension DriverController {
    func startPlayback(music: Bool) {
        guard !busy, keyboard.configurationDevices().count == 1 else {
            setStatus("请连接所选模式的键盘，并等待当前操作完成。", error: true); return
        }
        guard music || keyboard.supportsLiveFrames else {
            setStatus("原驱动的无线菜单不支持实时逐键帧，请切换有线模式。", error: true); return
        }
        stopPlayback(); frameCursor = 0
        if music {
            let capture = SystemAudioCapture()
            capture.onBands = { [weak self] bands in self?.lastBands = bands }
            capture.onError = { [weak self] error in self?.stopPlayback(); self?.render(); self?.present(error) }
            audio = capture; capture.start()
        }
        nextPlaybackFrame = .distantPast
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickPlayback(music: music) }
        }
        render(); setStatus(music ? "音乐律动已启动；如果系统请求权限，请允许系统音频采集。" : "实时灯效播放中。")
    }

    private func tickPlayback(music: Bool) {
        guard playbackTimer != nil, !frameInFlight, !busy, Date() >= nextPlaybackFrame else { return }
        let colors: [String: UInt32]
        if music {
            colors = musicColors()
            nextPlaybackFrame = Date().addingTimeInterval(0.05)
        } else {
            let frames = store.current.frames
            guard !frames.isEmpty else { stopPlayback(); return }
            let frame = frames[frameCursor % frames.count]
            colors = frame.colors; frameCursor = (frameCursor + 1) % frames.count
            nextPlaybackFrame = Date().addingTimeInterval(Double(frame.duration) / 1000)
        }
        keyboardView?.colors = colors; frameInFlight = true
        let device = keyboard, layout = resources.layout, bands = lastBands
        worker.async { [weak self] in
            do {
                if music { try device.displayMusic(bands, colors: colors, layout: layout) }
                else { try device.displayColors(colors, layout: layout) }
                DispatchQueue.main.async { [weak self] in self?.frameInFlight = false }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.frameInFlight = false; self?.stopPlayback(); self?.render(); self?.present(error)
                }
            }
        }
    }

    func stopPlayback() {
        playbackTimer?.invalidate(); playbackTimer = nil
        previewTimer?.invalidate(); previewTimer = nil
        audio?.stop(); audio = nil
    }

    func musicColors() -> [String: UInt32] {
        var result = [String: UInt32]()
        for key in resources.layout {
            let column = min(20, max(0, Int((key.rect.midX / 800) * 21)))
            let row = max(0, min(5, (key.posY - 52) / 35))
            let threshold = Float(6 - row) / 6
            let level = lastBands[column]
            let color = NSColor(calibratedHue: CGFloat(column) / 21, saturation: 1, brightness: 1, alpha: 1)
            result[String(key.index)] = level >= threshold ? color.rgbValue : 0
        }
        return result
    }
}
