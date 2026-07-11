import AppKit
import SwiftUI
import KeyboardShortcuts

// AppDelegate handles application lifecycle and system integration.
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    // Menu bar status item (icon in menu bar)
    private var statusItem: NSStatusItem?
    
    // Custom floating panel for the overlay
    private var overlayPanel: OverlayPanel?
    
    // The ViewModel that drives the overlay UI.
    // Created once here and passed to all views that need it.
    private var viewModel: OverlayViewModel?
    
    // MARK: - App Lifecycle
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Start as .prohibited: No dock icon, no activation
        NSApp.setActivationPolicy(.prohibited)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Switch to .accessory: No dock icon, but can show windows/panels
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize the ViewModel (this is our "Composition Root")
        // The ViewModel creates its own services internally
        viewModel = OverlayViewModel()
        
        // Initialize components
        setupMenuBar()
        setupOverlayPanel()
        setupKeyboardShortcut()
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        // SF Symbol for menu bar icon
        button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Sentient")
        button.image?.isTemplate = true // Adapts to dark/light mode
        
        button.action = #selector(handleMenuBarClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }
    
    @objc private func handleMenuBarClick(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseDown {
            showContextMenu()
        } else {
            toggleOverlay()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: "Toggle Overlay",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Sentient",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        if let button = statusItem?.button {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
                in: button
            )
        }
    }
    
    // MARK: - Overlay Panel Setup
    
    private func setupOverlayPanel() {
        // Calculate centered position on screen
        guard let screen = NSScreen.main else { return }
        
        let panelWidth: CGFloat = 500
        let panelHeight: CGFloat = 350
        
        // Position panel in upper-center of screen (like Spotlight)
        let xPos = (screen.frame.width - panelWidth) / 2
        let yPos = screen.frame.height * 0.65
        
        let contentRect = NSRect(x: xPos, y: yPos, width: panelWidth, height: panelHeight)
        
        overlayPanel = OverlayPanel(contentRect: contentRect)
        
        // Create SwiftUI view and host it in the panel
        // Here we inject the ViewModel into the View
        if let vm = viewModel {
            let overlayView = OverlayView(viewModel: vm)
            let hostingView = NSHostingView(rootView: overlayView)
            
            // Required for transparent background
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear
            
            overlayPanel?.contentView = hostingView
        }
        
        // Start hidden
        overlayPanel?.orderOut(nil)
    }
    
    // MARK: - Keyboard Shortcuts
    
    private func setupKeyboardShortcut() {
        // Toggle overlay visibility
        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) { [weak self] in
            self?.toggleOverlay()
        }
        
        // Toggle recording — always surface the overlay first so the user can
        // see listening state and cancel. Never record while the panel is hidden.
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.showOverlayIfNeeded()
                self.viewModel?.toggleRecording()
            }
        }
    }
    
    // MARK: - Actions
    
    /// Ensures the overlay is visible before sensitive actions (e.g. recording).
    private func showOverlayIfNeeded() {
        guard let panel = overlayPanel, !panel.isVisible else { return }
        recenterPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.animator().alphaValue = 1
    }
    
    @objc private func toggleOverlay() {
        guard let panel = overlayPanel else { return }
        
        if panel.isVisible {
            // Hide with animation
            panel.animator().alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                panel.orderOut(nil)
                panel.alphaValue = 1 // Reset for next show
            }
        } else {
            showOverlayIfNeeded()
        }
    }
    
    /// Recenters panel on the current main screen
    private func recenterPanel() {
        guard let panel = overlayPanel, let screen = NSScreen.main else { return }
        
        let panelWidth = panel.frame.width
        
        let xPos = (screen.frame.width - panelWidth) / 2 + screen.frame.origin.x
        let yPos = screen.frame.height * 0.65 + screen.frame.origin.y
        
        panel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
