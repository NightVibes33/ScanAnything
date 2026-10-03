import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Camera and photos") {
                Text("A photo you choose or capture is used to create the 3D entry you request.")
            }

            Section("3D generation") {
                Text("When you create a 3D entry, the selected photo is sent to the configured ScanAnything generation service and its model provider for processing. The app does not upload other photos from your library.")
            }

            Section("Local library") {
                Text("Source photos, generated previews, and downloaded 3D model files are stored in the app's local Documents container until you delete the entry or the app.")
            }

            Section("Export") {
                Text("Files leave the app only when you request generation or explicitly export/share a model.")
            }
        }
        .navigationTitle("Privacy")
    }
}
