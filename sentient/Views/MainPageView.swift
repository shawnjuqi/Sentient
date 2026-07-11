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
            headerView

            Divider()
                .background(Color.white.opacity(0.2))

            if !hasAPIKey {
                apiKeyWarning
            }
            
            if let error = viewModel.errorMessage {
                errorBanner(message: error)
            }
            
            transcriptSection
            
            if viewModel.hasPendingSend {
                pendingSendBanner
            }
            
            responseSection
            
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
            
            statusBadge
            
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
    
    private var statusColor: Color {
        if viewModel.isModelLoading {
            return .orange
        } else if viewModel.isRecording {
            return .red
        } else if viewModel.isProcessingAI {
            return .blue
        } else if viewModel.hasPendingSend {
            return .orange
        } else {
            return .green
        }
    }
    
    private var statusText: String {
        if viewModel.isModelLoading {
            return "Loading Model..."
        } else if viewModel.isRecording {
            return "Listening..."
        } else if viewModel.isProcessingAI {
            return "Thinking..."
        } else if viewModel.hasPendingSend {
            return "Ready to Send"
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
            
            if viewModel.microphonePermissionDenied {
                Button("Open Settings") {
                    openMicrophonePrivacySettings()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
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
    
    private func openMicrophonePrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Transcript Section
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your Voice", systemImage: "mic.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(viewModel.transcript.isEmpty ? "Press Record or Option+R to speak..." : viewModel.transcript)
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
    
    // MARK: - Pending Send
    
    private var pendingSendBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundColor(.accentColor)
            Text("Send this transcript to xAI Grok?")
                .font(.caption)
            Spacer()
            Button("Discard") {
                viewModel.discardPendingSend()
            }
            .font(.caption)
            .buttonStyle(.borderless)
            Button("Send") {
                viewModel.sendPendingToGrok()
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.12))
        )
    }
    
    // MARK: - Response Section
    
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
            .disabled(viewModel.isModelLoading || viewModel.isProcessingAI)
            
            Button(action: {
                viewModel.clearAll()
            }) {
                Image(systemName: "trash")
                    .font(.title2)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.transcript.isEmpty && viewModel.aiResponse.isEmpty && !viewModel.hasPendingSend)
        }
    }
}

// MARK: - Preview

#Preview {
    MainPageView(viewModel: OverlayViewModel())
        .frame(width: 500)
        .background(Color.gray.opacity(0.2))
}
