import AppKit
import ImageIO
import UniformTypeIdentifiers

enum TraceCopyContent: String, Equatable, CaseIterable {
    case all
    case image
    case dictation
    case document

    /// Title shared by the toolbar's copy-options menu and the
    /// "On copy (cmd+c)" format setting, so both surfaces stay in sync.
    var menuTitle: String {
        switch self {
        case .all:
            return "Copy image and dictation"
        case .image:
            return "Copy image"
        case .dictation:
            return "Copy dictation"
        case .document:
            return "Copy as .pdf"
        }
    }
}

enum TraceClipboardPayload {
    static func makeItem(
        image: NSImage,
        transcript: String?
    ) -> NSPasteboardItem? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let image = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }
        let transcript = transcript?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let item = NSPasteboardItem()
        if let png = encode(
            image,
            type: .png,
            transcript: transcript
        ) {
            item.setData(png, forType: .png)
        }
        if let tiff = encode(
            image,
            type: .tiff,
            transcript: transcript
        ) {
            item.setData(tiff, forType: .tiff)
        }
        guard item.data(forType: .png) != nil
                || item.data(forType: .tiff) != nil
        else {
            return nil
        }
        if let transcript, !transcript.isEmpty {
            item.setString(transcript, forType: .string)
        }
        return item
    }

    static func transcriptMetadata(from imageData: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(
            imageData as CFData,
            nil
        ),
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any]
        else {
            return nil
        }
        if let png = properties[
            kCGImagePropertyPNGDictionary
        ] as? [CFString: Any],
        let description = png[
            kCGImagePropertyPNGDescription
        ] as? String {
            return description
        }
        if let tiff = properties[
            kCGImagePropertyTIFFDictionary
        ] as? [CFString: Any],
        let description = tiff[
            kCGImagePropertyTIFFImageDescription
        ] as? String {
            return description
        }
        return nil
    }

    static func write(
        image: NSImage,
        transcript: String?,
        to pasteboard: NSPasteboard
    ) -> Bool {
        guard let item = makeItem(
            image: image,
            transcript: transcript
        ) else {
            return false
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    static func writeImage(
        _ image: NSImage,
        to pasteboard: NSPasteboard
    ) -> Bool {
        write(image: image, transcript: nil, to: pasteboard)
    }

    static func writeTranscript(
        _ transcript: String,
        to pasteboard: NSPasteboard
    ) -> Bool {
        let transcript = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !transcript.isEmpty else {
            return false
        }
        let item = NSPasteboardItem()
        item.setString(transcript, forType: .string)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    /// US Letter page, in points, used to lay out the "Copy as Document" PDF.
    private static let documentPageSize = CGSize(width: 612, height: 792)
    private static let documentMargin: CGFloat = 48
    private static let documentTextImageSpacing: CGFloat = 16

    static func makeDocumentData(
        image: NSImage,
        transcript: String?
    ) -> Data? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }
        let transcript = transcript?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(
            data: data as CFMutableData
        ) else {
            return nil
        }
        var mediaBox = CGRect(origin: .zero, size: documentPageSize)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            return nil
        }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(
            cgContext: context,
            flipped: false
        )
        drawDocumentPage(
            cgImage: cgImage,
            transcript: transcript,
            in: context
        )
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static func drawDocumentPage(
        cgImage: CGImage,
        transcript: String?,
        in context: CGContext
    ) {
        let contentWidth = documentPageSize.width - documentMargin * 2
        var imageTopY = documentPageSize.height - documentMargin
        if let transcript, !transcript.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.black,
            ]
            let maxHeight = documentPageSize.height
                - documentMargin * 2
            let measuredHeight = (transcript as NSString).boundingRect(
                with: CGSize(
                    width: contentWidth,
                    height: .greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).height
            let textHeight = min(measuredHeight, maxHeight)
            let textRect = CGRect(
                x: documentMargin,
                y: imageTopY - textHeight,
                width: contentWidth,
                height: textHeight
            )
            (transcript as NSString).draw(
                in: textRect,
                withAttributes: attributes
            )
            imageTopY = textRect.minY - documentTextImageSpacing
        }
        let availableHeight = max(imageTopY - documentMargin, 0)
        guard availableHeight > 0 else {
            return
        }
        let imageSize = CGSize(
            width: cgImage.width,
            height: cgImage.height
        )
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }
        // Never upscale past native resolution, only shrink to fit.
        let scale = min(
            contentWidth / imageSize.width,
            availableHeight / imageSize.height,
            1
        )
        let drawSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let drawOrigin = CGPoint(
            x: documentMargin + (contentWidth - drawSize.width) / 2,
            y: imageTopY - drawSize.height
        )
        context.draw(
            cgImage,
            in: CGRect(origin: drawOrigin, size: drawSize)
        )
    }

    /// Fallback used when there is no `.traceboard` document to name the
    /// PDF after (e.g. the isolated pasteboard tests).
    static let defaultDocumentFileName = "Trace Document.pdf"

    static func writeDocument(
        image: NSImage,
        transcript: String?,
        suggestedFileName: String = defaultDocumentFileName,
        to pasteboard: NSPasteboard
    ) -> Bool {
        guard let pdfData = makeDocumentData(
            image: image,
            transcript: transcript
        ) else {
            return false
        }
        let item = NSPasteboardItem()
        item.setData(pdfData, forType: .pdf)
        let fileName = pdfFileName(from: suggestedFileName)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        if (try? pdfData.write(to: tempURL, options: .atomic)) != nil {
            item.setString(tempURL.absoluteString, forType: .fileURL)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    /// Swaps whatever extension `suggestedFileName` carries (e.g. the
    /// matching `.traceboard` document's own name) for `.pdf`, so a
    /// paste into Finder/Mail/etc. shows the same base name as the
    /// document this copy came from.
    private static func pdfFileName(from suggestedFileName: String) -> String {
        let trimmed = suggestedFileName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return defaultDocumentFileName
        }
        let base = (trimmed as NSString).deletingPathExtension
        guard !base.isEmpty else {
            return defaultDocumentFileName
        }
        return "\(base).pdf"
    }

    private static func encode(
        _ image: CGImage,
        type: UTType,
        transcript: String?
    ) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let transcript, !transcript.isEmpty {
            properties[kCGImagePropertyPNGDictionary] = [
                kCGImagePropertyPNGDescription: transcript,
            ]
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFImageDescription: transcript,
            ]
        }
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
