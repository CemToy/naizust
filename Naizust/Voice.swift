import SwiftUI
import Speech
import AVFoundation

@MainActor final class Voice: ObservableObject {
    @Published var transcript = ""
    @Published var issue = ""
    @Published var active = false
    @Published var pending = false
    var timing: [TimedWord] = []
    var file: URL?
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var job: SFSpeechRecognitionTask?
    private var installed = false
    private var generation = UUID()
    private var player: AVAudioPlayer?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var prefix = ""
    private var previousTimes: [TimedWord] = []
    private var offset = 0.0
    private var recording: AVAudioFile?

    func reset() {
        stop()
        transcript = ""; issue = ""; timing = []; file = nil; recording = nil
        player?.stop()
    }
    func start() async {
        guard !pending, !active else { return }
        pending = true
        defer { pending = false }
        let token = generation
        let permission = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard token == generation else { return }
        guard permission == .authorized, await AVAudioApplication.requestRecordPermission() else {
            issue = "Разреши доступ к микрофону и распознаванию речи в настройках iPhone."; return
        }
        guard token == generation else { return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            issue = "Автономное распознавание русской речи сейчас недоступно на этом iPhone."; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.fileReadUnknown) }
            if recording == nil {
                let folder = URL.documentsDirectory.appending(path: "Recordings")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: UUID().uuidString + ".caf")
                recording = try AVAudioFile(forWriting: url, settings: format.settings)
                file = url
            }
            guard let recording, recording.processingFormat == format else {
                issue = "Изменился аудиовход. Заверши текущую попытку."; stop(); return
            }
            prefix = transcript
            previousTimes = timing
            offset = Double(recording.length) / format.sampleRate
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request
            let epoch = UUID()
            generation = epoch
            job = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == epoch else { return }
                    if let result {
                        let best = result.bestTranscription
                        self.transcript = [self.prefix,best.formattedString].filter { !$0.isEmpty }.joined(separator: " ")
                        self.timing = self.previousTimes + best.segments.flatMap { s in
                            words(s.substring).map { TimedWord(word: $0, time: self.offset+s.timestamp) }
                        }
                    }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                        self.issue = "Запись приостановлена. Можно продолжить с этого места."
                    }
                }
            }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
                do { try recording.write(from: buffer) }
                catch { Task { @MainActor [weak self] in
                    guard let self, self.generation == epoch else { return }
                    self.stop(); self.issue = "Не удалось записать звук. Проверь свободное место."
                } }
            }
            installed = true
            try engine.start()
            active = true; issue = ""
        } catch { stop(); issue = "Не удалось включить запись. " + error.localizedDescription }
    }
    func stop() {
        generation = UUID()
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        request?.endAudio(); job?.cancel(); job = nil; request = nil
        active = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func finish() async {
        if active {
            engine.stop()
            if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
            request?.endAudio()
            for _ in 0..<25 where active {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        stop()
        recording = nil
        if issue.hasPrefix("Запись приостановлена") { issue = "" }
    }
    func listen(_ filename: String, at second: Double = 0) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            let url = URL.documentsDirectory.appending(path: "Recordings").appending(path: filename)
            player = try AVAudioPlayer(contentsOf: url)
            player?.currentTime = max(0,second-0.3)
            player?.play()
        } catch { issue = "Не удалось воспроизвести запись." }
    }
    func silence() { player?.stop() }
}
