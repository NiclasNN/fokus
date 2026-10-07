import AVFoundation

/// Syntetiserade toner — inga ljudfiler att packa med. Ett detentklick är
/// två partialer med snabb exponentiell död: torr transient upptill, kropp under.
///
/// Två fällor som kraschade appen första gången och som konstruktionen nu
/// skyddar mot:
///  1. `AVAudioEngine.start()` kastar ett ObjC-undantag — som `try?` INTE kan
///     fånga — om grafen saknar in- eller utgång. Därför måste `mainMixerNode`
///     röras och spelarna kopplas in INNAN motorn startas.
///  2. En ny nod per klick (attach/connect/detach under pågående drag) river
///     sönder grafen. I stället ligger en liten fast pool och turas om.
@MainActor
final class Sound {
    static let shared = Sound()
    var enabled = true

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var ready = false
    private var lastTick = Date.distantPast

    private func prepare() {
        guard !ready else { return }
        let session = AVAudioSession.sharedInstance()
        // .ambient: appens pling ska aldrig pausa användarens musik
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let mixer = engine.mainMixerNode          // skapar utgången — måste ske före start()
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: mixer, format: format)
            players.append(p)
        }
        engine.prepare()
        do { try engine.start() } catch { return }
        ready = true
    }

    private func play(_ partials: [(freq: Double, gain: Double, seconds: Double)]) {
        guard enabled else { return }
        prepare()
        guard ready else { return }
        if !engine.isRunning, (try? engine.start()) == nil { return }

        let sr = 44_100.0
        let total = partials.map(\.seconds).max() ?? 0.1
        let frames = AVAudioFrameCount(sr * total)
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buf.floatChannelData?[0] else { return }
        buf.frameLength = frames

        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            var v = 0.0
            for p in partials where t < p.seconds {
                // tonhöjden faller genom klicket, amplituden dör exponentiellt
                let f = p.freq * (1.0 - 0.28 * (t / p.seconds))
                v += sin(2 * .pi * f * t) * p.gain * exp(-t / (p.seconds * 0.26))
            }
            ch[i] = Float(max(-1, min(1, v)))
        }

        let node = players[next]
        next = (next + 1) % players.count
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    enum Detent { case minute, five, hour }

    func detent(_ kind: Detent, up: Bool) {
        guard enabled, Date().timeIntervalSince(lastTick) > 0.022 else { return }
        lastTick = Date()
        let base: Double = kind == .hour ? 1500 : kind == .five ? 2500 : 2050
        let f = base * (up ? 1.06 : 0.94)
        let len: Double = kind == .hour ? 0.05 : 0.018
        let vol: Double = kind == .minute ? 0.10 : kind == .five ? 0.15 : 0.20
        var parts: [(Double, Double, Double)] = [(f, vol, len), (f * 0.5, vol * 0.55, len * 1.6)]
        if kind == .hour { parts.append((320, 0.18, 0.12)) }
        play(parts)
    }
    /// Bockens "plink" — kvittot på att något blev gjort.
    func check() { play([(1046.5, 0.14, 0.09), (1568, 0.10, 0.16)]) }
    func start() { play([(523.25, 0.22, 0.28), (783.99, 0.16, 0.34)]) }
    func done()  { play([(880, 0.22, 0.6), (1108.73, 0.18, 0.75), (1318.51, 0.15, 0.9)]) }
}
