import AVFoundation
import Observation
import Speech

/// Turns speech into text for the meal description.
@MainActor
@Observable
final class MealDictation {
    enum State: Equatable { case idle, listening, denied }

    private(set) var state: State = .idle
    /// What has been recognized in the current session.
    fileprivate(set) var transcript = ""

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    var isListening: Bool { state == .listening }

    func toggle(locale: Locale) async {
        if isListening { stop() } else { await start(locale: locale) }
    }

    func stop() {
        guard engine.isRunning || request != nil else { state = state == .denied ? .denied : .idle; return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .listening { state = .idle }
    }

    private func start(locale: Locale) async {
        guard await Self.authorized(), let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            state = .denied
            return
        }
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device when the model is there; forcing it would fail for languages whose model is not downloaded.
        request.requiresOnDeviceRecognition = false
        self.request = request
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let sink = AudioSink(request)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(sink))
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            state = .denied
            return
        }
        state = .listening
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self))
    }

    /// Built outside the main actor: Speech calls it on a background queue.
    private nonisolated static func resultHandler(for dictation: MealDictation) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak dictation] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true || error != nil
            Task { @MainActor in
                guard let dictation else { return }
                if let text { dictation.transcript = text }
                if finished { dictation.stop() }
            }
        }
    }

    /// Runs on the audio thread, so it must not be main-actor isolated.
    private nonisolated static func tapBlock(_ sink: AudioSink) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in sink.append(buffer) }
    }

    private nonisolated static func speechAuthorization() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    private static func authorized() async -> Bool {
        let speech = await speechAuthorization()
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

/// Hands microphone buffers from the audio thread to the recognition request.
private final class AudioSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
}
