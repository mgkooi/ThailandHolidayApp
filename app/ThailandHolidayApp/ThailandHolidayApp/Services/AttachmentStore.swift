import Foundation
import UIKit

struct AttachmentStore {
    private let fileManager: FileManager
    let documentsDirectory: URL

    init(documentsDirectory: URL, fileManager: FileManager = .default) {
        self.documentsDirectory = documentsDirectory
        self.fileManager = fileManager
    }

    var attachmentsDirectory: URL {
        documentsDirectory.appendingPathComponent("Attachments", isDirectory: true)
    }

    func imageURL(for filename: String) -> URL {
        attachmentsDirectory.appendingPathComponent(filename)
    }

    func prepareDirectory() throws {
        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
    }

    func saveImageData(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else {
            throw AttachmentStoreError.invalidImage
        }

        let resized = image.resized(maxLongEdge: 2_400)
        guard let encoded = resized.jpegData(compressionQuality: 0.85) else {
            throw AttachmentStoreError.encodingFailed
        }

        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).jpg"
        try encoded.write(to: imageURL(for: filename), options: .atomic)
        return filename
    }

    func deleteAttachment(filename: String) throws {
        let url = imageURL(for: filename)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

enum AttachmentStoreError: LocalizedError {
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Het gekozen bestand is geen geldige afbeelding."
        case .encodingFailed: "De afbeelding kon niet worden verwerkt."
        }
    }
}

private extension UIImage {
    func resized(maxLongEdge: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return self }
        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
