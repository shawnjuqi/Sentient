import SwiftUI

struct PopoverView: View {
    var body: some View {
        VStack() {
            // Main Content
            Text("Main Content")

            // Takes up all available space
            Spacer()

            // Quit Button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

#Preview {
    PopoverView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}