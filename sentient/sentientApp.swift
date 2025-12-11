import SwiftUI

@main
struct sentientApp: App {
    // Bridge AppDelegate to SwiftUI app lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Settings scene, only shows when user goes to App -> Settings
        Settings {
            // Empty for now, add settings later
            EmptyView()
        }
    }
}
