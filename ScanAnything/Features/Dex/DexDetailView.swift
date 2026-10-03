import QuickLook
import SceneKit
import SwiftUI

private struct QuickLookTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct DexDetailView: View {
    @Environment(DexStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let entryID: UUID

    @State private var quickLookTarget: QuickLookTarget?
    @State private var renameShown = false
    @State private var newName = ""

    var body: some View {
        Group {
            if let entry = store.entry(id: entryID) {
                content(entry)
            } else {
                ContentUnavailableView("Entry missing", systemImage: "questionmark.square")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $quickLookTarget) { target in
            QuickLookModelView(url: target.url)
                .ignoresSafeArea()
        }
        .alert("RENAME ENTRY", isPresented: $renameShown) {
            TextField("Name", text: $newName)
            Button("SAVE") {
                store.rename(entryID, to: newName)
            }
            Button("CANCEL", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func content(_ entry: DexEntry) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(entry)

                VStack(spacing: 14) {
                    DexPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(entry.dexNumber)
                                Spacer()
                                Text(entry.status == .ready ? "REGISTERED" : entry.status.rawValue.uppercased())
                            }
                            .font(.system(.caption, design: .monospaced, weight: .black))
                            .foregroundStyle(.secondary)

                            Text(entry.name.uppercased())
                                .font(.system(.title, design: .monospaced, weight: .black))

                            Text("Generated entirely on this device from one photo.")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if let triangles = entry.triangleCount,
                               let resolution = entry.generationResolution {
                                HStack {
                                    Text("\(triangles.formatted()) TRIANGLES")
                                    Spacer()
                                    Text("\(resolution)³ FIELD")
                                }
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if entry.status == .ready {
                        modelActions(entry)
                    } else if let message = entry.statusMessage {
                        DexPanel {
                            Label(message.uppercased(), systemImage: "clock")
                                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(.black)
        .navigationTitle(entry.dexNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    newName = entry.name
                    renameShown = true
                } label: {
                    Image(systemName: "pencil")
                }

                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.delete(entryID)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func hero(_ entry: DexEntry) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.dexRed, Color.dexRedDark, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let usdz = store.usdzURL(for: entry), entry.status == .ready {
                LocalUSDZSceneView(url: usdz)
                    .frame(height: 410)
            } else if let image = store.image(for: entry) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(28)
            }
        }
        .frame(height: 430)
    }

    @ViewBuilder
    private func modelActions(_ entry: DexEntry) -> some View {
        if let usdz = store.usdzURL(for: entry) {
            DexPanel {
                VStack(spacing: 12) {
                    Button {
                        quickLookTarget = QuickLookTarget(url: usdz)
                    } label: {
                        Label("OPEN IN 3D / AR", systemImage: "arkit")
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dexRed)

                    ShareLink(item: usdz) {
                        Label("EXPORT USDZ", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.system(.headline, design: .monospaced, weight: .black))
            }
        }
    }
}

private struct QuickLookModelView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: QLPreviewController,
        context: Context
    ) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

private struct LocalUSDZSceneView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.scene = try? SCNScene(url: url, options: nil)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene == nil {
            view.scene = try? SCNScene(url: url, options: nil)
        }
    }
}
