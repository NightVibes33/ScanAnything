import SwiftUI

struct GenerationSettingsView: View {
    @AppStorage("generationEndpoint") private var generationEndpoint = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("3D Engine") {
                TextField(
                    "https://your-domain.com/api/generate",
                    text: $generationEndpoint,
                    axis: .vertical
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                Text("Production builds should point this at the ScanAnything server proxy. The model provider key stays on the server, never in the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                NavigationLink("Privacy") {
                    PrivacyPolicyView()
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
