import AppKit

enum LabPaperLayout {
    static let drawingSize = NSSize(width: 1_024, height: 720)
    static let canvasInset: CGFloat = 24
    static let statusBarHeight: CGFloat = 42
    static let paperKitToolbarBandHeight: CGFloat = 52
    static let minimumRendererSize = NSSize(
        width: drawingSize.width + canvasInset * 2,
        height:
            drawingSize.height
                + canvasInset * 2
                + paperKitToolbarBandHeight
    )
    static let minimumWindowContentSize = NSSize(
        width: minimumRendererSize.width,
        height: minimumRendererSize.height + statusBarHeight
    )
    static let preferredWindowContentSize = minimumWindowContentSize

    static func drawingRect(
        in bounds: NSRect,
        topReservedHeight: CGFloat = 0
    ) -> NSRect {
        guard bounds.width.isFinite,
              bounds.height.isFinite,
              topReservedHeight.isFinite,
              topReservedHeight >= 0
        else {
            return .zero
        }
        let available = NSRect(
            x: bounds.minX + canvasInset,
            y: bounds.minY + canvasInset + topReservedHeight,
            width: bounds.width - canvasInset * 2,
            height:
                bounds.height
                    - canvasInset * 2
                    - topReservedHeight
        )
        guard available.width >= drawingSize.width,
              available.height >= drawingSize.height
        else {
            return .zero
        }
        return NSRect(
            x: round(available.midX - drawingSize.width / 2),
            y: round(available.midY - drawingSize.height / 2),
            width: drawingSize.width,
            height: drawingSize.height
        )
    }
}
