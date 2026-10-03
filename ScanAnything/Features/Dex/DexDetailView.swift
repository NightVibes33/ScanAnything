import QuickLook
import SwiftUI
import WebKit

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

                            Text("Generated from a single source photo.")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
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
                colors: [.dexRed, .dexRedDark, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let glb = store.glbURL(for: entry), entry.status == .ready {
                LocalGLBView(url: glb)
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
        DexPanel {
            VStack(spacing: 12) {
                if let usdz = store.usdzURL(for: entry) {
                    Button {
                        quickLookTarget = QuickLookTarget(url: usdz)
                    } label: {
                        Label("OPEN IN 3D / AR", systemImage: "arkit")
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.dexRed)

                    ShareLink(item: usdz) {
                        Label("EXPORT USDZ", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let glb = store.glbURL(for: entry) {
                    ShareLink(item: glb) {
                        Label("EXPORT GLB", systemImage: "cube")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.system(.headline, design: .monospaced, weight: .black))
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

private struct LocalGLBView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        load(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func load(_ modelURL: URL, in webView: WKWebView) {
        let directory = modelURL.deletingLastPathComponent()
        let htmlURL = directory.appending(path: "viewer.html")
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
          <style>
            html,body { margin:0; width:100%; height:100%; background:transparent; overflow:hidden; }
            model-viewer { width:100%; height:100%; background:transparent; }
          </style>
          <script type="module" src="https://cdn.jsdelivr.net/npm/@google/model-viewer/dist/model-viewer.min.js"></script>
        </head>
        <body>
          <model-viewer src="(modelURL.lastPathComponent)" camera-controls auto-rotate shadow-intensity="1" interaction-prompt="none"></model-viewer>
        </body>
        </html>
        """

        do {
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(htmlURL, allowingReadAccessTo: directory)
        } catch {
            webView.loadHTMLString("<html><body style='background:black'></body></html>", baseURL: nil)
        }
    }
}
