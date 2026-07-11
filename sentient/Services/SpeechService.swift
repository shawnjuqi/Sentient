import Foundation
import WhisperKit
import AVFoundation

// MARK: - Speech Service Errors

/// Errors that can occur during speech recognition.
///
/// **Design Note:**
/// We use a dedicated error enum instead of generic errors because:
/// 1. Callers can handle specific cases (e.g., show "Open Settings" for permission errors)
/// 2. Error messages are centralized here, not scattered in catch blocks
/// 3. Errors are self-documenting
enum SpeechServiceError: LocalizedError {
    case modelNotLoaded
    case microphonePermissionDenied
    case microphonePermissionNotDetermined
    case audioEngineFailure(underlying: Error)
    case transcriptionFailed(underlying: Error)
    case noAudioRecorded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Speech recognition model not loaded"
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .microphonePermissionNotDetermined:
            return "Microphone permission not yet requested"
        case .audioEngineFailure(let error):
            return "Audio engine error: \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "Transcription error: \(error.localizedDescription)"
        case .noAudioRecorded:
            return "No audio was recorded"
        }
    }
}

// MARK: - Audio Processor

/// Handles raw audio processing on a background thread to avoid blocking the Main Actor.
///
/// **Thread Safety Pattern:**
/// Audio callbacks run on a realtime audio thread, not the main thread.
/// We use NSLock to protect shared state (the audio buffer).
///
/// **@unchecked Sendable:**
/// We mark this as Sendable (can be passed between threads) but "unchecked"
/// because Swift can't verify our manual locking is correct.
/// We're promising the compiler: "trust me, I handle thread safety manually."
final class AudioProcessor: @unchecked Sendable {

    // MARK: - Private State (All protected by lock)

    private var audioBuffer: [Float] = []
    private var converter: AVAudioConverter?
    private let lock = NSLock()

    /// Whether to accumulate incoming audio samples.
    /// The engine runs continuously; this gates actual recording sessions.
    private var isCapturing = false

    /// Thread-safe read of whether samples are currently being accumulated.
    var isActivelyCapturing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCapturing
    }

    /// Target format: 16kHz mono Float32 (WhisperKit's expected input)
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Capture Control

    /// Clears the buffer and begins accumulating audio samples.
    func startCapturing() {
        lock.lock()
        defer { lock.unlock() }
        audioBuffer.removeAll(keepingCapacity: true)
        converter?.reset()
        isCapturing = true
    }

    /// Stops accumulating audio samples. Buffer is preserved for retrieval.
    func stopCapturing() {
        lock.lock()
        defer { lock.unlock() }
        isCapturing = false
    }

    // MARK: - Public API

    /// Processes an audio buffer from the microphone tap.
    /// Converts to 16kHz and appends to internal buffer — only while capturing.
    ///
    /// **Called from audio thread** - must be thread-safe.
    /// Holds the lock for the full conversion so `clear`/`startCapturing` cannot
    /// reset the converter mid-convert.
    func process(buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard isCapturing else { return }

        let inputFormat = buffer.format

        if converter == nil {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            if converter == nil {
                Log.error("Failed to create audio converter", category: "AudioProcessor")
                return
            }
        }

        let conv = converter!

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = UInt32(ceil(Double(buffer.frameLength) * ratio))

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            Log.error("Failed to create output buffer", category: "AudioProcessor")
            return
        }

        var inputConsumed = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let status = conv.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if status == .error {
            Log.error("Conversion error: \(error?.localizedDescription ?? "unknown")", category: "AudioProcessor")
            return
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
        audioBuffer.append(contentsOf: samples)
    }

    /// Returns accumulated audio samples and clears the buffer.
    func retrieveAndClearAudio() -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let data = audioBuffer
        audioBuffer.removeAll(keepingCapacity: true)
        converter?.reset()

        return data
    }

    /// Clears buffer and resets converter without returning data.
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        audioBuffer.removeAll(keepingCapacity: true)
        converter?.reset()
        converter = nil
        isCapturing = false
    }
}

// MARK: - Speech Service

/// Service for speech-to-text using WhisperKit.
///
/// ## Single Responsibility:
/// This service ONLY handles:
/// - Loading the WhisperKit model
/// - Capturing audio from the microphone
/// - Transcribing audio to text
///
/// It does NOT handle:
/// - UI state management (that's OverlayViewModel's job)
/// - AI responses (that's GrokService's job)
/// - Presenting errors to users (that's the View's job)
///
/// ## Why @MainActor?
/// AVAudioEngine and some WhisperKit operations need to run on the main thread.
/// Rather than sprinkling DispatchQueue.main everywhere, we isolate the whole class.
///
/// ## Engine Lifetime Strategy:
/// The AVAudioEngine is started once and kept running for the app's lifetime.
/// Recording sessions are gated by a capture flag in AudioProcessor, not by
/// stop/start cycles. This avoids HAL I/O thread conflicts (error 35) that occur
/// when repeatedly tearing down and restarting the audio engine.
@MainActor
class SpeechService {

