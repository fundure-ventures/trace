import AppKit
import NeoInput
import TraceCalibration
import TraceGeometry

final class HoverCursorView: NSView {
    private var calibration: CalibratedSurface?
    private var hoverPoint: UnitPoint?

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.needsDisplayOnBoundsChange = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setCalibration(_ calibration: CalibratedSurface?) {
        guard calibration != self.calibration else {
            return
        }
        self.calibration = calibration
        setHoverPoint(nil)
    }

    func setHover(_ sample: RawHoverSample?) {
        guard let sample,
              let calibration,
              sample.page == calibration.page,
              let normalized = calibration.calibration.normalize(
                  NcodePoint(x: sample.x, y: sample.y)
              ),
              (0...1).contains(normalized.x),
              (0...1).contains(normalized.y)
        else {
            setHoverPoint(nil)
            return
        }
        setHoverPoint(normalized)
    }

    func clear() {
        setHoverPoint(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.cgContext.clear(bounds)
        guard let hoverPoint else {
            return
        }
        let point = map(
            hoverPoint,
            into: LabPaperLayout.drawingRect(in: bounds)
        )
        let ring = NSBezierPath(
            ovalIn: NSRect(
                x: point.x - 9,
                y: point.y - 9,
                width: 18,
                height: 18
            )
        )
        NSColor.white.withAlphaComponent(0.92).setStroke()
        ring.lineWidth = 5
        ring.stroke()

        NSColor.systemBlue.setStroke()
        ring.lineWidth = 2
        ring.stroke()

        NSColor.systemBlue.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: point.x - 2,
                y: point.y - 2,
                width: 4,
                height: 4
            )
        ).fill()
    }

    private func setHoverPoint(_ point: UnitPoint?) {
        guard point != hoverPoint else {
            return
        }
        hoverPoint = point
        needsDisplay = true
    }

    private func map(_ point: UnitPoint, into rect: NSRect) -> NSPoint {
        NSPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }
}
