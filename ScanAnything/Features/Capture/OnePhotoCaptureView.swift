import PhotosUI
import SwiftUI
import UIKit

struct OnePhotoCaptureView: View {
    @Environment(DexStore.self) private var store
    @Binding var selectedTab: DexTab

    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var cameraShown = false
    @State private var generatedEntryID: UUID?
    @State private var isGenerating = false
    @State private var phase = "READY"
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            DexHeader(title: "Capture", subtitle: "one photo")

            ScrollView {
                VStack(spacing: 18) {
                    captureScreen

                    if image == nil {
                        sourceButtons
                    } else {
                        actionButtons
                    }

                    Text("ONE PHOTO • ONE 3D ENTRY")
                        .font(.system(.caption, design: .monospaced, weight: .black))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(16)
            }
            .background(.black)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $cameraShown) {
            CameraPicker { captured in
                image = captured
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self),
                      let loaded = UIImage(data: data)
                else { return }
                image = loaded
            }
        }
        .navigationDestination(item: $generatedEntryID) { id in
            DexDetailView(entryID: id)
        }
        .alert(
            "3D GENERATION FAILED",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var captureScreen: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.dexScreen)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.75), lineWidth: 5)
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(8)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 92, weight: .ultraLight))
                    Text("CENTER ONE SUBJECT")
                        .font(.system(.headline, design: .monospaced, weight: .black))
                    Text("Fill most of the frame")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(.black.opacity(0.76))
            }

            if isGenerating {
                ZStack {
                    Color.black.opacity(0.72)
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text(phase)
                            .font(.system(.headline, design: .monospaced, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(8)
            }
        }
        .aspectRatio(0.82, contentMode: .fit)
        .padding(8)
        .background(Color.dexRedDark, in: RoundedRectangle(cornerRadius: 18))
    }

    private var sourceButtons: some View {
        VStack(spacing: 12) {
            Button {
                cameraShown = true
            } label: {
                Label("TAKE PHOTO", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dexRed)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("CHOOSE PHOTO", systemImage: "photo.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .font(.system(.headline, design: .monospaced, weight: .black))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                generate()
            } label: {
                Label("CREATE 3D", systemImage: "cube.transparent.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dexRed)
            .disabled(isGenerating)

            Button("RETAKE") {
                image = nil
                photoItem = nil
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(isGenerating)
        }
        .font(.system(.headline, design: .monospaced, weight: .black))
    }

    private func generate() {
        guard let image else { return }

        Task {
            isGenerating = true
            phase = "PREPARING PHOTO"

            do {
                let jpeg = try CaptureImageProcessor.jpegData(from: image)
                let entry = try store.createEntry(from: jpeg)
                phase = "BUILDING 3D"

                let service = try Generative3DService()
                let result = try await service.generate(jpegData: jpeg)

                phase = "DOWNLOADING MODEL"
                let thumbnailData: Data?
                if let thumbnailURL = result.thumbnailURL {
                    thumbnailData = try await service.download(thumbnailURL)
                } else {
                    thumbnailData = nil
                }

                let glbData = try await service.download(result.glbURL)

                let usdzData: Data?
                if let usdzURL = result.usdzURL {
                    usdzData = try await service.download(usdzURL)
                } else {
                    usdzData = nil
                }

                try store.complete(
                    entry.id,
                    previewData: thumbnailData,
                    glbData: glbData,
                    usdzData: usdzData
                )

                phase = "REGISTERED"
                generatedEntryID = entry.id
                selectedTab = .dex
                self.image = nil
                photoItem = nil
            } catch {
                errorMessage = error.localizedDescription
            }

            isGenerating = false
            phase = "READY"
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void

        init(onImage: @escaping (UIImage) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
