//
//  RNGTimerSound.swift
//  PKReference
//
//  The RNG Timer's beeps: a short generated tone, scheduled ahead on the
//  audio engine at the host times the timer works out, so a busy main
//  thread can't make one late. On iOS it plays with the silent switch on.
//

import AVFoundation

/// The timer's clock: the host's monotonic time (`mach_absolute_time`) in
/// seconds, the clock audio is scheduled on.
nonisolated enum RNGTimerClock {
    static func now() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }
}

/// What the timer needs from a sound: beeps at times on `RNGTimerClock`.
protocol TimerBeeper: AnyObject {
    /// Gets the output going, so the first beep isn't late.
    func prepare()
    /// Beeps at each time, in order.
    func schedule(_ times: [Double])
    /// Drops every beep not yet played.
    func cancelAll()
}

final class RNGTimerSound: TimerBeeper {
    static let shared = RNGTimerSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var tone = Self.tone(format: format)
    private var attached = false
    /// Scheduled and not yet played, to schedule again if the output
    /// changes (headphones plugged in), which stops the engine.
    private var pending: [Double] = []
    private var configurationObserver: NSObjectProtocol?

    private init() {}

    func prepare() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        if !attached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            attached = true
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.restart() }
                }
        }
        guard !engine.isRunning else {
            if !player.isPlaying { player.play() }
            return
        }
        do {
            try engine.start()
            player.play()
        } catch {
            print("[RNGTimerSound] couldn't start audio: \(error)")
        }
    }

    func schedule(_ times: [Double]) {
        let now = RNGTimerClock.now()
        pending.removeAll { $0 <= now }
        pending.append(contentsOf: times)
        enqueue(times)
    }

    func cancelAll() {
        pending.removeAll()
        player.stop()
        if engine.isRunning { player.play() }
    }

    /// One beep now, to hear what it sounds like.
    func beepNow() {
        prepare()
        schedule([RNGTimerClock.now()])
    }

    /// A buffer starts when its first sample reaches the output, so each
    /// starts early by the output's latency (much more over Bluetooth).
    private func enqueue(_ times: [Double]) {
        guard engine.isRunning else { return }
        let latency = engine.outputNode.presentationLatency
        let now = RNGTimerClock.now()
        for time in times where time > now - 0.05 {
            let at = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: max(now, time - latency)))
            player.scheduleBuffer(tone, at: at, options: [], completionHandler: nil)
        }
    }

    private func restart() {
        let now = RNGTimerClock.now()
        pending.removeAll { $0 <= now }
        player.stop()
        do {
            try engine.start()
            player.play()
            enqueue(pending)
        } catch {
            print("[RNGTimerSound] couldn't restart audio: \(error)")
        }
    }

    /// 60 ms of 1 kHz with 5 ms fades, so it doesn't click.
    private static func tone(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * 0.06)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let fade = rate * 0.005
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i)
            let envelope = min(1, t / fade, (Double(frames) - t) / fade)
            samples[i] = Float(0.6 * envelope * sin(2 * .pi * 1_000 * t / rate))
        }
        return buffer
    }
}
