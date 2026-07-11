import Foundation

/// Actor-isolated service for streaming responses from xAI Grok API.
/// Using `actor` ensures thread-safe access to mutable state (like the URLSession task).
actor GrokService {
    
    // MARK: - Configuration
    
    private let apiURL = URL(string: "https://api.x.ai/v1/chat/completions")!
    
    /// Dedicated session with TLS 1.2+ and SPKI pinning for api.x.ai.
    private let urlSession: URLSession = GrokURLSessionFactory.makeSession()
    
    private var apiKey: String {
        KeychainHelper.load(key: "xai_api_key")
            ?? ProcessInfo.processInfo.environment["XAI_API_KEY"]
            ?? ""
    }
    
    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }
    
    private let model = "grok-4-1-fast-reasoning"
    
    private var activeTask: Task<Void, Never>?
    
    // MARK: - Public API
    
    func streamResponse(
        prompt: String,
        onToken: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
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
        guard hasAPIKey else {
            throw GrokError.noAPIKey
        }
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful voice assistant. Keep responses concise and conversational."],
                ["role": "user", "content": prompt]
            ],
            "stream": true,
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await urlSession.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            Log.error("API Error \(httpResponse.statusCode): \(errorBody)", category: "GrokService")
            throw GrokError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            
            guard line.hasPrefix("data: ") else { continue }
            
            let jsonString = String(line.dropFirst(6))
            
            if jsonString == "[DONE]" { break }
            
            if let chunk = parseStreamChunk(jsonString) {
                await onToken(chunk)
            }
        }
        
        await onComplete()
    }
    
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
    
    /// Maps status codes to safe user-facing copy (raw API bodies stay in logs only).
    static func userFacingMessage(forStatusCode code: Int) -> String {
        switch code {
        case 401, 403:
            return "API key rejected. Check your key in Settings."
        case 429:
            return "Rate limited by xAI. Try again in a moment."
        case 500...599:
            return "Grok service is temporarily unavailable."
        default:
            return "Request failed (HTTP \(code)). Please try again."
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Grok API"
        case .httpError(let code, _):
            return Self.userFacingMessage(forStatusCode: code)
        case .noAPIKey:
            return "No API key configured. Add your key in Settings (⌘,)."
        }
    }
}
