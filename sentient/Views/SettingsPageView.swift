import SwiftUI
import KeyboardShortcuts
import AppKit

// MARK: - Settings Page

/// Settings page for API key configuration and keyboard shortcuts.
struct SettingsPageView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    /// Draft API key edited in the text field. Persisted only via Save / Clear.
    @State private var apiKey: String = ""
    
    /// Last value known to be stored in Keychain (drives the configured badge).
    @State private var storedAPIKey: String = ""
    
    @State private var showAPIKey: Bool = false
    @State private var saveMessage: String?
    @State private var saveFailed: Bool = false
    
    private var hasUnsavedChanges: Bool {
        apiKey != storedAPIKey
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            apiKeySection
            
            shortcutsSection
            
            Spacer()
            
            footerView
        }
        .padding(20)
        .onAppear {
            if let legacy = UserDefaults.standard.string(forKey: "xai_api_key"), !legacy.isEmpty {
                if KeychainHelper.save(legacy, key: "xai_api_key") {
                    UserDefaults.standard.removeObject(forKey: "xai_api_key")
                }
            }
            let loaded = KeychainHelper.load(key: "xai_api_key") ?? ""
            apiKey = loaded
            storedAPIKey = loaded
            saveMessage = nil
            saveFailed = false
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button(action: { viewModel.showMain() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            Text("Settings")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .opacity(0)
        }
    }
    
    // MARK: - API Key Section
    
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("xAI API Key")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Group {
                    if showAPIKey {
                        TextField("Enter your API key...", text: $apiKey)
                    } else {
                        SecureField("Enter your API key...", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveAPIKey() }
                
                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help(showAPIKey ? "Hide" : "Show")
            }
            
            HStack {
                Button("Save") { saveAPIKey() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!hasUnsavedChanges)
                
                if !storedAPIKey.isEmpty {
                    Button("Clear") { clearAPIKey() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                
                Spacer()
                
                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundColor(saveFailed ? .red : .secondary)
                } else if !storedAPIKey.isEmpty {
                    Label("API key configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("Get your key from")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Link("console.x.ai", destination: URL(string: "https://console.x.ai")!)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed
        
        if trimmed.isEmpty {
            clearAPIKey()
            return
        }
        
        if KeychainHelper.save(trimmed, key: "xai_api_key") {
            storedAPIKey = trimmed
            saveFailed = false
            saveMessage = "Saved to Keychain"
        } else {
            saveFailed = true
            saveMessage = "Could not save to Keychain"
        }
    }
    
    private func clearAPIKey() {
        if KeychainHelper.delete(key: "xai_api_key") {
            apiKey = ""
            storedAPIKey = ""
            saveFailed = false
            saveMessage = "API key removed"
        } else {
            saveFailed = true
            saveMessage = "Could not remove Keychain item"
        }
    }
    
    // MARK: - Shortcuts Section
    
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(spacing: 10) {
                HStack {
                    Text("Toggle Overlay")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    KeyboardShortcuts.Recorder(for: .toggleOverlay)
                        .controlSize(.small)
                }
                
                HStack {
                    Text("Start/Stop Recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    KeyboardShortcuts.Recorder(for: .toggleRecording)
                        .controlSize(.small)
                }
            }
            
            Text("Click a recorder and press your desired key combination")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Text("Sentient v\(Bundle.main.appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsPageView(viewModel: OverlayViewModel())
        .frame(width: 500, height: 380)
        .background(Color.gray.opacity(0.2))
}
