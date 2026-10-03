import Foundation

enum DexEntryStatus: String, Codable, Sendable {
    case generating
    case ready
    case failed
}

struct DexEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let number: Int
    var name: String
    let createdAt: Date
    let sourceImageFileName: String
    var previewImageFileName: String
    var glbFileName: String?
    var usdzFileName: String?
    var generationID: String?
    var status: DexEntryStatus
    var statusMessage: String?

    init(
        id: UUID = UUID(),
        number: Int,
        name: String,
        createdAt: Date = Date(),
        sourceImageFileName: String = "source.jpg",
        previewImageFileName: String = "preview.jpg",
        glbFileName: String? = nil,
        usdzFileName: String? = nil,
        generationID: String? = nil,
        status: DexEntryStatus = .generating,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.createdAt = createdAt
        self.sourceImageFileName = sourceImageFileName
        self.previewImageFileName = previewImageFileName
        self.glbFileName = glbFileName
        self.usdzFileName = usdzFileName
        self.generationID = generationID
        self.status = status
        self.statusMessage = statusMessage
    }

    var dexNumber: String {
        String(format: "#%04d", number)
    }
}
