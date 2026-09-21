#if DEBUG
import AppKit
import NeoInput
import TraceCalibration
import TraceGeometry

enum HoverCursorProbe {
    static func run() throws {
        let view = HoverCursorView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )
        let page = PenPageID(section: 3, owner: 27, note: 258, page: 1)
        let calibration = try NcodeSurfaceCalibration(
            corners: [
                NcodePoint(x: 0, y: 0),
                NcodePoint(x: 100, y: 0),
                NcodePoint(x: 100, y: 100),
                NcodePoint(x: 0, y: 100),
            ]
        )
        view.setCalibration(
            CalibratedSurface(page: page, calibration: calibration)
        )
        view.setHover(
            hoverSample(
                page: PenPageID(section: 3, owner: 27, note: 258, page: 2)
            )
        )
        guard try bluePixelCount(in: view) == 0 else {
            throw probeError("wrong-page hover displayed a cursor")
        }

        view.setHover(hoverSample(page: page))
        let visibleCursorPixels = try bluePixelCount(in: view)
        guard visibleCursorPixels > 0 else {
            throw probeError("the hover cursor did not render")
        }
        if let path = ProcessInfo.processInfo.environment[
            "TRACE_LAB_HOVER_SNAPSHOT"
        ] {
            try writeSnapshot(
                of: view,
                to: URL(fileURLWithPath: path)
            )
        }

        view.setHover(nil)
        let clearedCursorPixels = try bluePixelCount(in: view)
        guard clearedCursorPixels == 0 else {
            throw probeError("the hover cursor did not clear")
        }
        print(
            "hover-cursor pixels=\(visibleCursorPixels) cleared=0"
        )
    }

    private static func writeSnapshot(
        of view: NSView,
        to url: URL
    ) throws {
        guard let representation = view.bitmapImageRepForCachingDisplay(
            in: view.bounds
        ) else {
            throw probeError("could not render the hover cursor snapshot")
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw probeError("could not encode the hover cursor snapshot")
        }
        try data.write(to: url, options: .atomic)
    }

    private static func hoverSample(page: PenPageID) -> RawHoverSample {
        RawHoverSample(
            id: 1,
            source: .outOfStrokeDot,
            eventCount: 1,
            timeDeltaMilliseconds: 4,
            page: page,
            receivedWallClockMilliseconds: 100,
            receivedUptimeNanoseconds: 100_000_000,
            interArrivalMilliseconds: nil,
            x: 50,
            y: 50,
            force: 0,
            pressure: 0,
            tiltX: 90,
            tiltY: 45,
            twist: 120
        )
    }

    private static func bluePixelCount(
        in view: NSView
    ) throws -> Int {
        guard let representation = view.bitmapImageRepForCachingDisplay(
            in: view.bounds
        ) else {
            throw probeError("could not render the hover cursor fixture")
        }
        view.cacheDisplay(in: view.bounds, to: representation)

        var count = 0
        let centerX = representation.pixelsWide / 2
        let centerY = representation.pixelsHigh / 2
        for y in max(0, centerY - 20)..<min(
            representation.pixelsHigh,
            centerY + 20
        ) {
            for x in max(0, centerX - 20)..<min(
                representation.pixelsWide,
                centerX + 20
            ) {
                guard let color = representation.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
                else {
                    continue
                }
                if color.blueComponent > 0.55,
                   color.blueComponent > color.redComponent * 1.35
                {
                    count += 1
                }
            }
        }
        return count
    }

    private static func probeError(_ message: String) -> NSError {
        NSError(
            domain: "TraceHoverCursorProbe",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
#endif
