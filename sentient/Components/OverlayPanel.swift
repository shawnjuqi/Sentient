import AppKit

// Custom NSPanel subclass for Spotlight-style floating overlay.
final class OverlayPanel: NSPanel {
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // .borderless: No title bar, close/minimize buttons, or resize handles
            // .nonactivatingPanel: Panel won't cause app to become "active"
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configurePanel()
    }
    
    private func configurePanel() {
        // MARK: - Transparency & Background
        
        // isOpaque = false: Required for any transparency effects
        isOpaque = false
        
        // Clear background so only SwiftUI content is visible
        backgroundColor = .clear
        
        // MARK: - Window Level & Behavior
        
        // .floating: Window stays above normal windows from all apps
        level = .floating
        
        // Stay on the active Space only — avoid mirroring sensitive transcripts
        // onto every virtual desktop. fullScreenAuxiliary keeps Spotlight-like behavior.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        
        // Exclude overlay contents from screenshots and screen sharing when possible.
        sharingType = .none
        
        // MARK: - Focus & Interaction
        
        // Keep visible while using other apps (Spotlight-style); Space isolation
        // and sharingType handle the main shoulder-surf / capture risks.
        hidesOnDeactivate = false
        
        // MARK: - Visual Polish
        
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        
        // Allow dragging by background (no title bar)
        isMovableByWindowBackground = true
        
        // Smooth fade animation when showing/hiding
        animationBehavior = .utilityWindow
    }
    
    // MARK: - Key Window Override
    
    /// Override to allow panel to become key window and receive keyboard events
    override var canBecomeKey: Bool {
        return true
    }
    
    /// Allow panel to become main window if needed
    override var canBecomeMain: Bool {
        return true
    }
}
