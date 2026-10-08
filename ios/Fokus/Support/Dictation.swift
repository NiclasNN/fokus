import Foundation
import Speech
import AVFoundation

/// Röst till text, på telefonen. Svensk taligenkänning körs lokalt när
/// enheten klarar det, så det du säger lämnar aldrig telefonen.
@MainActor
final class Dictation: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var listening = false
    @Published var problem: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "sv-SE"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !listening else { return }
        problem = nil

        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else {
            problem = "Taligenkänning är avstängd för Fokus. Slå på den i Inställningar → Fokus — eller skriv i rutan."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "Fokus får inte använda mikrofonen. Slå på den i Inställningar → Fokus — eller skriv i rutan."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            problem = "Svensk taligenkänning är inte tillgänglig just nu. Du kan skriva i rutan i stället."
            return
        }
        // Löftet är att inget lämnar telefonen. Utan lokal svensk igenkänning
        // skulle ljudet gå till Apples servrar — hellre säga det än göra det.
        guard recognizer.supportsOnDeviceRecognition else {
            problem = "Svensk taligenkänning på telefonen saknas. Lägg till svenska under Inställningar → Allmänt → Tangentbord → Diktering — eller skriv i rutan."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            problem = "Kunde inte starta mikrofonen."
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true          // punkter och komman hjälper uppdelningen
        req.requiresOnDeviceRecognition = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            problem = "Kunde inte starta mikrofonen."
            teardown()
            return
        }

        // Pratar man igen efter en paus ska det läggas till, inte skriva över.
        let before = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = before.isEmpty ? "" : before + " "

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = prefix + result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) { self.teardown() }
            }
        }
        listening = true
        Haptics.press()
    }

    func stop() {
        guard listening else { return }
        request?.endAudio()
        teardown()
        Haptics.tap()
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        listening = false
        // Tillbaka till appens vanliga ljudläge, så tickljuden fungerar igen
        // och användarens musik inte förblir nedtonad.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
