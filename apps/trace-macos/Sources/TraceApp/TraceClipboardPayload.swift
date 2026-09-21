import AppKit
import ImageIO
import UniformTypeIdentifiers

enum TraceCopyContent: Equatable {
    case all
    case dictation
    case image
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
