import SwiftUI

struct GenerationSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var memoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    var body: some View {
        Form {
            Section("On-device 3D engine") {
                LabeledContent("Model", value: "TripoSR Core ML")
                LabeledContent("Inference", value: "This iPhone")
                LabeledContent("Network", value: "Not used")
                LabeledContent(
                    "Mesh grid",
                    value: "\(OnDeviceTripoSREngine.recommendedResolution)³"
                )
                LabeledContent(
                    "Device memory",
                    value: String(format: "%.1f GB", memoryGB)
                )
            }

            Section("Pipeline") {
                Label("Vision foreground isolation", systemImage: "person.crop.rectangle")
                Label("Core ML triplane encoder", systemImage: "brain.head.profile")
                Label("Local NeRF field queries", systemImage: "cube.transparent")
                Label("Local marching cubes + USDZ", systemImage: "shippingbox.fill")
            }

            Section {
                Text("A selected photo never needs to leave the device for 3D generation. The neural-network weights ship with the app build.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                NavigationLink("Privacy") {
                    PrivacyPolicyView()
                }
            }
        }
        .navigationTitle("System")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
