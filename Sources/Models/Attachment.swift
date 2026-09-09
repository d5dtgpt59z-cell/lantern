import Foundation
import AppKit
import ImageIO
import PDFKit

struct Attachment: Codable, Identifiable {
    var id = UUID()
    var name: String
    var imageData: Data?
    var text: String?
    static func read(_ url: URL) throws -> Attachment {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 20_000_000 else {
            throw failure("Choose a file smaller than 20 MB.")
        }
        let data = try Data(contentsOf: url)
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1280, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            return Attachment(name: url.lastPathComponent, imageData: png)
        }
        let text: String?
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(data: data), !pdf.isLocked else { throw failure("This PDF is locked or unreadable.") }
            text = pdf.string
        } else { text = String(data: data, encoding: .utf8) }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.contains("\0") else {
            throw failure("Use a photo, UTF-8 text/code file, or PDF with selectable text. For a scanned PDF, attach page images instead.")
        }
        guard text.count <= 12000 else { throw failure("This document is too long. Attach an excerpt of up to 12,000 characters.") }
        return Attachment(name: url.lastPathComponent, text: text)
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "Lantern", code: 4, userInfo: [NSLocalizedDescriptionKey: message]) }
}
