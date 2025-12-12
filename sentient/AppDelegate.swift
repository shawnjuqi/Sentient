import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // Menu Bar Icon
    var statusItem: NSStatusItem?

    // Menu Bar Popup
    var popover: NSPopover?

    // Set activation policy before app finishes launching
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 1. Start as Prohibited (no dock, no focus)
        NSApp.setActivationPolicy(.prohibited)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 2. Switch to Accessory (no dock, but can show windows/popovers)
        NSApp.setActivationPolicy(.accessory)

        // Setup the menu bar icon and popover functionality
        setupMenuBar()
    }

    func setupMenuBar() {
        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Get the button of the menu bar icon
        if let button = statusItem?.button {
            // Set the image of the menu bar icon
            button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Sentient")

            // Allow system to color icon based on dark/light mode
            button.image?.isTemplate = true

            // Add click handler to the menu bar icon
            button.action = #selector(handleButtonClick(_:))

            // Set the target of the click handler
            button.target = self

            // Enable right-click detection
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        // Initialize and configure popover
        setupPopover()
    }

    func setupPopover() {
        // Create popover with NSPopover
        popover = NSPopover()

        // Set popover size
        popover?.contentSize = NSSize(width: 300, height: 400)

        // Set popover behavior to close when click outside
        popover?.behavior = .transient

        // Create SwiftUI View, provide Core Data context to view hierarchy
        let contentView = PopoverView()
            .environment(\.managedObjectContext, 
                PersistenceController.shared.container.viewContext)
        
        // Creates an NSView to render the SwiftUI view (bridging) (fixes typing difference)
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    func showContextMenu() {
        // Create menu
        let menu = NSMenu()
        
        // Add menu item
        let quitMenuItem = NSMenuItem(
            title: "Quit Sentient",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        
        // Show menu at icon, centered horizontally below
        if let button = statusItem?.button {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
                in: button
            )
        }
    }

    // Handle both left and right clicks
    @objc func handleButtonClick(_ sender: NSButton) {
        // Safely unwrap the current event
        guard let event = NSApp.currentEvent else {
            return
        }
        
        // Right-click: show menu
        if (event.type == .rightMouseDown || event.type == .rightMouseUp) {
            showContextMenu()
        } else {
            // Left-click: toggle popover
            togglePopover(sender)
        }
    }

    // Called when menu bar icon is clicked
    // @objc require for #selector to function
    // sender is the object that triggered the action (button)
    @objc func togglePopover(_ sender: Any?) {
        // Safely unwrap optional button (must exit if else)
        guard let button = statusItem?.button else { return }

        // Safely unwrap popover element
        if let popover = popover {
            if (popover.isShown) {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Make popover key window to recieve keyboard input
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    // Called through popover or right-click context menu
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
