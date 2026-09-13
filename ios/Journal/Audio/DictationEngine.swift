import Foundation
import AVFoundation
import Speech

/// State of the on-device dictation engine.
public enum DictationState: Sendable, Equatable {
    case idle
    case starting
    case listening(time: TimeInterval)
    case finishing
    case error(String)
}

public enum DictationError: LocalizedError {
    case speechRecognizerUnavailable
    case onDeviceRecognitionUnsupported
    case microphonePermissionDenied
    case speechPermissionDenied
    case alreadyRecording
    case audioSessionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Apple speech recognizer is not available for this locale."
        case .onDeviceRecognitionUnsupported:
            return "On-device speech recognition is not supported on this device/locale."
        case .microphonePermissionDenied:
            return "Microphone access was denied. Please allow microphone access in Settings."
        case .speechPermissionDenied:
            return "Speech recognition permission was denied. Please allow it in Settings."
        case .alreadyRecording:
            return "Dictation is already actively recording."
        case .audioSessionFailed(let msg):
            return "Audio session setup failed: \(msg)"
        }
    }
}

/// Thread-safe buffer relay connecting the real-time AVAudioEngine input tap to the active SFSpeechAudioBufferRecognitionRequest.
private final class AudioBufferRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = newRequest
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }

    func endAudio() {
        lock.lock()
        request?.endAudio()
        lock.unlock()
    }
}

/// On-Device Dictation Engine utilizing Apple's newest native Neural Engine models.
///
/// Features:
/// - 100% On-Device: `requiresOnDeviceRecognition = true` (zero network transmission).
/// - Continuous Rambling: Accumulates utterances across pauses without deleting previously transcribed thoughts.
/// - Seamless Utterance Recovery: Automatically spawns new recognition tasks on silence timeouts while audio keeps streaming.
/// - Modern Transformer Punctuation: Automatically adds commas, periods, and capitalization.
/// - Live Loudness Meter: Computes real-time RMS energy on the audio tap for visual metering.
/// - Zero App Download Overhead: Uses built-in OS models rather than bundling 180MB weights.
@MainActor
public class DictationEngine: NSObject, ObservableObject {
    @Published public private(set) var state: DictationState = .idle
    @Published public private(set) var currentText: String = ""
    @Published public private(set) var audioLevel: Float = 0.0

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var startTime: Date?

    // Concurrency relay for swapping recognition requests while audio tap is actively feeding PCM buffers
    private let bufferRelay = AudioBufferRelay()

    // Continuous rambling accumulation
    private var committedText: String = ""
    private var currentHypothesis: String = ""
    private var lastHypothesisTimestamp: TimeInterval = 0.0
    private var routeChangeObserver: NSObjectProtocol? = nil

    public var isRecording: Bool {
        if case .listening = state { return true }
        if case .starting = state { return true }
        return false
    }

    public init(locale: Locale = Locale.current) {
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Permissions

    /// Requests both Microphone and Speech Recognition permissions.
    public func requestAuthorization() async -> Bool {
        // 1. Microphone Permission
        #if os(iOS)
        let micAllowed: Bool
        if #available(iOS 17.0, *) {
            micAllowed = await AVAudioApplication.requestRecordPermission()
        } else {
            micAllowed = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard micAllowed else { return false }
        #endif

        // 2. Speech Recognition Permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return speechStatus == .authorized
    }

    // MARK: - Recording Controls

    /// Starts streaming on-device speech-to-text.
    public func start() async throws {
        guard !isRecording else { throw DictationError.alreadyRecording }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw DictationError.speechRecognizerUnavailable
        }

        // Enforce 100% on-device recognition for privacy
        if #available(iOS 13.0, macOS 10.15, *) {
            guard recognizer.supportsOnDeviceRecognition else {
                throw DictationError.onDeviceRecognitionUnsupported
            }
        }

        let authorized = await requestAuthorization()
        guard authorized else {
            throw DictationError.speechPermissionDenied
        }

        state = .starting
        committedText = ""
        currentHypothesis = ""
        lastHypothesisTimestamp = 0.0
        currentText = ""
        audioLevel = 0.0

        // Clean any previous session
        teardownSession()