    // MARK: - Properties

    /// WhisperKit speech recognition pipeline
    private var whisperPipe: WhisperKit?

    /// Audio engine for capturing microphone input — single instance, stays running
    private let audioEngine = AVAudioEngine()

    /// Thread-safe audio processor
    private let audioProcessor = AudioProcessor()

    /// Whether the audio engine tap has been installed and the engine is running
    private var isEngineStarted = false

    /// Whether the model has been loaded successfully
    var isModelLoaded: Bool {
        whisperPipe != nil
    }

    // MARK: - Initialization

    init() {
        // Observe hardware configuration changes (e.g. audio device switch).
        // When this fires, the existing tap is invalidated and must be reinstalled.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleEngineConfigChange()
            }
        }
    }

    // MARK: - Model Loading

    /// Loads the WhisperKit model.
    /// Audio engine is started on demand when recording begins so the mic
    /// is not held open for the entire app lifetime.
    func loadModel() async throws {
        Log.debug("Loading WhisperKit model...", category: "SpeechService")
        whisperPipe = try await WhisperKit(model: "distil-large-v3")
        Log.debug("WhisperKit model loaded successfully", category: "SpeechService")
    }

    // MARK: - Microphone Permission

    /// Requests microphone permission asynchronously.
    /// - Parameter completion: Called with the result (granted or denied)
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    // MARK: - Recording

    /// Starts recording audio from the microphone.
    /// - Throws: `SpeechServiceError` if permission denied or engine fails
    func startRecording() throws {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break // Continue below
        case .notDetermined:
            throw SpeechServiceError.microphonePermissionNotDetermined
        case .denied, .restricted:
            throw SpeechServiceError.microphonePermissionDenied
        @unknown default:
            throw SpeechServiceError.microphonePermissionDenied
        }

        // Ensure the engine is running (no-op if already started)
        try startEngineIfNeeded()

        // Begin accumulating audio in the processor
        audioProcessor.startCapturing()
    }

    /// Stops recording and preserves audio for transcription.
    /// Tears down the audio engine so the microphone is released when idle.
    func stopRecording() {
        audioProcessor.stopCapturing()
        stopEngineIfNeeded()
    }

    /// Clears any recorded audio without transcribing and releases the mic.
    func clearAudio() {
        audioProcessor.clear()
        stopEngineIfNeeded()
    }

    // MARK: - Transcription

    /// Transcribes the recorded audio and returns the text.
    /// - Returns: The transcribed text
    /// - Throws: `SpeechServiceError` if transcription fails
    func transcribe() async throws -> String {
        guard let pipe = whisperPipe else {
            throw SpeechServiceError.modelNotLoaded
        }

        // Retrieve audio from processor
        let audioSamples = audioProcessor.retrieveAndClearAudio()

        guard !audioSamples.isEmpty else {
            throw SpeechServiceError.noAudioRecorded
        }

        // Debug stats
        let durationSeconds = Double(audioSamples.count) / 16000.0
        Log.debug("Transcribing \(audioSamples.count) samples (\(String(format: "%.1f", durationSeconds))s)", category: "SpeechService")

        do {
            let results = try await pipe.transcribe(audioArray: audioSamples)

            // results.first is optional (array might be empty)
            // but .text is a non-optional String
            if let result = results.first {
                let text = result.text.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    return text
                }
            }
            return ""
        } catch {
            throw SpeechServiceError.transcriptionFailed(underlying: error)
        }
    }

    // MARK: - Private Helpers

    /// Starts the audio engine and installs the tap, if not already running.
    /// Safe to call multiple times — subsequent calls are no-ops.
    private func startEngineIfNeeded() throws {
        guard !isEngineStarted else { return }

        let inputNode = audioEngine.inputNode

        // Get hardware's native format
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        Log.debug("Hardware format: \(hardwareFormat.sampleRate) Hz, \(hardwareFormat.channelCount) ch", category: "SpeechService")

        // Capture local reference to processor to avoid capturing 'self'
        let processor = self.audioProcessor

        // Install tap - closure captures only 'processor', not 'self'
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            processor.process(buffer: buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isEngineStarted = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw SpeechServiceError.audioEngineFailure(underlying: error)
        }
    }

    /// Stops the audio engine and removes the input tap, releasing the microphone.
    private func stopEngineIfNeeded() {
        guard isEngineStarted else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        isEngineStarted = false
    }

    /// Called when the audio hardware configuration changes (e.g. device switch or
    /// bluetooth audio devices transitioning from A2DP to HFP when the mic activates).
    /// Must fully stop the engine before reinstalling the tap, otherwise the old
    /// HAL I/O thread remains and the next start fails with error 35.
    private func handleEngineConfigChange() {
        Log.debug("Audio engine configuration changed, reinstalling tap...", category: "SpeechService")
        stopEngineIfNeeded()
        // Only restart if we were actively capturing; otherwise stay idle.
        guard audioProcessor.isActivelyCapturing else { return }
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            try? startEngineIfNeeded()
            audioProcessor.startCapturing()
        }
    }
}
