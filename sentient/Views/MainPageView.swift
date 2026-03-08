import SwiftUI
import AppKit

// MARK: - Main Page

/// The main voice input and AI response page.
struct MainPageView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    /// Check if API key is configured (view-level concern for display)
    @State private var hasAPIKey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with settings button
            headerView

            Divider()
                .background(Color.white.opacity(0.2))

            // API key warning if not configured
            if !hasAPIKey {
                apiKeyWarning
            }
            
            // Error message if present
            if let error = viewModel.errorMessage {
                errorBanner(message: error)
            }
            
            // Transcribed text section
            transcriptSection
            
            // AI response section
            responseSection
            
            // Recording controls
            controlsSection
        }
        .padding(20)
        .onAppear {
            hasAPIKey = KeychainHelper.load(key: "xai_api_key") != nil
        }
    }

    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text("Sentient")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Status indicator
            statusBadge
            
            // Settings button - calls ViewModel method
            Button(action: { viewModel.showSettings() }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    /// Computed property for status color based on ViewModel state
    private var statusColor: Color {
        if viewModel.isModelLoading {
            return .orange
        } else if viewModel.isRecording {
            return .red
        } else if viewModel.isProcessingAI {
            return .blue
        } else {
            return .green
        }
    }
    
    /// Computed property for status text based on ViewModel state
    private var statusText: String {
        if viewModel.isModelLoading {
            return "Loading Model..."
        } else if viewModel.isRecording {
            return "Listening..."
        } else if viewModel.isProcessingAI {
            return "Thinking..."
        } else {
            return "Ready"
        }
    }
    
    // MARK: - API Key Warning
    
    private var apiKeyWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("API key required.")
                .font(.caption)
            Button("Configure") {
                viewModel.showSettings()
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
        )
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Show "Open Settings" button for microphone permission errors
            if viewModel.microphonePermissionDenied {
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            // Dismiss button - calls ViewModel method
            Button {
                viewModel.clearError()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.15))
        )
    }
    
    // MARK: - Transcript Section
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your Voice", systemImage: "mic.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(viewModel.transcript.isEmpty ? "Press the button or Option+Space to speak..." : viewModel.transcript)
                .font(.body)
                .foregroundColor(viewModel.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }
    
    // MARK: - Response Section
    
    /// Calculate response box height based on content
    private var responseBoxHeight: CGFloat {
        let minHeight: CGFloat = 36
        let maxHeight: CGFloat = 280
        
        let responseText = viewModel.aiResponse
        if responseText.isEmpty {
            return minHeight
        }
        
        let estimatedLines = ceil(Double(responseText.count) / 55.0)
        let calculatedHeight = CGFloat(estimatedLines) * 22
        
        return min(max(calculatedHeight, minHeight), maxHeight)
    }
    
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Grok", systemImage: "sparkles")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView {
                Text(viewModel.aiResponse.isEmpty ? "AI response will appear here..." : viewModel.aiResponse)
                    .font(.body)
                    .foregroundColor(viewModel.aiResponse.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: responseBoxHeight)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
            .animation(.easeInOut(duration: 0.2), value: responseBoxHeight)
        }
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        HStack {
            // Record button - calls ViewModel method
            Button(action: {
                viewModel.toggleRecording()
            }) {
                HStack {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                    Text(viewModel.isRecording ? "Stop" : "Record")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRecording ? .red : .accentColor)
            .disabled(viewModel.isModelLoading)
            
            // Clear button - calls ViewModel method
            Button(action: {
                viewModel.clearAll()
            }) {
                Image(systemName: "trash")
                    .font(.title2)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.transcript.isEmpty && viewModel.aiResponse.isEmpty)
        }
    }
}

// MARK: - Preview

#Preview {
    MainPageView(viewModel: OverlayViewModel())
        .frame(width: 500)
        .background(Color.gray.opacity(0.2))
}
