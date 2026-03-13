import Foundation
import UIKit
import UniformTypeIdentifiers
import PDFKit

class FileService {

    static func processImageData(_ data: Data, fileName: String) -> AttachmentItem {
        // Compress image if too large
        var processedData = data
        if data.count > 5_000_000, let image = UIImage(data: data) {
            let compressed = compressImage(image, maxBytes: 4_500_000)
            processedData = compressed ?? data
        }
        return AttachmentItem(name: fileName, type: .image, data: processedData)
    }

    static func processFileData(_ data: Data, fileName: String, contentType: UTType?) -> AttachmentItem {
        let type: AttachmentItem.AttachmentType
        if contentType?.conforms(to: .image) == true {
            type = .image
        } else if contentType?.conforms(to: .pdf) == true {
            type = .pdf
        } else {
            type = .document
        }
        return AttachmentItem(name: fileName, type: type, data: data)
    }

    static func extractTextFromPDF(data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                text += page.string ?? ""
                text += "\n"
            }
        }
        return text.isEmpty ? nil : text
    }

    private static func compressImage(_ image: UIImage, maxBytes: Int) -> Data? {
        var compression: CGFloat = 0.9
        var data = image.jpegData(compressionQuality: compression)
        while let d = data, d.count > maxBytes, compression > 0.1 {
            compression -= 0.1
            data = image.jpegData(compressionQuality: compression)
        }
        return data
    }

    static func thumbnailForAttachment(_ attachment: AttachmentItem) -> UIImage? {
        switch attachment.type {
        case .image:
            guard let data = attachment.data else { return nil }
            return UIImage(data: data)
        case .pdf:
            guard let data = attachment.data,
                  let doc = PDFDocument(data: data),
                  let page = doc.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: bounds.size)
            return renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(bounds)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
        case .document, .audio:
            return UIImage(systemName: "doc.text")
        }
    }
}
