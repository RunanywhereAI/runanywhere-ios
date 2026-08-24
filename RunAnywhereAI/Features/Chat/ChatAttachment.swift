import Foundation
import RunAnywhere
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import PDFKit

enum AttachmentPayload {
    case image(Data)
    case document(String)
}

struct ChatAttachment: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let byteCount: Int
    let payload: AttachmentPayload

    static func == (lhs: ChatAttachment, rhs: ChatAttachment) -> Bool { lhs.id == rhs.id }

    var isImage: Bool {
        if case .image = payload { return true }
        return false
    }

    var symbol: String { isImage ? "photo" : "doc.text" }

    var imageData: Data? {
        if case .image(let data) = payload { return data }
        return nil
    }

    var text: String? {
        if case .document(let text) = payload { return text }
        return nil
    }

    /// What the composer shows under the filename.
    var detail: String {
        if let text {
            let words = text.split(whereSeparator: \.isWhitespace).count
            return "\(words) words · \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// The longest edge a photo is scaled to before it reaches the model.
    ///
    /// A screenshot from a 5K display is ~14 megapixels; handing that to a VLM
    /// expands into a very large token grid and the process is killed on memory
    /// before it ever answers.
    static let maxImageEdge: CGFloat = 1024

    func modelImage() throws -> ImageInput {
        guard let data = imageData else {
            throw AttachmentError.unsupported("That attachment is not an image.")
        }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            throw AttachmentError.unsupported("That image could not be decoded.")
        }
        return try ImageInput.uiImage(Self.downscale(image))
        #else
        guard let image = NSImage(data: data) else {
            throw AttachmentError.unsupported("That image could not be decoded.")
        }
        return try ImageInput.nsImage(Self.downscale(image))
        #endif
    }

    #if canImport(UIKit)
    private static func downscale(_ image: UIImage) -> UIImage {
        // Pixels, not points: `UIImage.size` is points and a 3x photo is three
        // times larger than this guard would otherwise think.
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        guard longest > maxImageEdge else { return image }
        let scale = maxImageEdge / longest
        let target = CGSize(
            width: (image.size.width * image.scale * scale).rounded(),
            height: (image.size.height * image.scale * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
    #else
    /// Measured in pixels, not points.
    ///
    /// `NSImage.size` is a point size, so a 2x screenshot reports 1024x662 for a
    /// 2048x1324 bitmap and the guard never fired: the full-resolution CGImage
    /// still reached the model.
    private static func downscale(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let pixelWidth = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxImageEdge else { return image }

        let scale = maxImageEdge / longest
        let target = NSSize(width: (pixelWidth * scale).rounded(), height: (pixelHeight * scale).rounded())
        let output = NSImage(size: target)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        return output
    }
    #endif
}

enum AttachmentError: LocalizedError {
    case unsupported(String)
    case tooLarge(String)
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message), .tooLarge(let message), .empty(let message):
            return message
        }
    }
}

/// Turning a picked file into something a model can read.
///
/// The picker's `allowedContentTypes` filters the picker, not a drop or a
/// paste, so the file decides the mode here and an unsupported one says so
/// rather than reaching the model and failing as if the model were at fault.
enum AttachmentLoader {
    static let documentTypes: [UTType] = [.pdf, .json, .plainText, .rtf]
    static let imageTypes: [UTType] = [.png, .jpeg, .heic, .gif, .tiff, .webP]

    static let maxImageBytes = 12 * 1024 * 1024
    static let maxDocumentBytes = 4 * 1024 * 1024

    static func load(from url: URL) async throws -> ChatAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)

        if type?.conforms(to: .image) == true {
            guard data.count <= maxImageBytes else {
                throw AttachmentError.tooLarge("\(name) is larger than 12 MB.")
            }
            return ChatAttachment(filename: name, byteCount: data.count, payload: .image(data))
        }

        guard data.count <= maxDocumentBytes else {
            throw AttachmentError.tooLarge("\(name) is larger than 4 MB.")
        }

        let text = try extractText(from: data, url: url, ext: ext)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AttachmentError.empty("\(name) has no readable text in it.")
        }
        return ChatAttachment(filename: name, byteCount: data.count, payload: .document(trimmed))
    }

    /// PDF parsing and large-file decoding block the caller, so this runs off
    /// the main actor via the detached task in `AttachmentLoader.load(from:)`'s
    /// caller. Kept pure so it can be tested without a file picker.
    private static func extractText(from data: Data, url: URL, ext: String) throws -> String {
        switch ext {
        case "pdf":
            guard let document = PDFDocument(data: data) else {
                throw AttachmentError.unsupported("That PDF could not be opened.")
            }
            var text = ""
            for index in 0..<document.pageCount {
                if let page = document.page(at: index)?.string {
                    text += page + "\n"
                }
            }
            return text
        case "txt", "md", "markdown", "json", "csv", "log", "xml", "yaml", "yml":
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw AttachmentError.unsupported("\(url.lastPathComponent) is not readable text.")
            }
            return text
        case "rtf":
            #if canImport(AppKit) && !canImport(UIKit)
            let attributed = try NSAttributedString(data: data, options: [:], documentAttributes: nil)
            return attributed.string
            #else
            throw AttachmentError.unsupported("RTF is not supported here.")
            #endif
        default:
            if let text = String(data: data, encoding: .utf8) { return text }
            throw AttachmentError.unsupported("\(url.lastPathComponent) is not a supported file type.")
        }
    }
}

enum AttachmentImport {
    case image
    case document
}