        // Configure audio session on iOS with Bluetooth / AirPods support
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Enable Bluetooth HFP (AirPods / headsets) and A2DP routing with spoken audio mode
            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )

            // If a Bluetooth input (e.g. AirPods) is connected, prioritize it as the active input port
            if let bluetoothPort = audioSession.availableInputs?.first(where: {
                $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
            }) {
                try? audioSession.setPreferredInput(bluetoothPort)
            }

            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Listen for route changes (e.g. user puts in / takes out AirPods while recording)
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                guard let self = self, self.isRecording else { return }
                let session = AVAudioSession.sharedInstance()
                if let bluetooth = session.availableInputs?.first(where: {
                    $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
                }) {
                    try? session.setPreferredInput(bluetooth)
                }
            }
        } catch {
            state = .idle
            throw DictationError.audioSessionFailed(error.localizedDescription)
        }
        #endif

        let engine = AVAudioEngine()
        let request = createRecognitionRequest()

        self.audioEngine = engine
        self.recognitionRequest = request
        self.bufferRelay.setRequest(request)

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install audio tap for real-time sample streaming and RMS metering
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            self.bufferRelay.append(buffer)

            // Compute RMS loudness level
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameLength))
            let normalized = min(max(rms * 5.0, 0.0), 1.0) // Scale to [0, 1]

            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }

        // Start initial recognition task
        startRecognitionTask(with: request)

        try engine.start()

        self.startTime = Date()
        self.state = .listening(time: 0)

        // Start duration timer
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime else { return }
                if case .listening = self.state {
                    self.state = .listening(time: Date().timeIntervalSince(start))
                }
            }
        }
    }

    /// Stops recording and returns the final accumulated text.
    public func stop() async -> String {
        guard isRecording else {
            let text = currentText
            currentText = ""
            committedText = ""
            currentHypothesis = ""
            return text
        }
        state = .finishing

        timer?.invalidate()
        timer = nil

        // Commit any remaining in-flight hypothesis
        commitCurrentHypothesis()
        updatePublishedText()

        bufferRelay.endAudio()

        // Wait a short moment for final hypothesis to settle
        try? await Task.sleep(nanoseconds: 100_000_000)

        commitCurrentHypothesis()
        updatePublishedText()

        let finalText = currentText
        teardownSession()
        committedText = ""
        currentHypothesis = ""
        currentText = ""
        lastHypothesisTimestamp = 0.0
        audioLevel = 0.0
        state = .idle

        return finalText
    }

    /// Synchronously and immediately stops recording, commits all in-flight text, tears down the audio session, and returns the final text instantly.
    @discardableResult
    public func stopImmediately() -> String {
        guard isRecording else {
            let text = currentText
            currentText = ""
            committedText = ""
            currentHypothesis = ""
            return text
        }
        state = .finishing

        timer?.invalidate()
        timer = nil

        commitCurrentHypothesis()
        updatePublishedText()

        bufferRelay.endAudio()

        let finalText = currentText
        teardownSession()
        committedText = ""
        currentHypothesis = ""
        currentText = ""
        lastHypothesisTimestamp = 0.0
        audioLevel = 0.0
        state = .idle

        return finalText
    }

    /// Cancels recording and discards the current take.
    public func cancel() {
        timer?.invalidate()
        timer = nil
        teardownSession()
        committedText = ""
        currentHypothesis = ""
        currentText = ""
        lastHypothesisTimestamp = 0.0
        audioLevel = 0.0
        state = .idle
    }

    // MARK: - Recognition Task Management

    private func createRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 13.0, macOS 10.15, *) {
            request.requiresOnDeviceRecognition = true
        }
        if #available(iOS 16.0, macOS 13.0, *) {
            request.addsPunctuation = true
        }
        return request
    }

    private func startRecognitionTask(with request: SFSpeechAudioBufferRecognitionRequest) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        // `.finishing` has to count. stop() ends the audio and then waits a
        // moment for the last hypothesis to settle — and this guard was quietly
        // discarding exactly those results, so the final words of a take were
        // lost and the wait accomplished nothing.
        var accepting = isRecording
        if case .finishing = state { accepting = true }
        guard accepting else { return }

        if let result = result {
            let newHypothesis = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)

            if !newHypothesis.isEmpty {
                // If Apple's recognizer reset bestTranscription after a pause (new utterance started),
                // commit the previous hypothesis so earlier thoughts are NEVER wiped out.
                if shouldCommitPreviousHypothesis(newHypothesis: newHypothesis, result: result) {
                    commitCurrentHypothesis()
                }

                self.currentHypothesis = newHypothesis
                if let lastSeg = result.bestTranscription.segments.last {
                    self.lastHypothesisTimestamp = lastSeg.timestamp + lastSeg.duration
                }
                updatePublishedText()
            }

            if result.isFinal {
                commitCurrentHypothesis()
                updatePublishedText()
                restartRecognitionTaskIfActive()
                return
            }
        }

        if let error = error {
            let nsError = error as NSError
            // Check if error is silence/pause timeout (e.g. kAFAssistantErrorDomain error 1110 / 203)
            if isRecording, case .listening = state {
                // User paused long enough for utterance timeout.
                // Commit whatever was said and seamlessly restart recognition on the still-running audio tap.
                // Deliberately narrow: matching NSCocoaErrorDomain as well meant
                // almost any failure restarted recognition, which can loop.
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    commitCurrentHypothesis()
                    updatePublishedText()
                    restartRecognitionTaskIfActive()
                }
            } else if case .finishing = state {
                // Normal shutdown
            }
        }
    }

    /// Determines whether the incoming transcription result represents a new utterance after a pause.
    public func shouldCommitPreviousHypothesis(newHypothesis: String, result: SFSpeechRecognitionResult) -> Bool {
        guard !currentHypothesis.isEmpty else { return false }
        guard newHypothesis != currentHypothesis else { return false }

        // If newHypothesis directly extends currentHypothesis, it's the same utterance growing
        if newHypothesis.lowercased().hasPrefix(currentHypothesis.lowercased()) {
            return false
        }

        // If currentHypothesis has prefix of newHypothesis, recognizer trimmed a trailing partial word
        if currentHypothesis.lowercased().hasPrefix(newHypothesis.lowercased()) {
            return false
        }

        // Check segment timestamp: if the first word starts after the previous hypothesis completed
        if let firstSeg = result.bestTranscription.segments.first {
            if lastHypothesisTimestamp > 0 && firstSeg.timestamp >= (lastHypothesisTimestamp - 0.2) {
                return true
            }
        }

        // Check word overlap at the beginning: if the first word differs and current hypothesis is substantial
        let oldWords = currentHypothesis.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let newWords = newHypothesis.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        if oldWords.count >= 2 && newWords.count >= 1 {
            let oldFirst = oldWords[0].lowercased().trimmingCharacters(in: .punctuationCharacters)
            let newFirst = newWords[0].lowercased().trimmingCharacters(in: .punctuationCharacters)
            if oldFirst != newFirst {
                return true
            }
        }

        return false
    }

    /// Manually sets hypothesis state for unit testing utterance boundary logic.
    public func setTestHypothesis(current: String, committed: String = "", timestamp: TimeInterval = 0.0) {
        self.currentHypothesis = current
        self.committedText = committed
        self.lastHypothesisTimestamp = timestamp
        updatePublishedText()
    }

    /// Manually sets listening state for unit testing stop and save behaviors.
    public func setTestListeningState(isListening: Bool) {
        self.state = isListening ? .listening(time: 1.0) : .idle
    }

    private func commitCurrentHypothesis() {
        guard !currentHypothesis.isEmpty else { return }
        committedText = combineText(committed: committedText, hypothesis: currentHypothesis)
        currentHypothesis = ""
        lastHypothesisTimestamp = 0.0
    }

    private func updatePublishedText() {
        currentText = combineText(committed: committedText, hypothesis: currentHypothesis)
    }

    /// Seamlessly restarts recognition request on the active audio tap when an utterance finishes or times out on pause.
    private func restartRecognitionTaskIfActive() {
        guard isRecording, case .listening = state else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        bufferRelay.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        let newRequest = createRecognitionRequest()
        self.recognitionRequest = newRequest
        self.lastHypothesisTimestamp = 0.0

        bufferRelay.setRequest(newRequest)
        startRecognitionTask(with: newRequest)
    }

    /// Intelligently joins committed sentences and in-flight hypotheses with correct spacing and sentence capitalization.
    public func combineText(committed: String, hypothesis: String) -> String {
        let trimmedHypothesis = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHypothesis.isEmpty else {
            return committed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let hadTrailingNewline = committed.hasSuffix("\n")
        let trimmedCommitted = committed.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedCommitted.isEmpty else {
            return trimmedHypothesis
        }

        // Auto-capitalize hypothesis if committed ends with sentence-ending punctuation or newline
        var formattedHypothesis = trimmedHypothesis
        if hadTrailingNewline || [".", "!", "?"].contains(trimmedCommitted.last ?? " ") {
            if let firstChar = formattedHypothesis.first, firstChar.isLowercase {
                formattedHypothesis = formattedHypothesis.prefix(1).uppercased() + formattedHypothesis.dropFirst()
            }
        }

        if hadTrailingNewline {
            return "\(trimmedCommitted)\n\(formattedHypothesis)"
        } else {
            return "\(trimmedCommitted) \(formattedHypothesis)"
        }
    }

    private func teardownSession() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
            }
        }
        audioEngine = nil
        bufferRelay.endAudio()
        bufferRelay.setRequest(nil)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        #if os(iOS)
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
