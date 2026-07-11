import SwiftUI

// MARK: - Page Enum

/// Tracks which page is currently displayed in the overlay
enum OverlayPage {
    case main
    case settings
}

// MARK: - OverlayViewModel

/// ViewModel for the overlay UI.
@MainActor
class OverlayViewModel: ObservableObject {
    
    // MARK: - Published UI State
    
    /// Current transcribed text from speech
    @Published var transcript: String = ""
    
    /// Streaming response from Grok AI
    @Published var aiResponse: String = ""
    
    /// True while WhisperKit model is loading
    @Published var isModelLoading: Bool = true
    
    /// True while actively recording audio
    @Published var isRecording: Bool = false
    
    /// True while waiting for/receiving AI response
    @Published var isProcessingAI: Bool = false
    
    /// True when a transcript is ready and waiting for the user to send it to Grok.
    @Published var hasPendingSend: Bool = false
    
    /// User-facing error message (nil when no error)
    @Published var errorMessage: String?
    
    /// True if microphone permission was denied
    @Published var microphonePermissionDenied: Bool = false
    
    /// Current page in the overlay navigation
    @Published var currentPage: OverlayPage = .main
    
    // MARK: - Dependencies
    
    private let speechService: SpeechService
    private let grokService: GrokService
    
    // MARK: - Initialization
    
    init(speechService: SpeechService, grokService: GrokService) {
        self.speechService = speechService
        self.grokService = grokService
        
        Task {
            await loadSpeechModel()
        }
    }
    
    convenience init() {
        self.init(
            speechService: SpeechService(),
            grokService: GrokService()
        )
    }
    
    // MARK: - Model Loading
    
    private func loadSpeechModel() async {
        do {
            try await speechService.loadModel()
            isModelLoading = false
            Log.debug("Speech model loaded", category: "OverlayViewModel")
        } catch {
            isModelLoading = false
            errorMessage = "Failed to load speech recognition model. Please restart the app."
            Log.error("Failed to load speech model: \(error)", category: "OverlayViewModel")
        }
    }
    
    // MARK: - Public Actions
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Sends the current transcript to Grok after explicit user confirmation.
    func sendPendingToGrok() {
        let prompt = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            errorMessage = "Nothing to send. Record something first."
            return
        }
        hasPendingSend = false
        Task {
            await sendToGrok(prompt: prompt)
        }
    }
    
    /// Discards a pending cloud send without clearing the transcript.
    func discardPendingSend() {
        hasPendingSend = false
    }
    
    func clearAll() {
        transcript = ""
        aiResponse = ""
        errorMessage = nil
        hasPendingSend = false
        speechService.clearAudio()
        Task {
            await grokService.cancelRequest()
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    func showSettings() {
        currentPage = .settings
    }
    
    func showMain() {
        currentPage = .main
    }
    
    // MARK: - Private Recording Logic
    
    private func startRecording() {
        errorMessage = nil
        hasPendingSend = false
        
        guard !isModelLoading else {
            errorMessage = "Please wait, speech model is still loading..."
            return
        }
        
        guard speechService.isModelLoaded else {
            errorMessage = "Speech model not available. Please restart the app."
            return
        }
        
        do {
            try speechService.startRecording()
            isRecording = true
            Log.debug("Recording started", category: "OverlayViewModel")
        } catch SpeechServiceError.microphonePermissionDenied {
            microphonePermissionDenied = true
            errorMessage = "Microphone access denied. Please enable in System Settings."
        } catch SpeechServiceError.microphonePermissionNotDetermined {
            speechService.requestMicrophonePermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startRecording()
                    } else {
                        self?.microphonePermissionDenied = true
                        self?.errorMessage = "Microphone access is required to use voice input."
                    }
                }
            }
        } catch {
            errorMessage = "Unable to access microphone. Please check your audio settings."
            Log.error("Failed to start recording: \(error)", category: "OverlayViewModel")
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        speechService.stopRecording()
        Log.debug("Recording stopped", category: "OverlayViewModel")
        
        Task {
            await transcribeOnly()
        }
    }
    
    // MARK: - Transcription & AI Coordination
    
    /// Transcribes audio and waits for explicit send — does not call the cloud API yet.
    private func transcribeOnly() async {
        do {
            let text = try await speechService.transcribe()
            
            if text.isEmpty {
                errorMessage = "No speech detected. Please try again."
                return
            }
            
            transcript = text
            aiResponse = ""
            hasPendingSend = true
            Log.debug("Transcription ready (\(text.count) chars); waiting for send", category: "OverlayViewModel")
            
        } catch SpeechServiceError.noAudioRecorded {
            errorMessage = "No audio recorded. Try speaking louder or check your microphone."
        } catch {
            errorMessage = "Failed to transcribe speech. Please try again."
            Log.error("Transcription error: \(error)", category: "OverlayViewModel")
        }
    }
    
    private func sendToGrok(prompt: String) async {
        isProcessingAI = true
        aiResponse = ""
        
        Log.debug("Sending to Grok (\(prompt.count) chars)", category: "OverlayViewModel")
        
        await grokService.streamResponse(
            prompt: prompt,
            onToken: { [weak self] token in
                self?.aiResponse += token
            },
            onComplete: { [weak self] in
                self?.isProcessingAI = false
                Log.debug("Grok response complete", category: "OverlayViewModel")
            },
            onError: { [weak self] error in
                self?.isProcessingAI = false
                self?.aiResponse = "Error: \(error.localizedDescription)"
                Log.error("Grok error: \(error)", category: "OverlayViewModel")
            }
        )
    }
}
