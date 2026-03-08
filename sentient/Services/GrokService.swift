import Foundation

/// Actor-isolated service for streaming responses from xAI Grok API.
/// Using `actor` ensures thread-safe access to mutable state (like the URLSession task).
/// This prevents data races when starting/cancelling requests from different contexts.
actor GrokService {
    
    // MARK: - Configuration
    
    /// xAI API endpoint for chat completions
    private let apiURL = URL(string: "https://api.x.ai/v1/chat/completions")!
    
    /// Reads API key from the Keychain (written by SettingsPageView).
    /// Falls back to an environment variable so development runs work without a saved key.
    private var apiKey: String {
        // KeychainHelper.load returns nil if nothing is stored yet.
        // The `??` chain falls through to the env var, then finally to "".
        KeychainHelper.load(key: "xai_api_key")
            ?? ProcessInfo.processInfo.environment["XAI_API_KEY"]
            ?? ""
    }
    
    /// Check if API key is configured
    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }
    
    /// Model to use. Check https://docs.x.ai for current models.
    private let model = "grok-4-1-fast-reasoning"
    
    /// Track active streaming task for cancellation
    private var activeTask: Task<Void, Never>?
    
    // MARK: - Public API
    
    /// Streams a response from Grok API for the given prompt.
    /// - Parameters:
    ///   - prompt: The user's transcribed speech
    ///   - onToken: Callback fired for each streamed token (runs on MainActor)
    ///   - onComplete: Callback fired when streaming finishes
    ///   - onError: Callback fired if an error occurs
    func streamResponse(
        prompt: String,
        onToken: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        // Cancel any existing request
        activeTask?.cancel()
        
        activeTask = Task {
            do {
                try await performStreamingRequest(
                    prompt: prompt,
                    onToken: onToken,
                    onComplete: onComplete
                )
            } catch {
                if !Task.isCancelled {
                    await onError(error)
                }
            }
        }
    }
    
    /// Cancels any active streaming request
    func cancelRequest() {
        activeTask?.cancel()
        activeTask = nil
    }
    
    // MARK: - Private Implementation
    
    private func performStreamingRequest(
        prompt: String,
        onToken: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) async throws {
        // Check for API key
        guard hasAPIKey else {
            throw GrokError.noAPIKey
        }
        
        // Build request
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Request body with streaming enabled
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful voice assistant. Keep responses concise and conversational."],
                ["role": "user", "content": prompt]
            ],
            "stream": true,  // Enable Server-Sent Events streaming
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Use URLSession's async bytes API for streaming
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to read error body for debugging
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break } // Limit error message size
            }
            Log.error("API Error \(httpResponse.statusCode): \(errorBody)", category: "GrokService")
            throw GrokError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        // Process Server-Sent Events stream
        // Each line is prefixed with "data: " and contains JSON
        for try await line in bytes.lines {
            // Check for cancellation
            if Task.isCancelled { break }
            
            // Skip empty lines
            guard line.hasPrefix("data: ") else { continue }
            
            // Extract JSON payload
            let jsonString = String(line.dropFirst(6)) // Remove "data: " prefix
            
            // "[DONE]" signals end of stream
            if jsonString == "[DONE]" { break }
            
            // Parse the chunk
            if let chunk = parseStreamChunk(jsonString) {
                await onToken(chunk)
            }
        }
        
        await onComplete()
    }
    
    /// Parses a single SSE chunk and extracts the content delta
    private func parseStreamChunk(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }
}

// MARK: - Error Types

enum GrokError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case noAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Grok API"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .noAPIKey:
            return "No API key configured. Add your key in Settings (⌘,)."
        }
    }
}
