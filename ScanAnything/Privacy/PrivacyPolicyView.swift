import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Camera and photos") {
                Text("ScanAnything only receives the photo you explicitly capture or select for a Dex entry.")
            }

            Section("On-device generation") {
                Text("Foreground isolation, neural 3D inference, mesh extraction, preview generation, and USDZ export run on the device. The selected image is not uploaded to a 3D generation server.")
            }

            Section("Local library") {
                Text("Source photos, generated previews, and 3D models are stored in the app's local Documents container until you delete the entry or the app.")
            }

            Section("Export") {
                Text("A model leaves the app only when you explicitly use an iOS share or export action.")
            }
        }
        .navigationTitle("Privacy")
    }
}
