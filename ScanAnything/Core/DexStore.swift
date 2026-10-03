import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class DexStore {
    private(set) var entries: [DexEntry] = []

    private let fileManager = FileManager.default
    private let root: URL
    private let libraryURL: URL

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appending(path: "Dex", directoryHint: .isDirectory)
        libraryURL = root.appending(path: "entries.json", directoryHint: .notDirectory)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    func entry(id: UUID) -> DexEntry? {
        entries.first { $0.id == id }
    }

    func directory(for entry: DexEntry) -> URL {
        root.appending(path: entry.id.uuidString, directoryHint: .isDirectory)
    }

    func sourceImageURL(for entry: DexEntry) -> URL {
        directory(for: entry).appending(path: entry.sourceImageFileName)
    }

    func previewImageURL(for entry: DexEntry) -> URL {
        directory(for: entry).appending(path: entry.previewImageFileName)
    }

    func glbURL(for entry: DexEntry) -> URL? {
        guard let name = entry.glbFileName else { return nil }
        return directory(for: entry).appending(path: name)
    }

    func usdzURL(for entry: DexEntry) -> URL? {
        guard let name = entry.usdzFileName else { return nil }
        return directory(for: entry).appending(path: name)
    }

    func createEntry(from jpegData: Data) throws -> DexEntry {
        let nextNumber = (entries.map(\.number).max() ?? 0) + 1
        let entry = DexEntry(number: nextNumber, name: "Specimen (nextNumber)")
        let folder = directory(for: entry)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try jpegData.write(to: sourceImageURL(for: entry), options: .atomic)
        try jpegData.write(to: previewImageURL(for: entry), options: .atomic)
        entries.insert(entry, at: 0)
        persist()
        return entry
    }

    func markSubmitted(_ id: UUID, generationID: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].generationID = generationID
        entries[index].status = .generating
        entries[index].statusMessage = "Building 3D model"
        persist()
    }

    func complete(
        _ id: UUID,
        previewData: Data?,
        glbData: Data,
        usdzData: Data?
    ) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        let folder = directory(for: entry)

        if let previewData {
            let previewName = "preview.png"
            try previewData.write(
                to: folder.appending(path: previewName),
                options: .atomic
            )
            entries[index].previewImageFileName = previewName
        }

        let glbName = "model.glb"
        try glbData.write(
            to: folder.appending(path: glbName),
            options: .atomic
        )
        entries[index].glbFileName = glbName

        if let usdzData {
            let usdzName = "model.usdz"
            try usdzData.write(
                to: folder.appending(path: usdzName),
                options: .atomic
            )
            entries[index].usdzFileName = usdzName
        }

        entries[index].status = .ready
        entries[index].statusMessage = nil
        persist()
    }

    func fail(_ id: UUID, message: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .failed
        entries[index].statusMessage = message
        persist()
    }

    func rename(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = entries.firstIndex(where: { $0.id == id })
        else { return }
        entries[index].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        guard let entry = entry(id: id) else { return }
        try? fileManager.removeItem(at: directory(for: entry))
        entries.removeAll { $0.id == id }
        persist()
    }

    func image(for entry: DexEntry) -> UIImage? {
        UIImage(contentsOfFile: previewImageURL(for: entry).path(percentEncoded: false))
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([DexEntry].self, from: data)
                .filter {
                    fileManager.fileExists(
                        atPath: sourceImageURL(for: $0).path(percentEncoded: false)
                    )
                }
        } catch {
            entries = []
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: libraryURL, options: .atomic)
        } catch {
            assertionFailure("Could not persist Dex library: \(error)")
        }
    }
}
