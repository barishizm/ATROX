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
    /// Counts started sessions, so late answers of a finished one can be told apart.
    @ObservationIgnored private var session = 0

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
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // No usable microphone (e.g. during a call): installTap would raise an exception do/catch cannot catch.
            guard Self.isUsable(sampleRate: format.sampleRate, channels: format.channelCount) else { throw DictationError.noInput }
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
        session += 1
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self, session: session))
    }

    /// A tap needs a real input format; the input node reports 0 Hz / 0 channels while the microphone is unavailable.
    nonisolated static func isUsable(sampleRate: Double, channels: AVAudioChannelCount) -> Bool { sampleRate > 0 && channels > 0 }

    private enum DictationError: Error { case noInput }

    /// Built outside the main actor: Speech calls it on a background queue. Answers of an earlier session (a cancelled
    /// task reports an error after the user already started again) are ignored, so they cannot stop the new one.
    private nonisolated static func resultHandler(for dictation: MealDictation, session: Int)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak dictation] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true || error != nil
            Task { @MainActor in
                guard let dictation, dictation.session == session else { return }
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
