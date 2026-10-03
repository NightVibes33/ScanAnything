import Foundation
import UIKit

enum Generative3DError: LocalizedError {
    case endpointMissing
    case invalidImage
    case invalidResponse
    case backend(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .endpointMissing:
            "The 3D engine is not configured."
        case .invalidImage:
            "The selected image could not be prepared."
        case .invalidResponse:
            "The 3D engine returned an invalid response."
        case .backend(let message):
            message
        case .timedOut:
            "3D generation timed out."
        }
    }
}

struct Generative3DResult: Sendable {
    let thumbnailURL: URL?
    let glbURL: URL
    let usdzURL: URL?
}

actor Generative3DService {
    private struct SubmitBody: Encodable {
        let imageDataURI: String
    }

    private struct SubmitResponse: Decodable {
        let id: String
    }

    private struct StatusResponse: Decodable {
        let status: String
        let thumbnailURL: URL?
        let glbURL: URL?
        let usdzURL: URL?
        let error: String?
    }

    private let session: URLSession
    private let endpoint: URL

    init(session: URLSession = .shared) throws {
        self.session = session

        let override = UserDefaults.standard.string(forKey: "generationEndpoint")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let bundled = Bundle.main.object(
            forInfoDictionaryKey: "SCANANYTHING_API_BASE_URL"
        ) as? String

        guard let raw = [override, bundled]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty }),
              let url = URL(string: raw)
        else {
            throw Generative3DError.endpointMissing
        }

        endpoint = url
    }

    func generate(jpegData: Data) async throws -> Generative3DResult {
        let id = try await submit(jpegData: jpegData)
        return try await waitForResult(id: id)
    }

    func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw Generative3DError.invalidResponse
        }
        return data
    }

    private func submit(jpegData: Data) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let dataURI = "data:image/jpeg;base64," + jpegData.base64EncodedString()
        request.httpBody = try JSONEncoder().encode(
            SubmitBody(imageDataURI: dataURI)
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(SubmitResponse.self, from: data).id
    }

    private func waitForResult(id: String) async throws -> Generative3DResult {
        let deadline = ContinuousClock.now + .seconds(720)

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()

            var components = URLComponents(
                url: endpoint,
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "id", value: id)]
            guard let statusURL = components?.url else {
                throw Generative3DError.invalidResponse
            }

            var request = URLRequest(url: statusURL)
            request.timeoutInterval = 30
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)

            let payload = try JSONDecoder().decode(StatusResponse.self, from: data)
            switch payload.status.lowercased() {
            case "completed", "ready":
                guard let glb = payload.glbURL else {
                    throw Generative3DError.invalidResponse
                }
                return Generative3DResult(
                    thumbnailURL: payload.thumbnailURL,
                    glbURL: glb,
                    usdzURL: payload.usdzURL
                )
            case "failed", "error":
                throw Generative3DError.backend(
                    payload.error ?? "3D generation failed."
                )
            default:
                try await Task.sleep(for: .seconds(2))
            }
        }

        throw Generative3DError.timedOut
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw Generative3DError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? String {
                throw Generative3DError.backend(error)
            }
            throw Generative3DError.invalidResponse
        }
    }
}

@MainActor
enum CaptureImageProcessor {
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

        for quality in stride(from: 0.90, through: 0.55, by: -0.07) {
            if let data = normalized.jpegData(compressionQuality: quality),
               data.count <= 2_800_000 {
                return data
            }
        }

        guard let data = normalized.jpegData(compressionQuality: 0.5) else {
            throw Generative3DError.invalidImage
        }
        return data
    }
}
