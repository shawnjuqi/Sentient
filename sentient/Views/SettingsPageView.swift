import SwiftUI
import KeyboardShortcuts
import AppKit

// MARK: - Settings Page

/// Settings page for API key configuration and keyboard shortcuts.
struct SettingsPageView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    /// Holds the API key as local view state.
    /// Populated from Keychain on appear; written back on every change.
    @State private var apiKey: String = ""
    
    /// Controls visibility of the API key (local view state, not in ViewModel)
    /// This is fine because it's purely a UI concern with no business logic.
    @State private var showAPIKey: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with back button
            headerView
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // API Key section
            apiKeySection
            
            // Keyboard shortcuts info
            shortcutsSection
            
            Spacer()
            
            // Footer
            footerView
        }
        .padding(20)
        .onAppear {
            // On first launch after this update, migrate any key already in UserDefaults
            // into the Keychain, then wipe the insecure copy.
            if let legacy = UserDefaults.standard.string(forKey: "xai_api_key"), !legacy.isEmpty {
                KeychainHelper.save(legacy, key: "xai_api_key")       // Secure it
                UserDefaults.standard.removeObject(forKey: "xai_api_key") // Delete plain-text copy
            }
            // Load from Keychain into the local @State var so the text field renders it.
            // Falls back to "" if nothing is stored yet.
            apiKey = KeychainHelper.load(key: "xai_api_key") ?? ""
        }
        .onChange(of: apiKey) { _, newValue in
            // Called every time the user edits the text field.
            if newValue.isEmpty {
                // An empty field means the user cleared their key — remove it entirely
                // so Keychain doesn't store an empty string that looks like a valid key.
                KeychainHelper.delete(key: "xai_api_key")
            } else {
                // Persist the new value immediately; no Save button needed.
                KeychainHelper.save(newValue, key: "xai_api_key")
            }
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
            
            // Invisible spacer for centering
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
                
                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help(showAPIKey ? "Hide" : "Show")
            }
            
            HStack {
                if !apiKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("API key configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Get your key from")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link("console.x.ai", destination: URL(string: "https://console.x.ai")!)
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    // MARK: - Shortcuts Section
    
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(spacing: 10) {
                // Toggle Overlay shortcut
                HStack {
                    Text("Toggle Overlay")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    KeyboardShortcuts.Recorder(for: .toggleOverlay)
                        .controlSize(.small)
                }
                
                // Toggle Recording shortcut
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
