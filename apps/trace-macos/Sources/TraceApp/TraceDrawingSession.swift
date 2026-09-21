import AppKit
import TraceAppCore

final class TraceDrawingSession {
    var manifest: TraceDrawingManifest
    var screenshot: NSImage
    var tldrawSnapshotJSON: String?
    let packageURL: URL

    init(
        manifest: TraceDrawingManifest,
        screenshot: NSImage,
        tldrawSnapshotJSON: String? = nil,
        packageURL: URL
    ) {
        self.manifest = manifest
        self.screenshot = screenshot
        self.tldrawSnapshotJSON = tldrawSnapshotJSON
        self.packageURL = packageURL
    }
}

enum TraceDrawingStoreError: LocalizedError {
    case invalidScreenshot
    case missingManifest
    case missingScreenshot
    case missingVoiceRecording

    var errorDescription: String? {
        switch self {
        case .invalidScreenshot:
            return "Trace could not encode the captured window."
        case .missingManifest:
            return "This Trace drawing is missing its document data."
        case .missingScreenshot:
            return "This Trace drawing is missing its captured screenshot."
        case .missingVoiceRecording:
            return "Trace could not preserve the recorded voice annotation."
        }
    }
}

final class TraceDrawingStore {
    let directoryURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        documentsDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = documentsDirectoryURL
                ?? fileManager.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                ).first
                ?? fileManager.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first
                ?? fileManager.homeDirectoryForCurrentUser
            let preferred = base.appendingPathComponent(
                "Trace",
                isDirectory: true
            )
            let legacy = base.appendingPathComponent(
                "Trace Drawings",
                isDirectory: true
            )
            var resolved = preferred
            if fileManager.fileExists(atPath: legacy.path),
               !fileManager.fileExists(atPath: preferred.path)
            {
                do {
                   try fileManager.moveItem(at: legacy, to: preferred)
                } catch {
                    resolved = legacy
                    NSLog(
                        "Trace could not rename drawing folder: %@",
                        error.localizedDescription
                    )
                }
            }
            self.directoryURL = resolved
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func create(
        from capture: CapturedWindow,
        backgroundColor: TraceRGBAColor,
        sourceWindowCornerRadius: Double? = nil
    ) throws -> TraceDrawingSession {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let now = Date()
        let baseName = TraceDrawingFileName.make(
            applicationName: capture.descriptor.ownerName,
            date: now
        )
        let packageURL = uniqueURL(
            for: directoryURL.appendingPathComponent(
                baseName,
                isDirectory: true
            )
        )
        try fileManager.createDirectory(
            at: packageURL,
            withIntermediateDirectories: false
        )
        do {
            let screenshotFileName = "screenshot.png"
            let screenshotURL = packageURL.appendingPathComponent(
                screenshotFileName
            )
            let representation = NSBitmapImageRep(cgImage: capture.cgImage)
            guard let png = representation.representation(
                using: .png,
                properties: [:]
            ) else {
                throw TraceDrawingStoreError.invalidScreenshot
            }
            try png.write(to: screenshotURL, options: .atomic)

            let manifest = TraceDrawingManifest(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                sourceApplicationName: capture.descriptor.ownerName,
                sourceWindowTitle: capture.descriptor.title,
                screenshotFileName: screenshotFileName,
                screenshotPixelWidth: capture.cgImage.width,
                screenshotPixelHeight: capture.cgImage.height,
                coordinateSpace: .surfaceNormalized,
                sourceWindowCornerRadius: sourceWindowCornerRadius
                    ?? inferredCornerRadius(
                        from: representation,
                        sourceBounds: capture.descriptor.bounds
                    ),
                sourceWindowBounds: capture.descriptor.bounds,
                pageKind: .screenshot,
                backgroundColor: backgroundColor,
                viewport: TracePageViewport.full,
                strokes: []
            )
            let session = TraceDrawingSession(
                manifest: manifest,
                screenshot: NSImage(
                    cgImage: capture.cgImage,
                    size: NSSize(
                        width: capture.cgImage.width,
                        height: capture.cgImage.height
                    )
                ),
                packageURL: packageURL
            )
            try save(session)
            return session
        } catch {
            try? fileManager.removeItem(at: packageURL)
            throw error
        }
    }

    func createBlank(
        size: NSSize,
        backingScale: CGFloat,
        backgroundColor: TraceRGBAColor
    ) throws -> TraceDrawingSession {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let now = Date()
        let packageURL = uniqueURL(
            for: directoryURL.appendingPathComponent(
                TraceDrawingFileName.make(
                    applicationName: "Blank Page",
                    date: now
                ),
                isDirectory: true
            )
        )
        try fileManager.createDirectory(
            at: packageURL,
            withIntermediateDirectories: false
        )
        do {
            let screenshotFileName = "screenshot.png"
            let screenshot = try solidImage(color: backgroundColor)
            guard let representation = bitmapRepresentation(of: screenshot),
                  let png = representation.representation(
                      using: .png,
                      properties: [:]
                  )
            else {
                throw TraceDrawingStoreError.invalidScreenshot
            }
            try png.write(
                to: packageURL.appendingPathComponent(screenshotFileName),
                options: .atomic
            )
            let width = max(1, size.width)
            let height = max(1, size.height)
            let manifest = TraceDrawingManifest(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                sourceApplicationName: "Trace",
                sourceWindowTitle: "Blank Page",
                screenshotFileName: screenshotFileName,
                screenshotPixelWidth: max(
                    1,
                    Int((width * backingScale).rounded())
                ),
                screenshotPixelHeight: max(
                    1,
                    Int((height * backingScale).rounded())
                ),
                sourceWindowCornerRadius: 14,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: height
                ),
                pageKind: .blank,
                backgroundColor: backgroundColor,
                viewport: TracePageViewport.full,
                strokes: []
            )
            let session = TraceDrawingSession(
                manifest: manifest,
                screenshot: screenshot,
                packageURL: packageURL
            )
            try save(session)
            return session
        } catch {
            try? fileManager.removeItem(at: packageURL)
            throw error
        }
    }

    func save(_ session: TraceDrawingSession) throws {
        if let snapshot = session.tldrawSnapshotJSON {
            try Data(snapshot.utf8).write(
                to: session.packageURL.appendingPathComponent(
                    "tldraw.json"
                ),
                options: .atomic
            )
        }
        session.manifest.updatedAt = Date()
        let data = try encoder.encode(session.manifest)
        try data.write(
            to: session.packageURL.appendingPathComponent("document.json"),
            options: .atomic
        )
    }

    func attachVoice(
        audioFileURL: URL?,
        transcript: String,
        to session: TraceDrawingSession
    ) throws {
        guard let audioFileURL else {
            throw TraceDrawingStoreError.missingVoiceRecording
        }
        let audioFileName = "voice.wav"
        let transcriptFileName = "transcript.txt"
        let audioDestination = session.packageURL.appendingPathComponent(
            audioFileName
        )
        let transcriptDestination = session.packageURL.appendingPathComponent(
            transcriptFileName
        )
        let audioTemporary = session.packageURL.appendingPathComponent(
            ".voice-\(UUID().uuidString).tmp"
        )
        let transcriptTemporary = session.packageURL.appendingPathComponent(
            ".transcript-\(UUID().uuidString).tmp"
        )
        defer {
            try? fileManager.removeItem(at: audioTemporary)
            try? fileManager.removeItem(at: transcriptTemporary)
        }

        try fileManager.copyItem(
            at: audioFileURL,
            to: audioTemporary
        )
        try Data(transcript.utf8).write(
            to: transcriptTemporary,
            options: .atomic
        )
        if fileManager.fileExists(atPath: audioDestination.path) {
            try fileManager.removeItem(at: audioDestination)
        }
        if fileManager.fileExists(atPath: transcriptDestination.path) {
            try fileManager.removeItem(at: transcriptDestination)
        }
        try fileManager.moveItem(
            at: audioTemporary,
            to: audioDestination
        )
        try fileManager.moveItem(
            at: transcriptTemporary,
            to: transcriptDestination
        )
        session.manifest.voiceRecordingFileName = audioFileName
        session.manifest.transcriptFileName = transcriptFileName
        try save(session)
    }

    func removeVoiceArtifacts(
        from session: TraceDrawingSession
    ) throws {
        for fileName in [
            session.manifest.voiceRecordingFileName,
            session.manifest.transcriptFileName,
        ].compactMap({ $0 }) {
            let url = session.packageURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        session.manifest.voiceRecordingFileName = nil
        session.manifest.transcriptFileName = nil
    }

    func load(from packageURL: URL) throws -> TraceDrawingSession {
        let manifestURL = packageURL.appendingPathComponent("document.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw TraceDrawingStoreError.missingManifest
        }
        var manifest = try decoder.decode(
            TraceDrawingManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        if manifest.pageKind == nil {
            manifest.pageKind = .screenshot
        }
        if manifest.viewport == nil {
            manifest.viewport = TracePageViewport.full
        }
        normalizeScreenshotViewport(&manifest)
        let screenshotURL = packageURL.appendingPathComponent(
            manifest.screenshotFileName
        )
        guard let screenshot = NSImage(contentsOf: screenshotURL) else {
            throw TraceDrawingStoreError.missingScreenshot
        }
        let tldrawURL = packageURL.appendingPathComponent("tldraw.json")
        let tldrawSnapshotJSON = fileManager.fileExists(
            atPath: tldrawURL.path
        ) ? try String(contentsOf: tldrawURL, encoding: .utf8) : nil
        if manifest.sourceWindowCornerRadius == nil,
           let representation = bitmapRepresentation(of: screenshot)
        {
            let sourceBounds = manifest.sourceWindowBounds
                ?? TraceRect(
                    x: 0,
                    y: 0,
                    width: Double(manifest.screenshotPixelWidth),
                    height: Double(manifest.screenshotPixelHeight)
                )
            manifest.sourceWindowCornerRadius = inferredCornerRadius(
                from: representation,
                sourceBounds: sourceBounds
            )
        }
        return TraceDrawingSession(
            manifest: manifest,
            screenshot: screenshot,
            tldrawSnapshotJSON: tldrawSnapshotJSON,
            packageURL: packageURL
        )
    }

    private func uniqueURL(for requested: URL) -> URL {
        guard fileManager.fileExists(atPath: requested.path) else {
            return requested
        }
        let directory = requested.deletingLastPathComponent()
        let stem = requested.deletingPathExtension().lastPathComponent
        let pathExtension = requested.pathExtension
        for index in 2...999 {
            let name = "\(stem)-\(index).\(pathExtension)"
            let candidate = directory.appendingPathComponent(
                name,
                isDirectory: true
            )
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory.appendingPathComponent(
            "\(stem)-\(UUID().uuidString).\(pathExtension)",
            isDirectory: true
        )
    }

    private func inferredCornerRadius(
        from representation: NSBitmapImageRep,
        sourceBounds: TraceRect
    ) -> Double {
        guard representation.hasAlpha,
              representation.pixelsWide > 0,
              representation.pixelsHigh > 0
        else {
            return 0
        }
        let threshold: CGFloat = 0.5
        let horizontalInset = (0..<representation.pixelsWide).first {
            (representation.colorAt(x: $0, y: 0)?.alphaComponent ?? 0)
                >= threshold
        } ?? 0
        let verticalInset = (0..<representation.pixelsHigh).first {
            (representation.colorAt(x: 0, y: $0)?.alphaComponent ?? 0)
                >= threshold
        } ?? 0
        return TraceWindowSilhouette.cornerRadiusPoints(
            horizontalInsetPixels: horizontalInset,
            verticalInsetPixels: verticalInset,
            pixelSize: TraceSize(
                width: Double(representation.pixelsWide),
                height: Double(representation.pixelsHigh)
            ),
            sourceSize: TraceSize(
                width: sourceBounds.width,
                height: sourceBounds.height
            )
        )
    }

    private func bitmapRepresentation(
        of image: NSImage
    ) -> NSBitmapImageRep? {
        if let representation = image.representations.first(where: {
            $0 is NSBitmapImageRep
        }) as? NSBitmapImageRep {
            return representation
        }
        guard let data = image.tiffRepresentation else {
            return nil
        }
        return NSBitmapImageRep(data: data)
    }

    private func solidImage(
        color: TraceRGBAColor
    ) throws -> NSImage {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: representation)
        else {
            throw TraceDrawingStoreError.invalidScreenshot
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(color).setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.addRepresentation(representation)
        return image
    }

    private func normalizeScreenshotViewport(
        _ manifest: inout TraceDrawingManifest
    ) {
        guard manifest.pageKind == .screenshot,
              let viewport = manifest.viewport
        else {
            return
        }
        let isNormalized =
            viewport.x >= 0
                && viewport.y >= 0
                && viewport.width > 0
                && viewport.height > 0
                && viewport.x + viewport.width <= 1
                && viewport.y + viewport.height <= 1
        guard isNormalized,
              let source = manifest.sourceWindowBounds
        else {
            manifest.viewport = TracePageViewport.full
            return
        }
        let visibleWidth = source.width * viewport.width
        let visibleHeight = source.height * viewport.height
        if (source.width >= 32 && visibleWidth < 32)
            || (source.height >= 32 && visibleHeight < 32)
        {
            manifest.viewport = TracePageViewport.full
        }
    }
}
