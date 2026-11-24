import Foundation

#if canImport(AVFoundation) && !os(watchOS)
import AVFoundation

/// Sample-accurate native Audio Psychophysics Engine for macOS & iOS.
///
/// Key AirPods / Bluetooth engineering feature:
/// Runs an ultra-quiet (-72 dB, 70 Hz) continuous PCM carrier while active so
/// AirPods / Bluetooth audio pipelines stay locked open with zero DAC fade-in
/// clipping. Both clicks in a two-pulse trial are synthesized into a single
/// contiguous 48 kHz PCM buffer, preserving ~20.8 microsecond relative gap accuracy.
@MainActor
public final class AudioPsychophysicsEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var keepAliveNode: AVAudioSourceNode?
    private let sampleRate: Double = 48_000.0
    private var isStarted = false
    public var airPodsKeepAliveEnabled: Bool = true

    public init() {}

    public func startSessionAudio() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .measurement, options: [.allowBluetoothA2DP])
        try? session.setActive(true)
        #endif

        guard !isStarted else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        if airPodsKeepAliveEnabled {
            var phase: Double = 0.0
            let sr = sampleRate
            let phaseStep = 2.0 * .pi * 70.0 / sr
            let src = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for frame in 0..<Int(frameCount) {
                    let sample = Float(sin(phase) * 0.00025) // ~ -72 dB keep-alive carrier
                    phase += phaseStep
                    if phase > 2.0 * .pi { phase -= 2.0 * .pi }
                    for buf in abl {
                        if let ptr = buf.mData?.assumingMemoryBound(to: Float.self) {
                            ptr[frame] = sample
                        }
                    }
                }
                return noErr
            }
            keepAliveNode = src
            engine.attach(src)
            engine.connect(src, to: engine.mainMixerNode, format: format)
        }

        do {
            try engine.start()
            player.play()
            isStarted = true
        } catch {
            // Audio device unavailable (e.g. headless CI)
        }
    }

    public func stopSessionAudio() {
        guard isStarted else { return }
        player.stop()
        engine.stop()
        if let src = keepAliveNode {
            engine.detach(src)
            keepAliveNode = nil
        }
        engine.detach(player)
        isStarted = false
    }

    /// Play 1 single click or 2 sample-locked clicks separated by `gapMs` milliseconds.
    public func playTwoPulseStimulus(isTwoPulses: Bool, gapMs: Double) {
        startSessionAudio()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        let clickDurSec = 0.007
        let clickFrames = Int(sampleRate * clickDurSec)
        let leadFrames = Int(sampleRate * 0.08) // 80 ms lead-in inside continuous stream
        let gapFrames = isTwoPulses ? Int(round(sampleRate * (gapMs / 1000.0))) : 0
        let totalFrames = leadFrames + gapFrames + clickFrames + Int(sampleRate * 0.05)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
              let ch = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        memset(ch, 0, totalFrames * MemoryLayout<Float>.size)

        func writeClick(at startFrame: Int) {
            for i in 0..<clickFrames {
                let idx = startFrame + i
                guard idx < totalFrames else { break }
                let t = Double(i) / sampleRate
                // Hann window prevents speaker/AirPods transient clicks
                let env = 0.5 * (1.0 - cos(2.0 * .pi * Double(i) / Double(clickFrames - 1)))
                let wave = sin(2.0 * .pi * 1280.0 * t)
                ch[idx] += Float(0.55 * env * wave)
            }
        }

        writeClick(at: leadFrames)
        if isTwoPulses {
            writeClick(at: leadFrames + gapFrames)
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Play an exact `durationMs` (default 1500 ms) 440 Hz reference tone.
    public func playReferenceTone(durationMs: Double = 1500.0) {
        startSessionAudio()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        let durSec = durationMs / 1000.0
        let totalFrames = Int(round(sampleRate * durSec))
        let rampFrames = Int(sampleRate * 0.015)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
              let ch = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        for i in 0..<totalFrames {
            let t = Double(i) / sampleRate
            var env = 1.0
            if i < rampFrames {
                env = Double(i) / Double(rampFrames)
            } else if i > totalFrames - rampFrames {
                env = Double(totalFrames - i) / Double(rampFrames)
            }
            ch[i] = Float(0.22 * env * sin(2.0 * .pi * 440.0 * t))
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }
}
#endif
