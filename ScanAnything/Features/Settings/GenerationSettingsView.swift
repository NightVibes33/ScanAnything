import SwiftUI

struct GenerationSettingsView: View {
    @AppStorage("generationEndpoint") private var generationEndpoint = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Your 3D Engine") {
                TextField(
                    "http://YOUR-PC:8787/generate",
                    text: $generationEndpoint,
                    axis: .vertical
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                Text("This build uses your own free TripoSR server. No paid generation API or provider key is required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("PC setup") {
                Text("Run server/setup-windows.ps1 once, then server/start-windows.ps1. Use your PC LAN or Tailscale address above.")
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
