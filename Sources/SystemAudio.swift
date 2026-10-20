import Accelerate
import AVFoundation
import ScreenCaptureKit

@MainActor
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var starting: Task<Void, Never>?
    private let audioQueue = DispatchQueue(label: "com.aula.f108pro.audio")
    var gain: Float = 1
    var onBands: ([Float]) -> Void = { _ in }
    var onError: (Error) -> Void = { _ in }

    func start() {
        starting = Task { [weak self] in
            guard let self else { return }
            do {
                let available = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let display = available.displays.first else { throw ToolError("无法找到可用于系统音频采集的显示器。") }
                try Task.checkCancellation()
                let configuration = SCStreamConfiguration()
                configuration.width = 2; configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
                configuration.capturesAudio = true; configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 48000; configuration.channelCount = 1
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
                try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
                stream = capture
                try await capture.startCapture()
                if Task.isCancelled { try await capture.stopCapture() }
            } catch {
                if !Task.isCancelled { onError(error) }
            }
        }
    }

    func stop() {
        starting?.cancel(); starting = nil
        guard let stream else { return }
        self.stream = nil
        Task { [weak self] in
            do { try await stream.stopCapture() } catch { self?.onError(error) }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in self?.onError(error) }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM, description.mBitsPerChannel == 32,
              description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer), CMBlockBufferGetDataLength(block) >= 512 * 4 else { return }
        var samples = [Float](repeating: 0, count: 512)
        let status = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: 512 * 4, destination: $0.baseAddress!) }
        guard status == kCMBlockBufferNoErr else {
            Task { @MainActor [weak self] in self?.onError(ToolError("系统音频缓冲区读取失败：\(status)")) }
            return
        }
        guard let fft = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)) else {
            Task { @MainActor [weak self] in self?.onError(ToolError("无法创建音频频谱分析器。")) }
            return
        }
        defer { vDSP_destroy_fftsetup(fft) }
        var window = [Float](repeating: 0, count: 512)
        vDSP_hann_window(&window, 512, Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &samples, 1, 512)
        var real = [Float](repeating: 0, count: 256), imaginary = real
        var magnitudes = real
        for index in 0..<256 { real[index] = samples[index * 2]; imaginary[index] = samples[index * 2 + 1] }
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                vDSP_fft_zrip(fft, &split, 1, 9, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, 256)
            }
        }
        var bands = [Float]()
        for index in 0..<21 {
            let lower = max(1, Int(pow(255.0, Double(index) / 21)))
            let upper = max(lower + 1, min(256, Int(pow(255.0, Double(index + 1) / 21))))
            let power = magnitudes[lower..<upper].reduce(0, +) / Float(upper - lower)
            let normalized = max(0, min(1, (10 * log10(max(power / (512 * 512), 0.000001)) + 60) / 60))
            bands.append(normalized.isFinite ? normalized : 0)
        }
        let spectrum = bands
        Task { @MainActor [weak self] in
            guard let self else { return }
            onBands(spectrum.map { min(1, max(0, $0 * self.gain)) })
        }
    }
}
