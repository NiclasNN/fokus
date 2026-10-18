import Foundation
import Speech
import AVFoundation

/// Röst till text. Svensk taligenkänning körs lokalt när enheten klarar
/// det, annars hos Apple som vanlig diktering.
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
        // Lokalt när telefonen har svensk igenkänning. Har den inte det sköter
        // Apple igenkänningen, precis som vanlig diktering — att stänga av en
        // funktion du redan använder vore sämre än att säga det som det är.
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
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
        // Avsluta ljudet men låt igenkänningen leverera sitt slutresultat —
        // att avbryta direkt tappade de sista orden man sa.
        request?.endAudio()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        listening = false
        Haptics.tap()
        let pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if let self, self.task === pending, pending != nil { self.teardown() }
        }
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
