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
            DexHeader(title: "Capture", subtitle: "one photo • on device")

            ScrollView {
                VStack(spacing: 18) {
                    captureScreen

                    if image == nil {
                        sourceButtons
                    } else {
                        actionButtons
                    }

                    Label(
                        "NO UPLOAD • CORE ML • ON-DEVICE 3D",
                        systemImage: "iphone.gen3.radiowaves.left.and.right"
                    )
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
                    Text("One clear photo. Fill most of the frame.")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(.black.opacity(0.76))
            }

            if isGenerating {
                ZStack {
                    Color.black.opacity(0.76)
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text(phase)
                            .font(.system(.headline, design: .monospaced, weight: .black))
                            .foregroundStyle(.white)
                        Text("RUNNING ON THIS IPHONE")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.white.opacity(0.65))
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
                Label("REGISTER IN 3D", systemImage: "cube.transparent.fill")
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
            phase = "PREPARING SUBJECT"
            var entryID: UUID?

            do {
                let jpeg = try CaptureImageProcessor.jpegData(from: image)
                let entry = try store.createEntry(from: jpeg)
                entryID = entry.id

                phase = "GENERATING 3D"
                let result = try await OnDeviceTripoSREngine.shared.generate(
                    jpegData: jpeg
                )

                phase = "REGISTERING"
                try store.completeOnDevice(
                    entry.id,
                    previewData: result.previewPNG,
                    usdzData: result.usdz,
                    vertexCount: result.vertexCount,
                    triangleCount: result.triangleCount,
                    resolution: result.resolution
                )

                phase = "REGISTERED"
                generatedEntryID = entry.id
                selectedTab = .dex
                self.image = nil
                photoItem = nil
            } catch {
                if let entryID {
                    store.fail(entryID, message: error.localizedDescription)
                }
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



@MainActor
private enum CaptureImageProcessor {
    static func jpegData(from image: UIImage) throws -> Data {
        let maxDimension: CGFloat = 2_048
        let width = image.size.width
        let height = image.size.height
        let largest = max(width, height)
        let scale = largest > maxDimension ? maxDimension / largest : 1
        let target = CGSize(width: width * scale, height: height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        guard let data = normalized.jpegData(compressionQuality: 0.92) else {
            throw OnDevice3DError.invalidImage
        }
        return data
    }
}
