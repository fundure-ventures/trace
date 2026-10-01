#if DEBUG
import AppKit
import NeoTransport
import TraceAppCore
import TraceVoice

enum ProductTldrawProbe {
    @MainActor
    static func run(
        textToolsOnly: Bool = false,
        framingOnly: Bool = false
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let surface = TldrawProductCanvasView(
            frame: NSRect(x: 0, y: 0, width: 1_024, height: 720)
        )
        let window = NSWindow(
            contentRect: surface.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let frontmostProcessID =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = surface
        window.orderBack(nil)
        defer {
            window.orderOut(nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        guard !window.isKeyWindow,
              window.alphaValue == 0,
              frontmostProcessID == nil
                || NSWorkspace.shared.frontmostApplication?
                    .processIdentifier == frontmostProcessID
        else {
            throw probeError(
                "product probe window interrupted the active application"
            )
        }

        try await waitUntil("product tldraw ready") {
            surface.isReadyForTesting || surface.unavailableReason != nil
        }
        if let reason = surface.unavailableReason {
            throw probeError("product tldraw unavailable: \(reason)")
        }
        if framingOnly {
            try await verifyOffCenterDocumentFraming(
                surface,
                directory: directory
            )
            return
        }

        let document = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Trace Probe",
                sourceWindowTitle: "Product tldraw",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: 1_024,
                screenshotPixelHeight: 720,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 1_024,
                    height: 720
                ),
                pageKind: .blank,
                backgroundColor: TraceRGBAColor(
                    red: 1,
                    green: 1,
                    blue: 1
                ),
                viewport: TracePageViewport.full,
                strokes: [
                    TraceDrawingStroke(
                        id: 1,
                        color: .green,
                        brush: .highlighter,
                        width: 7.5,
                        points: [
                            TraceDrawingPoint(
                                x: 0.1,
                                y: 0.2,
                                pressure: 0.4,
                                tiltX: nil,
                                tiltY: nil,
                                twistDegrees: nil,
                                connectsToPrevious: false
                            ),
                            TraceDrawingPoint(
                                x: 0.6,
                                y: 0.5,
                                pressure: 0.7,
                                tiltX: nil,
                                tiltY: nil,
                                twistDegrees: nil,
                                connectsToPrevious: true
                            ),
                        ]
                    ),
                ]
            ),
            screenshot: solidImage(
                color: .white,
                size: NSSize(width: 1_024, height: 720)
            ),
            packageURL: directory
        )
        if textToolsOnly {
            try TraceRetainedInkProbe.runDrawingToolChecks(document: document)
            try await verifyTextEditing(surface, document: document)
            try await verifyIndependentStrokeWidths(surface)
            try await verifyRectangleWidths(surface)
            try await verifySelectionCopy(surface)
            try await verifyCapturedScreenshotOpacity(surface, document: document)
            return
        }
        var tool = TraceToolState()
        tool.canvasTool = .highlighter
        tool.color = .green
        tool.brush = .highlighter
        tool.width = 7.5
        var snapshots: [String] = []
        var userEditCount = 0
        var shortcutTools: [TraceCanvasTool] = []
        var temporaryTools: [String] = []
        var latestTimedShapes: [TraceTimedCanvasShape] = []
        let defaultsSuite =
            "TraceProductTldrawProbe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            throw probeError("could not create product probe defaults")
        }
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        let model = TraceAppModel(
            drawingStore: TraceDrawingStore(directoryURL: directory),
            defaults: defaults,
            transportFactory: {
                ProductTldrawProbeTransport()
            }
        )
        model.prepareDocumentForHistoryTesting(document)
        model.onTranscriptAnnotationsChange = {
            surface.syncStrokes(document)
        }
        defer {
            model.stop()
        }
        surface.onSnapshotChange = { snapshot, timedShapes in
            snapshots.append(snapshot)
            latestTimedShapes = timedShapes
            model.updateTldrawSnapshot(
                snapshot,
                timedShapes: timedShapes
            )
        }
        surface.onUserEdit = {
            userEditCount += $0
        }
        surface.onToolChange = {
            shortcutTools.append($0)
        }
        surface.onTemporaryToolChange = {
            temporaryTools.append($0?.rawValue ?? "none")
        }
        surface.setDocument(document, toolState: tool)

        try await waitUntil("product document") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["backgroundCount"] as? NSNumber)?.intValue == 0
                && state["backgroundLocked"] as? Bool == true
                && state["productTool"] as? String == "highlighter"
                && state["color"] as? String == "green"
        }
        guard let state = await surface.stateForTesting() else {
            throw probeError("Trace toolbar state was unavailable")
        }
        guard (state["uiElementCount"] as? NSNumber)?.intValue == 0,
              state["selectedTool"] as? String == "draw",
              state["productTool"] as? String == "highlighter",
              (
                  state["renderedBackgroundColor"] as? String
              )?.contains("255, 255, 255") == true,
              state["color"] as? String == "green",
              (state["opacity"] as? NSNumber)?.doubleValue == 1,
              abs(
                  ((state["width"] as? NSNumber)?.doubleValue ?? 0)
                      - 16
              ) < 0.001,
              (state["drawWidths"] as? [NSNumber])?.contains(where: {
                  abs($0.doubleValue - 7.5) < 0.001
              }) == true,
              (state["drawOpacities"] as? [NSNumber])?.allSatisfy({
                  $0.doubleValue == 1
              }) == true,
              (state["drawColors"] as? [String])?.contains("light-green")
                  == true,
              let drawColors = state["drawColors"] as? [String],
              state["drawBlendModes"] as? [String] == drawColors.map({
                  $0 == "light-green" ? "multiply" : "normal"
              }),
              let inkColors = state["inkColors"] as? [String: String],
              let highlighterColors =
                state["highlighterColors"] as? [String: String],
              let derivedGreen = inkColors["green"],
              derivedGreen != "#099268",
              highlighterColors["green"] != derivedGreen,
              (state["annotationCount"] as? NSNumber)?.intValue == 0,
              (state["lockedPenCount"] as? NSNumber)?.intValue == 1,
              state["derivedLayersAtBack"] as? Bool == true,
              let initialBackgroundSource =
                state["backgroundSource"] as? String
        else {
            throw probeError(
                "Trace toolbar did not configure tldraw: \(state)"
            )
        }
        document.manifest.strokes[0].transcriptAnnotation =
            TraceTranscriptAnnotation(id: 3, wordID: 8)
        surface.syncStrokes(document)
        try await waitUntil("late transcript annotation") {
            guard let annotationState =
                    await surface.stateForTesting(),
                  let center =
                    annotationState["annotationCenter"]
                        as? [String: Any]
            else {
                return false
            }
            let centerX =
                (center["x"] as? NSNumber)?.doubleValue ?? 1_024
            let centerY =
                (center["y"] as? NSNumber)?.doubleValue ?? 720
            let annotationWidth =
                (center["width"] as? NSNumber)?.doubleValue ?? 100
            let annotationHeight =
                (center["height"] as? NSNumber)?.doubleValue ?? 0
            return (
                annotationState["annotationCount"] as? NSNumber
            )?.intValue == 1
                && centerX < 100
                && centerY < 144
                && center["text"] as? String == "3"
                && (center["opacity"] as? NSNumber)?.doubleValue
                    == 1
                && abs(annotationWidth - annotationHeight) < 0.001
                && annotationWidth <= 26
                && center["fill"] as? String == derivedGreen
                && center["textColor"] as? String == "#ffffff"
                && center["fontFamily"] as? String
                    == "-apple-system, BlinkMacSystemFont, sans-serif"
                && annotationState["annotationIsTopmost"] as? Bool
                    == true
        }
        surface.setBackgroundColor(.red)
        try await waitUntil("product background color") {
            guard let colorState = await surface.stateForTesting() else {
                return false
            }
            return colorState["backgroundSource"] as? String
                != initialBackgroundSource
                && (
                    colorState["renderedBackgroundColor"] as? String
                )?.contains("245, 48, 46") == true
                && (
                    colorState["backgroundCount"] as? NSNumber
                )?.intValue == 0
        }
        document.manifest.backgroundColor = .red
        guard let spaceEvent = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: " ",
                  code: "Space"
              ),
              spaceEvent["defaultPrevented"] as? Bool == true
        else {
            throw probeError(
                "Space was not consumed by the tldraw canvas"
            )
        }
        guard await surface.setZoomForTesting(1),
              let initialZoomState = await surface.stateForTesting(),
              let zoomIn = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: "=",
                  code: "Equal",
                  metaKey: true
              ),
              zoomIn["defaultPrevented"] as? Bool == true
        else {
            throw probeError("Command-plus did not handle zoom in")
        }
        try await waitUntil("125% zoom") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return abs(
                ((state["zoom"] as? NSNumber)?.doubleValue ?? 0)
                    - 1.25
            ) < 0.001
                && sameViewportCenter(state, initialZoomState)
        }
        guard let secondZoomIn = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: "+",
                  code: "Equal",
                  metaKey: true
              ),
              secondZoomIn["defaultPrevented"] as? Bool == true
        else {
            throw probeError("second Command-plus did not handle zoom in")
        }
        try await waitUntil("150% zoom") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return abs(
                ((state["zoom"] as? NSNumber)?.doubleValue ?? 0)
                    - 1.5
            ) < 0.001
                && sameViewportCenter(state, initialZoomState)
        }
        guard let zoomOut = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: "-",
                  code: "Minus",
                  metaKey: true
              ),
              zoomOut["defaultPrevented"] as? Bool == true
        else {
            throw probeError("Command-minus did not handle zoom out")
        }
        try await waitUntil("125% zoom after zoom out") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return abs(
                ((state["zoom"] as? NSNumber)?.doubleValue ?? 0)
                    - 1.25
            ) < 0.001
                && sameViewportCenter(state, initialZoomState)
        }
        guard let zoomReset = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: "0",
                  code: "Digit0",
                  metaKey: true
              ),
              zoomReset["defaultPrevented"] as? Bool == true
        else {
            throw probeError("Command-0 did not handle zoom reset")
        }
        try await waitUntil("100% zoom") {
            guard let zoomState = await surface.stateForTesting() else {
                return false
            }
            return abs(
                ((zoomState["zoom"] as? NSNumber)?.doubleValue ?? 0)
                    - 1
            ) < 0.001
                && sameViewportCenter(
                    zoomState,
                    initialZoomState
                )
        }
        guard await surface.setZoomForTesting(0.1),
              let minimumZoomOut =
                  await surface.keyboardEventForTesting(
                      type: "keydown",
                      key: "-",
                      code: "Minus",
                      metaKey: true
                  ),
              minimumZoomOut["defaultPrevented"] as? Bool == true
        else {
            throw probeError(
                "Command-minus did not handle low zoom"
            )
        }
        try await waitUntil("minimum zoom") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return abs(
                ((state["zoom"] as? NSNumber)?.doubleValue ?? 0)
                    - 0.05
            ) < 0.001
        }
        guard await surface.setZoomForTesting(1) else {
            throw probeError("could not restore zoom after minimum")
        }
        guard let beforeResize = await surface.stateForTesting() else {
            throw probeError("product resize state was unavailable")
        }
        window.setContentSize(
            NSSize(width: 1_184, height: 800)
        )
        try await waitUntil("expanded tldraw viewport") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["viewportWidth"] as? NSNumber)?.doubleValue
                    == 1_184
                && (state["viewportHeight"] as? NSNumber)?.doubleValue
                    == 800
                && (state["pageWidth"] as? NSNumber)?.doubleValue
                    == 1_024
                && (state["pageHeight"] as? NSNumber)?.doubleValue
                    == 720
                && abs(
                    ((state["zoom"] as? NSNumber)?.doubleValue ?? 0)
                        - (
                            (beforeResize["zoom"] as? NSNumber)?
                                .doubleValue ?? 0
                        )
                ) < 0.001
        }
        window.setContentSize(
            NSSize(width: 1_024, height: 720)
        )
        try await waitUntil("restored tldraw viewport") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["viewportWidth"] as? NSNumber)?.doubleValue
                    == 1_024
                && (state["viewportHeight"] as? NSNumber)?.doubleValue
                    == 720
                && (state["pageWidth"] as? NSNumber)?.doubleValue
                    == 1_024
                && (state["pageHeight"] as? NSNumber)?.doubleValue
                    == 720
                && abs(
                    ((state["zoom"] as? NSNumber)?.doubleValue ?? 0)
                        - 1
                ) < 0.001
        }
        tool.gridStyle = .square
        tool.gridSpacingPoints = 16
        surface.setToolState(tool)
        try await waitUntil("product grid") {
            guard let gridState = await surface.stateForTesting() else {
                return false
            }
            return gridState["gridStyle"] as? String == "square"
                && (gridState["gridSpacing"] as? NSNumber)?.intValue
                    == 16
                && (gridState["backgroundCount"] as? NSNumber)?.intValue
                    == 0
                && gridState["derivedLayersAtBack"] as? Bool == true
                && gridState["exportIncludesGrid"] as? Bool == false
        }

        guard surface.insertImage(
            solidImage(
                color: .systemBlue,
                size: NSSize(width: 240, height: 120)
            )
        ) else {
            throw probeError("product tldraw rejected a pasted image")
        }
        try await waitUntil("product image undo") {
            guard let imageState = await surface.stateForTesting() else {
                return false
            }
            return surface.canUndo
                && (imageState["userImageCount"] as? NSNumber)?.intValue
                    == 1
                && (
                    imageState["selectedUserImageCount"] as? NSNumber
                )?.intValue == 0
                && imageState["selectedShapeCount"] as? NSNumber
                    == 0
                && imageState["selectedTool"] as? String == "draw"
                && imageState["productTool"] as? String == "pen"
                && imageState["derivedLayersAtBack"] as? Bool == true
        }
        guard userEditCount == 1 else {
            throw probeError(
                "image insertion reported \(userEditCount) edits"
            )
        }
        surface.undo()
        try await waitUntil("product image removed") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["shapeCount"] as? NSNumber)?.intValue == 2
                && surface.canRedo
        }
        surface.redo()
        try await waitUntil("product image restored") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["shapeCount"] as? NSNumber)?.intValue == 3
        }
        guard userEditCount == 1 else {
            throw probeError(
                "image undo/redo reported \(userEditCount) edits"
            )
        }
        let style = TraceToolState(
            color: .red,
            brush: .pen,
            penWidth: 5,
            gridStyle: .none,
            gridSpacingPoints: TraceGridPolicy.defaultSpacingPoints
        )
        surface.apply(
            TraceAnnotationUpdate(
                strokeID: 42,
                style: style,
                committed: [
                    TraceDrawingPoint(
                        x: 0.2,
                        y: 0.2,
                        pressure: 0.45,
                        tiltX: nil,
                        tiltY: nil,
                        twistDegrees: nil,
                        connectsToPrevious: false
                    ),
                    TraceDrawingPoint(
                        x: 0.7,
                        y: 0.6,
                        pressure: 0.7,
                        tiltX: nil,
                        tiltY: nil,
                        twistDegrees: nil,
                        connectsToPrevious: true
                    ),
                ],
                predicted: [],
                replacement: nil,
                isFinal: true
            )
        )
        try await waitUntil("product shapes and snapshot") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            let shapeCount =
                (state["shapeCount"] as? NSNumber)?.intValue ?? 0
            return shapeCount >= 4 && !snapshots.isEmpty
        }
        guard let snapshot = await surface.snapshotForTesting(),
              !snapshot.isEmpty,
              !snapshot.contains("trace-background-"),
              snapshot.contains("trace-image-")
        else {
            throw probeError(
                "product tldraw snapshot did not filter derived assets"
            )
        }
        document.manifest.strokes.append(
            TraceDrawingStroke(
                id: 42,
                color: .red,
                brush: .pen,
                width: 5,
                points: [
                    TraceDrawingPoint(
                        x: 0.2,
                        y: 0.2,
                        pressure: 0.45,
                        tiltX: nil,
                        tiltY: nil,
                        twistDegrees: nil,
                        connectsToPrevious: false
                    ),
                    TraceDrawingPoint(
                        x: 0.7,
                        y: 0.6,
                        pressure: 0.7,
                        tiltX: nil,
                        tiltY: nil,
                        twistDegrees: nil,
                        connectsToPrevious: true
                    ),
                ]
            )
        )
        document.manifest.strokes.append(
            TraceDrawingStroke(
                id: 43,
                color: .blue,
                brush: .pen,
                width: 5,
                points: [
                    TraceDrawingPoint(
                        x: 0.25,
                        y: 0.75,
                        pressure: 0.5,
                        tiltX: nil,
                        tiltY: nil,
                        twistDegrees: nil,
                        connectsToPrevious: false
                    ),
                    TraceDrawingPoint(
                        x: 0.75,
                        y: 0.25,
                        pressure: 0.5,
                        tiltX: nil,
                        tiltY: nil,
                        twistDegrees: nil,
                        connectsToPrevious: true
                    ),
                ]
            )
        )
        document.tldrawSnapshotJSON = snapshot
        surface.setDocument(document, toolState: tool)
        try await waitUntil("product snapshot reopen") {
            guard let reopenedState = await surface.stateForTesting() else {
                return false
            }
            return (
                (reopenedState["shapeCount"] as? NSNumber)?.intValue
                    ?? 0
            ) >= 5
                && (
                    reopenedState["lockedPenCount"] as? NSNumber
                )?.intValue == 3
                && (
                    reopenedState["userImageCount"] as? NSNumber
                )?.intValue == 1
                && reopenedState["derivedLayersAtBack"] as? Bool == true
        }
        guard let image = await surface.exportImageForTesting(
                  pixelRatio: 1
              ),
              bitmapDimensions(image) == NSSize(
                  width: 1_024,
                  height: 720
              )
        else {
            throw probeError(
                "product tldraw export did not preserve base dimensions"
            )
        }
        let backgroundPixel = bitmapColor(
            image,
            x: 2,
            y: 2
        )
        guard let backgroundPixel,
              backgroundPixel.redComponent > 0.85,
              backgroundPixel.greenComponent < 0.40,
              backgroundPixel.blueComponent < 0.35
        else {
            throw probeError(
                "product tldraw export lost the native background: "
                    + "\(String(describing: backgroundPixel))"
            )
        }
        guard await surface.setExportFixtureForTesting("masked"),
              let maskedImage =
                  await surface.exportImageForTesting(pixelRatio: 1),
              bitmapDimensions(maskedImage) == NSSize(
                  width: 1_024,
                  height: 720
              )
        else {
            throw probeError(
                "masked child geometry incorrectly expanded export"
            )
        }
        guard await surface.setExportFixtureForTesting("rotated"),
              let rotatedImage =
                  await surface.exportImageForTesting(pixelRatio: 1),
              let rotatedDimensions = bitmapDimensions(rotatedImage),
              rotatedDimensions.width == 1_072,
              rotatedDimensions.height > 820,
              let rotatedState = await surface.stateForTesting(),
              let rotatedPlan =
                  rotatedState["lastExportPlan"] as? [String: Any],
              rotatedPlan["didOverflowBase"] as? Bool == true
        else {
            throw probeError(
                "rotated rendered geometry did not expand export"
            )
        }
        guard await surface.setExportFixtureForTesting("none") else {
            throw probeError("could not clear export geometry fixture")
        }
        guard await surface.setFirstUserImagePositionForTesting(
                  x: 1_100,
                  y: 100
              ),
              let overflowImage = await surface.exportImageForTesting(
                  pixelRatio: 1
              ),
              bitmapDimensions(overflowImage) == NSSize(
                  width: 1_388,
                  height: 768
              ),
              let overflowState = await surface.stateForTesting(),
              let overflowPlan =
                  overflowState["lastExportPlan"] as? [String: Any],
              overflowPlan["didOverflowBase"] as? Bool == true,
              let overflowBounds =
                  overflowPlan["logicalBounds"] as? [String: Any],
              (overflowBounds["x"] as? NSNumber)?.doubleValue == -24,
              (overflowBounds["y"] as? NSNumber)?.doubleValue == -24,
              (overflowBounds["width"] as? NSNumber)?.doubleValue
                  == 1_388,
              (overflowBounds["height"] as? NSNumber)?.doubleValue
                  == 768,
              let overflowBackground = bitmapColor(
                  overflowImage,
                  x: 2,
                  y: 2
              ),
              overflowBackground.redComponent > 0.85,
              overflowBackground.greenComponent < 0.40,
              overflowBackground.blueComponent < 0.35
        else {
            throw probeError(
                "product tldraw export did not include overflow "
                    + "with symmetric background padding"
            )
        }
        guard await surface.setZoomForTesting(2),
              let zoomedOverflowImage =
                  await surface.exportImageForTesting(pixelRatio: 1),
              bitmapDimensions(zoomedOverflowImage)
                  == bitmapDimensions(overflowImage)
        else {
            throw probeError(
                "camera zoom changed product export dimensions"
            )
        }
        guard let commandDown = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: "Meta",
                  code: "MetaLeft",
                  metaKey: true
              ),
              commandDown["selectedTool"] as? String == "select",
              commandDown["productTool"] as? String == "highlighter"
        else {
            throw probeError(
                "Command did not temporarily activate Select"
            )
        }
        try await waitUntil("temporary toolbar Select") {
            temporaryTools.last == "select"
        }
        guard let commandUp = await surface.keyboardEventForTesting(
                  type: "keyup",
                  key: "Meta",
                  code: "MetaLeft"
              ),
              commandUp["selectedTool"] as? String == "draw"
        else {
            throw probeError(
                "Command did not temporarily activate Select"
            )
        }
        try await waitUntil("restored toolbar tool") {
            temporaryTools.last == "none"
        }
        let previewEventCount = temporaryTools.count
        guard let latchedCommandDown =
                await surface.keyboardEventForTesting(
                    type: "keydown",
                    key: "Meta",
                    code: "MetaLeft",
                    metaKey: true
                ),
              latchedCommandDown["selectedTool"] as? String
                == "select",
              await surface.selectFirstUserShapeForTesting(),
              let latchedCommandUp =
                await surface.keyboardEventForTesting(
                    type: "keyup",
                    key: "Meta",
                    code: "MetaLeft"
                )
        else {
            throw probeError(
                "Command selection did not select a user shape"
            )
        }
        _ = latchedCommandUp
        try await waitUntil("latched temporary Select") {
            guard let latchedState = await surface.stateForTesting()
            else {
                return false
            }
            return latchedState["selectedTool"] as? String == "select"
                && (
                    latchedState["selectedShapeCount"] as? NSNumber
                )?.intValue == 1
                && temporaryTools.count == previewEventCount + 1
                && temporaryTools.last == "select"
        }
        let latchedResumePreviewCount = temporaryTools.count
        guard let resumedDrawDown =
                await surface.keyboardEventForTesting(
                    type: "keydown",
                    key: "Meta",
                    code: "MetaLeft",
                    metaKey: true
                ),
              resumedDrawDown["selectedTool"] as? String == "draw",
              resumedDrawDown["productTool"] as? String == "highlighter",
              let resumedDrawUp =
                await surface.keyboardEventForTesting(
                    type: "keyup",
                    key: "Meta",
                    code: "MetaLeft"
                ),
              resumedDrawUp["selectedTool"] as? String == "draw"
        else {
            throw probeError(
                "Command did not restore the persistent Draw tool "
                    + "from latched Select"
            )
        }
        try await waitUntil("restored persistent Draw from latched Select") {
            guard let state = await surface.stateForTesting()
            else {
                return false
            }
            return state["selectedTool"] as? String == "draw"
                && (
                    state["selectedShapeCount"] as? NSNumber
                )?.intValue == 0
                && temporaryTools.count == latchedResumePreviewCount + 1
                && temporaryTools.last == "none"
        }
        guard let secondLatchedCommandDown =
                await surface.keyboardEventForTesting(
                    type: "keydown",
                    key: "Meta",
                    code: "MetaLeft",
                    metaKey: true
                ),
              secondLatchedCommandDown["selectedTool"] as? String
                == "select",
              await surface.selectFirstUserShapeForTesting(),
              let secondLatchedCommandUp =
                await surface.keyboardEventForTesting(
                    type: "keyup",
                    key: "Meta",
                    code: "MetaLeft"
                )
        else {
            throw probeError(
                "Command could not re-enter temporary Select"
            )
        }
        _ = secondLatchedCommandUp
        try await waitUntil("second latched temporary Select") {
            guard let state = await surface.stateForTesting()
            else {
                return false
            }
            return state["selectedTool"] as? String == "select"
                && (
                    state["selectedShapeCount"] as? NSNumber
                )?.intValue == 1
                && temporaryTools.last == "select"
        }
        guard await surface.emitPointerForTesting(
                  phase: "began",
                  x: 0.95,
                  y: 0.95
              ),
              await surface.emitPointerForTesting(
                  phase: "ended",
                  x: 0.95,
                  y: 0.95
              )
        else {
            throw probeError(
                "empty-canvas deselection events were rejected"
            )
        }
        try await waitUntil("released latched Select") {
            guard let releasedState = await surface.stateForTesting()
            else {
                return false
            }
            return releasedState["selectedTool"] as? String == "draw"
                && (
                    releasedState["selectedShapeCount"] as? NSNumber
                )?.intValue == 0
                && temporaryTools.last == "none"
        }
        guard let selectKey = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: "v",
                  code: "KeyV"
              ),
              selectKey["selectedTool"] as? String == "select",
              selectKey["productTool"] as? String == "select",
              await surface.selectFirstUserShapeForTesting(),
              let selectedImageState = await surface.stateForTesting(),
              (
                  selectedImageState["selectedUserImageCount"]
                      as? NSNumber
              )?.intValue == 1
        else {
            throw probeError(
                "V did not persistently select a user image"
            )
        }
        let drawCountBeforeTemporaryDraw =
            (selectedImageState["drawWidths"] as? [NSNumber])?.count
                ?? 0
        let selectToDrawPreviewCount = temporaryTools.count
        guard let temporaryDrawDown =
                await surface.keyboardEventForTesting(
                    type: "keydown",
                    key: "Meta",
                    code: "MetaLeft",
                    metaKey: true
                ),
              temporaryDrawDown["selectedTool"] as? String == "draw",
              temporaryDrawDown["productTool"] as? String == "select"
        else {
            throw probeError(
                "Command did not temporarily activate Draw from Select"
            )
        }
        try await waitUntil("temporary Draw clears selected image") {
            guard let state = await surface.stateForTesting()
            else {
                return false
            }
            return state["selectedTool"] as? String == "draw"
                && (
                    state["selectedUserImageCount"] as? NSNumber
                )?.intValue == 0
                && (
                    state["selectedShapeCount"] as? NSNumber
                )?.intValue == 0
                && temporaryTools.count == selectToDrawPreviewCount + 1
                && temporaryTools.last == "highlighter"
        }
        guard await surface.emitPointerForTesting(
                  phase: "began",
                  x: 0.5,
                  y: 0.5
              ),
              await surface.emitPointerForTesting(
                  phase: "moved",
                  x: 0.55,
                  y: 0.55
              ),
              await surface.emitPointerForTesting(
                  phase: "ended",
                  x: 0.6,
                  y: 0.6
              ),
              let temporaryDrawUp =
                await surface.keyboardEventForTesting(
                    type: "keyup",
                    key: "Meta",
                    code: "MetaLeft"
                ),
              temporaryDrawUp["selectedTool"] as? String == "select"
        else {
            throw probeError(
                "temporary Draw from Select did not accept pointer input"
            )
        }
        try await waitUntil("temporary Draw restored Select") {
            guard let state = await surface.stateForTesting()
            else {
                return false
            }
            let drawCount =
                (state["drawWidths"] as? [NSNumber])?.count ?? 0
            return state["selectedTool"] as? String == "select"
                && state["productTool"] as? String == "select"
                && drawCount > drawCountBeforeTemporaryDraw
                && (state["drawColors"] as? [String])?.last
                    == "light-green"
                && temporaryTools.last == "none"
        }
        guard let rectangleKey = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: "r",
                  code: "KeyR"
              ),
              rectangleKey["defaultPrevented"] as? Bool == true,
              rectangleKey["selectedTool"] as? String == "geo",
              rectangleKey["productTool"] as? String == "rectangle"
        else {
            throw probeError(
                "R did not select the rectangle tool"
            )
        }
        guard await surface.emitPointerForTesting(
                  phase: "began",
                  x: 0.25,
                  y: 0.25
              ),
              await surface.emitPointerForTesting(
                  phase: "moved",
                  x: 0.65,
                  y: 0.55
              ),
              await surface.emitPointerForTesting(
                  phase: "ended",
                  x: 0.65,
                  y: 0.55
              )
        else {
            throw probeError(
                "product rectangle pointer events were rejected"
            )
        }
        try await waitUntil("product rectangle") {
            guard let rectangleState = await surface.stateForTesting() else {
                return false
            }
            return (
                rectangleState["rectangleCount"] as? NSNumber
            )?.intValue == 1
                && rectangleState["selectedTool"] as? String == "geo"
                && rectangleState["productTool"] as? String == "rectangle"
                && (
                    rectangleState["selectedShapeCount"] as? NSNumber
                )?.intValue == 0
                && shortcutTools.last == .rectangle
                && (
                    rectangleState["timedShapeCount"] as? NSNumber
                )?.intValue == 1
                && latestTimedShapes.count == 1
                && latestTimedShapes[0]
                    .endedAtAppClockSeconds
                    >= latestTimedShapes[0]
                        .startedAtAppClockSeconds
                && latestTimedShapes[0].pathLength > 0
        }
        await surface.setTimingFinalizationDelayForTesting(80)
        guard let drawKey = await surface.keyboardEventForTesting(
                  type: "keydown",
                  key: "d",
                  code: "KeyD"
              ),
              drawKey["selectedTool"] as? String == "draw",
              await surface.emitPointerForTesting(
                  phase: "began",
                  x: 0.72,
                  y: 0.2
              ),
              await surface.emitPointerForTesting(
                  phase: "moved",
                  x: 0.82,
                  y: 0.3
              ),
              await surface.emitPointerForTesting(
                  phase: "ended",
                  x: 0.88,
                  y: 0.42
              )
        else {
            throw probeError(
                "product freehand pointer events were rejected"
            )
        }
        let timingFlushStartedAt = Date()
        await withCheckedContinuation { continuation in
            surface.flushSnapshot {
                continuation.resume()
            }
        }
        await surface.setTimingFinalizationDelayForTesting(0)
        guard Date().timeIntervalSince(timingFlushStartedAt) >= 0.06,
              latestTimedShapes.count == 2
        else {
            throw probeError(
                "snapshot flush did not wait for gesture timing"
            )
        }
        var timedFreehandState: [String: Any]?
        for _ in 0..<500 {
            timedFreehandState = await surface.stateForTesting()
            if (
                timedFreehandState?["timedShapeCount"] as? NSNumber
            )?.intValue == 2 {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard (
            timedFreehandState?["timedShapeCount"] as? NSNumber
        )?.intValue == 2 else {
            throw probeError(
                "timed freehand shape was missing: "
                    + "\(String(describing: timedFreehandState))"
            )
        }
        try await waitUntil("timed freehand WebKit bridge") {
            latestTimedShapes.count == 2
        }
        let orderedTimedShapes = latestTimedShapes.sorted {
            $0.startedAtAppClockSeconds
                < $1.startedAtAppClockSeconds
        }
        model.receiveTranscriptForTesting(
            TraceVoiceTranscriptSnapshot(
                text: "Rectangle stroke.",
                words: [
                    TraceTimedTranscriptionWord(
                        text: "Rectangle",
                        startedAtAppClockSeconds:
                            orderedTimedShapes[0]
                                .startedAtAppClockSeconds - 0.1,
                        endedAtAppClockSeconds:
                            orderedTimedShapes[0]
                                .endedAtAppClockSeconds + 0.1
                    ),
                    TraceTimedTranscriptionWord(
                        text: "stroke",
                        startedAtAppClockSeconds:
                            orderedTimedShapes[1]
                                .startedAtAppClockSeconds - 0.1,
                        endedAtAppClockSeconds:
                            orderedTimedShapes[1]
                                .endedAtAppClockSeconds + 0.1
                    ),
                ]
            )
        )
        for _ in 0..<500 where (
            document.manifest.timedCanvasShapes ?? []
        ).compactMap(\.transcriptAnnotation).count != 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard (
            document.manifest.timedCanvasShapes ?? []
        ).compactMap(\.transcriptAnnotation).count == 2,
              model.formattedTranscriptForTesting()
                == "Rectangle [4] stroke [5]."
        else {
            throw probeError(
                "timed shape model annotation failed: "
                    + "\(String(describing: document.manifest.timedCanvasShapes)), "
                    + "\(model.formattedTranscriptForTesting() ?? "nil")"
            )
        }
        try await waitUntil("timed shape renderer annotation") {
            guard let timedState = await surface.stateForTesting()
            else {
                return false
            }
            return (
                timedState["timedAnnotationCount"] as? NSNumber
            )?.intValue == 2
                && Set(
                    timedState["timedAnnotationTexts"] as? [String]
                        ?? []
                ) == Set(["4", "5"])
                && (
                    document.manifest.timedCanvasShapes ?? []
                ).compactMap(\.transcriptAnnotation).sorted {
                    $0.id < $1.id
                } == [
                    TraceTranscriptAnnotation(id: 4, wordID: 1),
                    TraceTranscriptAnnotation(id: 5, wordID: 2),
                ]
        }
        for shortcut in [
            ("v", "KeyV", TraceCanvasTool.select, "select"),
            ("d", "KeyD", TraceCanvasTool.pen, "draw"),
            ("h", "KeyH", TraceCanvasTool.highlighter, "draw"),
        ] {
            guard let keyState = await surface.keyboardEventForTesting(
                      type: "keydown",
                      key: shortcut.0,
                      code: shortcut.1
                  ),
                  keyState["defaultPrevented"] as? Bool == true,
                  keyState["selectedTool"] as? String == shortcut.3
            else {
                throw probeError(
                    "\(shortcut.0.uppercased()) did not select its tool"
                )
            }
            try await waitUntil("product tool shortcut") {
                shortcutTools.last == shortcut.2
            }
        }
        let cleanDocument = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Trace Probe",
                sourceWindowTitle: "Clean product tldraw",
                screenshotFileName: "clean-screenshot.png",
                screenshotPixelWidth: 640,
                screenshotPixelHeight: 480,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 640,
                    height: 480
                ),
                pageKind: .blank,
                backgroundColor: .blue,
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: solidImage(
                color: .systemBlue,
                size: NSSize(width: 640, height: 480)
            ),
            packageURL: directory
        )
        let progressiveBlankBoard = TraceBoardWindowController()
        progressiveBlankBoard.configureInvisibleProbeWindows()
        progressiveBlankBoard.prepareDocumentForPreview(
            cleanDocument,
            toolState: TraceToolState()
        )
        let initialBlankPresentation =
            progressiveBlankBoard.blankCanvasLoadingForPreview
        guard initialBlankPresentation.pending,
              !initialBlankPresentation.tldrawReady,
              initialBlankPresentation.tldrawAlpha == 0,
              !initialBlankPresentation.surfaceDisplaysScreenshot,
              (
                  initialBlankPresentation.rootBackgroundColor?
                      .usingColorSpace(.deviceRGB)?
                      .blueComponent ?? 0
              ) > 0.9,
              !initialBlankPresentation.toolbarPresented,
              !initialBlankPresentation.toolbarRevealAnimated
        else {
            throw probeError(
                "blank canvas did not present its native background first: "
                    + "\(initialBlankPresentation)"
            )
        }
        try await waitUntil("progressive blank tldraw reveal") {
            let presentation =
                progressiveBlankBoard.blankCanvasLoadingForPreview
            return !presentation.pending
                && presentation.tldrawReady
                && presentation.tldrawAlpha == 1
                && presentation.toolbarPresented
                && presentation.toolbarRevealAnimated
        }
        progressiveBlankBoard.hideBoard()
        surface.setDocument(cleanDocument, toolState: TraceToolState())
        try await waitUntil("clean product document") {
            guard let cleanState = await surface.stateForTesting() else {
                return false
            }
            return (
                cleanState["userImageCount"] as? NSNumber
            )?.intValue == 0
                && cleanState["derivedLayersAtBack"] as? Bool == true
        }
        guard let cleanSnapshot = await surface.snapshotForTesting(),
              !cleanSnapshot.contains("trace-image-")
        else {
            throw probeError(
                "new document retained an older image asset"
            )
        }
        guard await surface.dropImageForTesting(
            solidImage(
                color: .systemPurple,
                size: NSSize(width: 64, height: 64)
            ),
            delayMilliseconds: 150
        ) else {
            throw probeError("product tldraw rejected a test image drop")
        }
        let dropFlushStartedAt = Date()
        await withCheckedContinuation { continuation in
            surface.flushSnapshot {
                continuation.resume()
            }
        }
        let dropFlushDuration =
            Date().timeIntervalSince(dropFlushStartedAt)
        let droppedState = await surface.stateForTesting()
        let droppedImageCount = (
            droppedState?["userImageCount"] as? NSNumber
        )?.intValue
        guard dropFlushDuration >= 0.1,
              droppedImageCount == 1,
              (
                  droppedState?["selectedShapeCount"] as? NSNumber
              )?.intValue == 0,
              droppedState?["selectedTool"] as? String == "draw",
              droppedState?["productTool"] as? String == "pen"
        else {
            throw probeError(
                "snapshot flush did not wait for an image drop: "
                    + "\(dropFlushDuration)s, "
                    + "\(droppedImageCount ?? -1) images"
            )
        }
        let batchDocument = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Finder",
                sourceWindowTitle: "Open With",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: 900,
                screenshotPixelHeight: 650,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 900,
                    height: 650
                ),
                pageKind: .blank,
                backgroundColor: TraceRGBAColor(
                    red: 1,
                    green: 1,
                    blue: 1
                ),
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: solidImage(
                color: .white,
                size: NSSize(width: 900, height: 650)
            ),
            packageURL: directory
        )
        surface.setDocument(
            batchDocument,
            toolState: TraceToolState()
        )
        let batchEditBaseline = userEditCount
        guard surface.insertImages([
            TraceCanvasImage(
                image: solidImage(
                    color: .systemRed,
                    size: NSSize(width: 320, height: 180)
                ),
                name: "one.png"
            ),
            TraceCanvasImage(
                image: solidImage(
                    color: .systemGreen,
                    size: NSSize(width: 200, height: 300)
                ),
                name: "two.jpg"
            ),
            TraceCanvasImage(
                image: solidImage(
                    color: .systemBlue,
                    size: NSSize(width: 400, height: 200)
                ),
                name: "three.png"
            ),
        ]) else {
            throw probeError(
                "product tldraw rejected an Open With image batch"
            )
        }
        try await waitUntil("Open With image batch") {
            guard let batchState = await surface.stateForTesting(),
                  let frames =
                    batchState["userImageBounds"] as? [[String: Any]]
            else {
                return false
            }
            return (
                batchState["userImageCount"] as? NSNumber
            )?.intValue == 3
                && (
                    batchState["selectedUserImageCount"] as? NSNumber
                )?.intValue == 0
                && (
                    batchState["selectedShapeCount"] as? NSNumber
                )?.intValue == 0
                && batchState["selectedTool"] as? String == "draw"
                && batchState["productTool"] as? String == "pen"
                && frames.count == 3
                && framesDoNotOverlap(frames)
                && userEditCount == batchEditBaseline + 1
        }
        let screenshotDocument = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Trace Probe",
                sourceWindowTitle: "Screenshot product tldraw",
                screenshotFileName: "screenshot-page.png",
                screenshotPixelWidth: 800,
                screenshotPixelHeight: 500,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 800,
                    height: 500
                ),
                pageKind: .screenshot,
                backgroundColor: .blue,
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: halfTransparentImage(
                color: .systemTeal,
                size: NSSize(width: 800, height: 500)
            ),
            packageURL: directory
        )
        surface.setDocument(
            screenshotDocument,
            toolState: TraceToolState()
        )
        surface.setFrameSize(NSSize(width: 800, height: 500))
        surface.layoutSubtreeIfNeeded()
        try await waitUntil("screenshot product document") {
            guard let screenshotState =
                    await surface.stateForTesting()
            else {
                return false
            }
            return (
                screenshotState["backgroundCount"] as? NSNumber
            )?.intValue == 0
                && (
                    screenshotState["renderedBackgroundColor"] as? String
                )?.contains("26, 110, 245") == true
                && (
                    screenshotState["userImageCount"] as? NSNumber
                )?.intValue == 1
                && (
                    screenshotState["pageWidth"] as? NSNumber
                )?.intValue == 800
                && (
                    screenshotState["pageHeight"] as? NSNumber
                )?.intValue == 500
        }
        try await waitUntil("screenshot final viewport framing") {
            guard let screenshotState =
                    await surface.stateForTesting(),
                  let bounds = (
                    screenshotState["userImageBounds"]
                        as? [[String: Any]]
                  )?.first
            else {
                return false
            }
            return (
                screenshotState["viewportWidth"] as? NSNumber
            )?.intValue == 800
                && (
                    screenshotState["viewportHeight"] as? NSNumber
                )?.intValue == 500
                && abs(
                    (
                        (
                            screenshotState["viewportCenterX"]
                                as? NSNumber
                        )?.doubleValue ?? -1
                    ) - 400
                ) < 0.5
                && abs(
                    (
                        (
                            screenshotState["viewportCenterY"]
                                as? NSNumber
                        )?.doubleValue ?? -1
                    ) - 250
                ) < 0.5
                && abs(
                    (
                        (
                            screenshotState["zoom"] as? NSNumber
                        )?.doubleValue ?? 0
                    ) - 1
                ) < 0.001
                && (bounds["x"] as? NSNumber)?.intValue == 0
                && (bounds["y"] as? NSNumber)?.intValue == 0
                && (bounds["width"] as? NSNumber)?.intValue == 800
                && (bounds["height"] as? NSNumber)?.intValue == 500
        }
        if let path = ProcessInfo.processInfo.environment[
            "TRACE_FIRST_CAPTURE_ALIGNMENT_SNAPSHOT"
        ] {
            try await surface.writeSnapshotForTesting(
                to: URL(fileURLWithPath: path)
            )
        }
        guard await surface.selectFirstUserShapeForTesting() else {
            throw probeError(
                "captured screenshot was not selectable"
            )
        }
        try await waitUntil("captured screenshot selection") {
            guard let screenshotState =
                    await surface.stateForTesting()
            else {
                return false
            }
            return (
                    screenshotState["selectedUserImageCount"]
                        as? NSNumber
                )?.intValue == 1
        }
        guard await surface.setFirstUserImagePositionForTesting(
                  x: 24,
                  y: 36
              )
        else {
            throw probeError(
                "captured screenshot could not be moved"
            )
        }
        try await waitUntil("captured screenshot move") {
            guard let screenshotState =
                    await surface.stateForTesting(),
                  let bounds = (
                    screenshotState["userImageBounds"]
                        as? [[String: Any]]
                  )?.first
            else {
                return false
            }
            return (bounds["x"] as? NSNumber)?.intValue == 24
                && (bounds["y"] as? NSNumber)?.intValue == 36
        }
        guard let movedScreenshotSnapshot =
                await surface.snapshotForTesting(),
              movedScreenshotSnapshot.contains("trace-image-capture-"),
              movedScreenshotSnapshot.contains(
                "traceCaptureImageMigrated"
              ),
              !movedScreenshotSnapshot.contains("trace-background-")
        else {
            throw probeError(
                "captured screenshot transform was not persisted"
            )
        }
        screenshotDocument.tldrawSnapshotJSON = movedScreenshotSnapshot
        surface.setDocument(
            screenshotDocument,
            toolState: TraceToolState()
        )
        try await waitUntil("moved captured screenshot reopen") {
            guard let screenshotState =
                    await surface.stateForTesting(),
                  let bounds = (
                    screenshotState["userImageBounds"]
                        as? [[String: Any]]
                  )?.first
            else {
                return false
            }
            return (
                screenshotState["backgroundCount"] as? NSNumber
            )?.intValue == 0
                && (
                    screenshotState["userImageCount"] as? NSNumber
                )?.intValue == 1
                && (bounds["x"] as? NSNumber)?.intValue == 24
                && (bounds["y"] as? NSNumber)?.intValue == 36
                && (
                    screenshotState["pageWidth"] as? NSNumber
                )?.intValue == 800
                && (
                    screenshotState["pageHeight"] as? NSNumber
                )?.intValue == 500
        }
        surface.setBackgroundColor(.red)
        screenshotDocument.manifest.backgroundColor = .red
        guard let movedScreenshotExport =
                await surface.exportImageForTesting(pixelRatio: 1),
              bitmapDimensions(movedScreenshotExport) == NSSize(
                  width: 1_080,
                  height: 792
              ),
              let oldOnlyPixel = bitmapColor(
                  movedScreenshotExport,
                  x: 538,
                  y: 378
              ),
              oldOnlyPixel.redComponent > 0.85,
              oldOnlyPixel.greenComponent < 0.40,
              oldOnlyPixel.blueComponent < 0.35,
              let movedPixel = bitmapColor(
                  movedScreenshotExport,
                  x: 568,
                  y: 378
              ),
              movedPixel.greenComponent > 0.35,
              movedPixel.blueComponent > 0.35
        else {
            throw probeError(
                "moved screenshot export duplicated or lost the capture"
            )
        }
        guard await surface.selectFirstUserShapeForTesting()
        else {
            throw probeError(
                "reopened captured screenshot was not selectable"
            )
        }
        await surface.deleteSelectionForTesting()
        try await waitUntil("captured screenshot deletion") {
            guard let screenshotState =
                    await surface.stateForTesting()
            else {
                return false
            }
            return (
                screenshotState["userImageCount"] as? NSNumber
            )?.intValue == 0
                && (
                    screenshotState["backgroundCount"] as? NSNumber
                )?.intValue == 0
        }
        guard let deletedScreenshotSnapshot =
                await surface.snapshotForTesting(),
              !deletedScreenshotSnapshot.contains(
                  "shape:trace-image-capture-"
              ),
              deletedScreenshotSnapshot.contains(
                  "traceCaptureImageMigrated"
              ),
              let deletedScreenshotExport =
                  await surface.exportImageForTesting(pixelRatio: 1),
              bitmapDimensions(deletedScreenshotExport) == NSSize(
                  width: 800,
                  height: 500
              ),
              let deletedPixel = bitmapColor(
                  deletedScreenshotExport,
                  x: 700,
                  y: 250
              ),
              deletedPixel.redComponent > 0.85,
              deletedPixel.greenComponent < 0.40,
              deletedPixel.blueComponent < 0.35
        else {
            throw probeError(
                "deleted screenshot reappeared in persistence or export"
            )
        }
        screenshotDocument.tldrawSnapshotJSON = deletedScreenshotSnapshot
        surface.setDocument(
            screenshotDocument,
            toolState: TraceToolState()
        )
        try await waitUntil("deleted captured screenshot reopen") {
            guard let screenshotState =
                    await surface.stateForTesting()
            else {
                return false
            }
            return (
                screenshotState["userImageCount"] as? NSNumber
            )?.intValue == 0
                && (
                    screenshotState["backgroundCount"] as? NSNumber
                )?.intValue == 0
                && (
                    screenshotState["pageWidth"] as? NSNumber
                )?.intValue == 800
                && (
                    screenshotState["pageHeight"] as? NSNumber
                )?.intValue == 500
        }
        let legacyScreenshotDocument = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Trace Probe",
                sourceWindowTitle: "Legacy screenshot product tldraw",
                screenshotFileName: "legacy-screenshot-page.png",
                screenshotPixelWidth: 800,
                screenshotPixelHeight: 500,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 800,
                    height: 500
                ),
                pageKind: .screenshot,
                backgroundColor: .red,
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: halfTransparentImage(
                color: .systemTeal,
                size: NSSize(width: 800, height: 500)
            ),
            tldrawSnapshotJSON: cleanSnapshot,
            packageURL: directory
        )
        surface.setDocument(
            legacyScreenshotDocument,
            toolState: TraceToolState()
        )
        try await waitUntil("legacy screenshot migration") {
            guard let legacyState = await surface.stateForTesting()
            else {
                return false
            }
            return (
                legacyState["backgroundCount"] as? NSNumber
            )?.intValue == 0
                && (
                    legacyState["userImageCount"] as? NSNumber
                )?.intValue == 1
        }
        guard let migratedLegacySnapshot =
                await surface.snapshotForTesting(),
              migratedLegacySnapshot.contains(
                  "shape:trace-image-capture-"
              ),
              migratedLegacySnapshot.contains(
                  "traceCaptureImageMigrated"
              )
        else {
            throw probeError(
                "legacy screenshot did not migrate to a persisted image"
            )
        }
        let croppedScreenshotDocument = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Trace Probe",
                sourceWindowTitle: "Cropped screenshot export",
                screenshotFileName: "cropped-screenshot.png",
                screenshotPixelWidth: 800,
                screenshotPixelHeight: 500,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 800,
                    height: 500
                ),
                pageKind: .screenshot,
                backgroundColor: .red,
                viewport: TraceRect(
                    x: 0.25,
                    y: 0.25,
                    width: 0.5,
                    height: 0.5
                ),
                strokes: []
            ),
            screenshot: solidImage(
                color: .systemGreen,
                size: NSSize(width: 800, height: 500)
            ),
            packageURL: directory
        )
        surface.setDocument(
            croppedScreenshotDocument,
            toolState: TraceToolState()
        )
        try await waitUntil("cropped screenshot export document") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["pageWidth"] as? NSNumber)?.intValue == 400
                && (state["pageHeight"] as? NSNumber)?.intValue == 250
        }
        guard let croppedScreenshotExport =
                await surface.exportImageForTesting(pixelRatio: 2),
              bitmapDimensions(croppedScreenshotExport) == NSSize(
                  width: 800,
                  height: 500
              ),
              abs(croppedScreenshotExport.size.width - 400) < 0.5,
              abs(croppedScreenshotExport.size.height - 250) < 0.5
        else {
            throw probeError(
                "cropped screenshot export lost its fixed base bounds"
            )
        }
        let resizingBlank = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Trace Probe",
                sourceWindowTitle: "Calibrated blank",
                screenshotFileName: "calibrated-blank.png",
                screenshotPixelWidth: 900,
                screenshotPixelHeight: 650,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 900,
                    height: 650
                ),
                pageKind: .blank,
                backgroundColor: .blue,
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: solidImage(
                color: .blue,
                size: NSSize(width: 900, height: 650)
            ),
            packageURL: directory
        )
        surface.setDocument(
            resizingBlank,
            toolState: TraceToolState()
        )
        try await waitUntil("calibration resize source document") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["pageWidth"] as? NSNumber)?.intValue == 900
                && (state["pageHeight"] as? NSNumber)?.intValue == 650
        }
        guard surface.insertImage(
            solidImage(
                color: .systemGreen,
                size: NSSize(width: 180, height: 120)
            )
        ) else {
            throw probeError(
                "calibration resize probe could not insert user content"
            )
        }
        try await waitUntil("calibration resize user content") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["userImageCount"] as? NSNumber)?.intValue == 1
        }
        guard let beforeCalibrationResize =
                await surface.stateForTesting(),
              let beforeBounds =
                (
                    beforeCalibrationResize["userImageBounds"]
                        as? [[String: Any]]
                )?.first,
              let snapshot = await surface.snapshotForTesting()
        else {
            throw probeError(
                "calibration resize probe could not capture user placement"
            )
        }
        resizingBlank.tldrawSnapshotJSON = snapshot
        resizingBlank.manifest.sourceWindowBounds = TraceRect(
            x: 0,
            y: 0,
            width: 630,
            height: 900
        )
        surface.setDocument(
            resizingBlank,
            toolState: TraceToolState()
        )
        try await waitUntil("normalized calibration resize") {
            guard let state = await surface.stateForTesting(),
                  (state["pageWidth"] as? NSNumber)?.intValue == 630,
                  (state["pageHeight"] as? NSNumber)?.intValue == 900,
                  let afterBounds =
                    (
                        state["userImageBounds"] as? [[String: Any]]
                    )?.first
            else {
                return false
            }
            let beforeCenterX =
                ((beforeBounds["x"] as? NSNumber)?.doubleValue ?? -1)
                + (
                    (beforeBounds["width"] as? NSNumber)?.doubleValue
                        ?? 0
                ) / 2
            let beforeCenterY =
                ((beforeBounds["y"] as? NSNumber)?.doubleValue ?? -1)
                + (
                    (beforeBounds["height"] as? NSNumber)?.doubleValue
                        ?? 0
                ) / 2
            let afterCenterX =
                ((afterBounds["x"] as? NSNumber)?.doubleValue ?? -1)
                + (
                    (afterBounds["width"] as? NSNumber)?.doubleValue
                        ?? 0
                ) / 2
            let afterCenterY =
                ((afterBounds["y"] as? NSNumber)?.doubleValue ?? -1)
                + (
                    (afterBounds["height"] as? NSNumber)?.doubleValue
                        ?? 0
                ) / 2
            return abs(beforeCenterX / 900 - afterCenterX / 630) < 0.01
                && abs(beforeCenterY / 650 - afterCenterY / 900) < 0.01
        }
        let largeBlankDocument = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Trace Probe",
                sourceWindowTitle: "Large blank export",
                screenshotFileName: "large-blank.png",
                screenshotPixelWidth: 4_000,
                screenshotPixelHeight: 2_000,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 4_000,
                    height: 2_000
                ),
                pageKind: .blank,
                backgroundColor: .red,
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: solidImage(
                color: .white,
                size: NSSize(width: 4_000, height: 2_000)
            ),
            packageURL: directory
        )
        surface.setDocument(
            largeBlankDocument,
            toolState: TraceToolState()
        )
        try await waitUntil("large blank export document") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["shapeCount"] as? NSNumber)?.intValue == 0
                && (state["pageWidth"] as? NSNumber)?.intValue == 4_000
                && (state["pageHeight"] as? NSNumber)?.intValue == 2_000
        }
        guard let reducedImage =
                await surface.exportImageForTesting(pixelRatio: 2),
              bitmapDimensions(reducedImage) == NSSize(
                  width: 4_898,
                  height: 2_449
              ),
              let reducedState = await surface.stateForTesting(),
              let reducedPlan =
                  reducedState["lastExportPlan"] as? [String: Any],
              reducedPlan["didReduceResolution"] as? Bool == true,
              (
                  (reducedPlan["pixelWidth"] as? NSNumber)?.intValue
                      ?? 0
              ) * (
                  (reducedPlan["pixelHeight"] as? NSNumber)?.intValue
                      ?? 0
              ) <= 12_000_000,
              let reducedBackground = bitmapColor(
                  reducedImage,
                  x: 2,
                  y: 2
              ),
              reducedBackground.redComponent > 0.85
        else {
            throw probeError(
                "large blank export did not reduce to the exact "
                    + "12MP raster plan"
            )
        }
        let board = TraceBoardWindowController()
        var boardTool = TraceToolState()
        boardTool.canvasTool = .select
        var synchronizedBoardTool: TraceToolState?
        board.onToolChange = {
            synchronizedBoardTool = $0
        }
        board.prepareDocumentForPreview(
            screenshotDocument,
            toolState: boardTool
        )
        guard board.insertImage(
            solidImage(
                color: .systemOrange,
                size: NSSize(width: 120, height: 80)
            )
        ) else {
            throw probeError(
                "screenshot board rejected a pasted user image"
            )
        }
        try await waitUntil("screenshot board image tool reset") {
            guard let state = await board.productCanvasStateForPreview()
            else {
                return false
            }
            return state["selectedTool"] as? String == "draw"
                && state["productTool"] as? String == "pen"
                && (
                    state["selectedShapeCount"] as? NSNumber
                )?.intValue == 0
                && synchronizedBoardTool?.canvasTool == .pen
                && synchronizedBoardTool?.brush == .pen
                && board.drawingToolPresentationForPreview
                    .selectedSegment == 1
        }
        let rendererState = board.productRendererStateForPreview
        guard !rendererState.nativeLayersAttached,
              rendererState.tldrawAttached,
              !rendererState.surfaceDisplaysScreenshot
        else {
            throw probeError(
                "the product board still attached native fallback layers"
            )
        }
        board.showProductRendererErrorForPreview(
            "Synthetic board failure"
        )
        let failedRendererState = board.productRendererStateForPreview
        guard !failedRendererState.nativeLayersAttached,
              !failedRendererState.surfaceDisplaysScreenshot,
              failedRendererState.tldrawErrorVisible
        else {
            throw probeError(
                "the product board hid its tldraw failure"
            )
        }
        board.hideBoard()
        try await verifyTextEditing(surface, document: cleanDocument)
        try await verifyIndependentStrokeWidths(surface)
        try await verifySelectionCopy(surface)
        try await verifyCapturedScreenshotOpacity(surface, document: cleanDocument)
        surface.showErrorForTesting("Synthetic bridge failure")
        let errorPresentation = surface.errorPresentationForTesting
        guard errorPresentation.visible,
              errorPresentation.message
                .contains("Canvas unavailable"),
              errorPresentation.message
                .contains("Synthetic bridge failure")
        else {
            throw probeError(
                "tldraw failure did not surface an explicit error"
            )
        }
    }

    @MainActor
    private static func verifyOffCenterDocumentFraming(
        _ surface: TldrawProductCanvasView,
        directory: URL
    ) async throws {
        let document = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Trace Probe",
                sourceWindowTitle: "Off-center framing",
                screenshotFileName: "off-center.png",
                screenshotPixelWidth: 900,
                screenshotPixelHeight: 650,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 900,
                    height: 650
                ),
                pageKind: .blank,
                backgroundColor: TraceRGBAColor(
                    red: 1,
                    green: 1,
                    blue: 1
                ),
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: solidImage(
                color: .white,
                size: NSSize(width: 900, height: 650)
            ),
            packageURL: directory
        )
        surface.setDocument(document, toolState: TraceToolState())
        try await waitUntil("off-center framing document") {
            guard let state = await surface.stateForTesting() else {
                return false
            }
            return (state["shapeCount"] as? NSNumber)?.intValue == 0
                && (state["pageWidth"] as? NSNumber)?.intValue == 900
                && (state["pageHeight"] as? NSNumber)?.intValue == 650
        }
        guard surface.insertImage(
            solidImage(
                color: .systemBlue,
                size: NSSize(width: 240, height: 120)
            )
        ) else {
            throw probeError(
                "could not insert the off-center framing image"
            )
        }
        try await waitUntil("off-center framing image") {
            (await surface.stateForTesting()?["userImageCount"]
                as? NSNumber)?.intValue == 1
        }
        guard await surface.setFirstUserImagePositionForTesting(
                  x: 1_200,
                  y: 280
              )
        else {
            throw probeError(
                "could not move the off-center framing image"
            )
        }
        guard let snapshot = await surface.snapshotForTesting() else {
            throw probeError(
                "could not save the off-center framing fixture"
            )
        }
        document.tldrawSnapshotJSON = snapshot
        surface.setDocument(document, toolState: TraceToolState())
        try await waitUntil("off-center document framing") {
            guard let state = await surface.stateForTesting(),
                  let viewportCenterX = (
                    state["viewportCenterX"] as? NSNumber
                  )?.doubleValue,
                  let viewportCenterY = (
                    state["viewportCenterY"] as? NSNumber
                  )?.doubleValue
            else {
                return false
            }
            return abs(viewportCenterX - 1_320) < 0.5
                && abs(viewportCenterY - 340) < 0.5
        }
    }

    @MainActor
    private static func verifyTextEditing(
        _ surface: TldrawProductCanvasView,
        document: TraceDrawingSession
    ) async throws {
        var state = TraceToolState()
        state.canvasTool = .select
        state.brush = .highlighter
        surface.setDocument(document, toolState: state)
        try await waitUntil("text test document") {
            let value = await surface.stateForTesting()
            return value?["productTool"] as? String == "select"
                && (value?["pageWidth"] as? NSNumber)?.intValue
                    == document.manifest.screenshotPixelWidth
        }
        for _ in 0..<2 {
            guard await surface.emitPointerForTesting(
                      phase: "began", x: 0.8, y: 0.8
                  ),
                  await surface.emitPointerForTesting(
                      phase: "ended", x: 0.8, y: 0.8
                  )
            else {
                throw probeError("Could not double-click to create text")
            }
        }
        try await waitUntil("double-click text editing") {
            await surface.stateForTesting()?["isEditingText"] as? Bool == true
        }
        let firstText = "Text with spaces dhvrt"
        let typedText: String
        do {
            typedText = try await surface.typeTextForTesting(firstText)
        } catch {
            throw probeError("Double-click text input failed: \(error)")
        }
        guard typedText == firstText else {
            throw probeError("Double-click text did not preserve spaces")
        }
        let textCopy = try await surface.captureSelectionCopyForTesting(selectText: true)
        guard textCopy["handled"] as? Bool == true,
              (textCopy["events"] as? NSNumber)?.intValue == 1,
              textCopy["text"] as? String == "Text"
        else {
            throw probeError("Copy did not target only the selected text: \(textCopy)")
        }
        let caretCopy = try await surface.captureSelectionCopyForTesting()
        guard caretCopy["handled"] as? Bool == true,
              (caretCopy["events"] as? NSNumber)?.intValue == 1,
              caretCopy["text"] as? String == ""
        else {
            throw probeError("Copy at the text caret would export and close the canvas")
        }
        state.canvasTool = .pen
        state.brush = .pen
        state.width = 1
        surface.setToolState(state)
        try await waitUntil("one point Pen") {
            let value = await surface.stateForTesting()
            return value?["selectedTool"] as? String == "draw"
                && (value?["width"] as? NSNumber)?.doubleValue == 1
        }
        try await verifyDrawnWidth(surface, width: 1, y: 0.15)
        guard let shortcut = await surface.keyboardEventForTesting(
                  type: "keydown", key: "h", code: "KeyH"
              ),
              shortcut["productTool"] as? String == "highlighter",
              let highlighter = await surface.stateForTesting(),
              (highlighter["width"] as? NSNumber)?.doubleValue == 16
        else {
            throw probeError("Highlighter shortcut did not clamp to 16 pt")
        }
        try await verifyDrawnWidth(surface, width: 16, y: 0.5)
        guard let textTool = TraceCanvasTool(rawValue: "text") else {
            throw probeError("Text tool is missing from the native bridge")
        }
        state.canvasTool = textTool
        state.brush = .pen
        state.textSize = 36
        surface.setToolState(state)
        try await waitUntil("native Text tool") {
            let value = await surface.stateForTesting()
            return value?["selectedTool"] as? String == "text"
                && (value?["textSize"] as? NSNumber)?.intValue == 36
        }
        guard await surface.emitPointerForTesting(
                  phase: "began", x: 0.2, y: 0.3
              ),
              await surface.emitPointerForTesting(
                  phase: "ended", x: 0.2, y: 0.3
              )
        else {
            throw probeError("Could not create text with the Text tool")
        }
        try await waitUntil("Text tool editing") {
            await surface.stateForTesting()?["isEditingText"] as? Bool == true
        }
        let secondText = "More text with spaces"
        guard try await surface.typeTextForTesting(secondText) == secondText else {
            throw probeError("Text tool did not preserve spaces")
        }
        state.textSize = 124
        surface.setToolState(state)
        try await waitUntil("live text font size") {
            let value = await surface.stateForTesting()
            return value?["isEditingText"] as? Bool == true
                && (value?["textSizes"] as? [NSNumber])?.map(\.intValue) == [24, 124]
        }
        state.color = .blue
        surface.setToolState(state)
        try await waitUntil("text color change preserves editing") {
            let value = await surface.stateForTesting()
            return value?["isEditingText"] as? Bool == true
                && value?["color"] as? String == "blue"
        }
        let suffix = " after color"
        guard try await surface.typeTextForTesting(suffix) == secondText + suffix else {
            throw probeError("Updating text style interrupted typing")
        }
        guard await surface.keyboardEventForTesting(
            type: "keydown", key: "Escape", code: "Escape", inTextEditor: true
        ) != nil else {
            throw probeError("Could not finish text editing with Escape")
        }
        do {
            try await waitUntil("text editing finished") {
                let value = await surface.stateForTesting()
                return value?["isEditingText"] as? Bool == false
                    && value?["productTool"] as? String == "select"
            }
        } catch {
            throw probeError(
                "Text editing did not finish: \(String(describing: await surface.stateForTesting()))"
            )
        }
        let textBoxCopy = try await surface.captureSelectionCopyForTesting()
        guard textBoxCopy["handled"] as? Bool == true,
              (textBoxCopy["shapeCount"] as? NSNumber)?.intValue == 1
        else {
            throw probeError("Copy did not target the selected text box")
        }
        guard let value = await surface.stateForTesting(),
              value["textOpacities"] as? [Double] == [1, 1],
              (value["textSizes"] as? [NSNumber])?.map(\.intValue) == [24, 124],
              let snapshot = await surface.snapshotForTesting(),
              snapshot.contains(firstText),
              snapshot.contains(secondText + suffix)
        else {
            throw probeError("Text was not saved in the tldraw snapshot")
        }
        state.canvasTool = .select
        state.color = .green
        document.tldrawSnapshotJSON = snapshot
        surface.setDocument(document, toolState: state)
        try await waitUntil("restored text") {
            guard let value = await surface.stateForTesting(),
                  value["color"] as? String == "green",
                  let restored = await surface.snapshotForTesting()
            else {
                return false
            }
            return restored.contains(firstText) && restored.contains(secondText + suffix)
        }
        guard let shortcut = await surface.keyboardEventForTesting(
                  type: "keydown", key: "t", code: "KeyT"
              ),
              shortcut["defaultPrevented"] as? Bool == true,
              shortcut["selectedTool"] as? String == "text",
              shortcut["productTool"] as? String == "text",
              let textState = await surface.stateForTesting(),
              (textState["opacity"] as? NSNumber)?.doubleValue == 1
        else {
            throw probeError("T did not select opaque text")
        }
        state.canvasTool = .text
        state.textSize = 12
        surface.setToolState(state)
        try await waitUntil("minimum text font size") {
            (await surface.stateForTesting()?["textSize"] as? NSNumber)?.intValue == 12
        }
        guard await surface.emitPointerForTesting(
                  phase: "began", x: 0.8, y: 0.4
              ),
              await surface.emitPointerForTesting(
                  phase: "ended", x: 0.8, y: 0.4
              )
        else {
            throw probeError("Could not create minimum-size text")
        }
        try await waitUntil("minimum-size text shape") {
            (await surface.stateForTesting()?["textSizes"] as? [NSNumber])?
                .map(\.intValue) == [24, 124, 12]
        }
    }

    @MainActor
    private static func verifyIndependentStrokeWidths(_ surface: TldrawProductCanvasView) async throws {
        var state = TraceToolState()
        state.width = 2.25
        state.canvasTool = .highlighter
        state.brush = .highlighter
        state.width = 21
        state.textSize = 57
        surface.setToolState(state)
        try await waitUntil("native independent widths") {
            let value = await surface.stateForTesting()
            return value?["productTool"] as? String == "highlighter"
                && (value?["width"] as? NSNumber)?.doubleValue == 21
        }
        for (key, code, width, y) in [("d", "KeyD", 2.0, 0.6), ("h", "KeyH", 21.0, 0.65)] {
            guard await surface.keyboardEventForTesting(type: "keydown", key: key, code: code) != nil,
                  let value = await surface.stateForTesting(),
                  (value["width"] as? NSNumber)?.doubleValue == width
            else {
                throw probeError("\(key.uppercased()) did not restore its own \(width) pt width")
            }
            try await verifyDrawnWidth(surface, width: width, y: y)
        }
        guard await surface.keyboardEventForTesting(type: "keydown", key: "t", code: "KeyT") != nil,
              let textTool = await surface.stateForTesting(),
              (textTool["textSize"] as? NSNumber)?.intValue == 57,
              textTool["productTool"] as? String == "text"
        else {
            throw probeError("Text shortcut lost its independent font size")
        }
        state.canvasTool = .pen
        state.brush = .pen
        state.width = 3.5
        surface.setToolState(state)
        try await waitUntil("updated Drawing width") {
            (await surface.stateForTesting()?["width"] as? NSNumber)?.doubleValue == 4
        }
        guard await surface.keyboardEventForTesting(type: "keydown", key: "h", code: "KeyH") != nil,
              let value = await surface.stateForTesting(),
              (value["width"] as? NSNumber)?.doubleValue == 21
        else {
            throw probeError("Updating Drawing changed the remembered Highlighter width")
        }
        for (key, code, brush, width, y) in [
            ("h", "KeyH", TraceBrushKind.pen, 21.0, 0.72),
            ("d", "KeyD", TraceBrushKind.highlighter, 4.0, 0.78),
        ] {
            guard await surface.keyboardEventForTesting(
                type: "keydown", key: key, code: code
            ) != nil else {
                throw probeError("Could not set the last-used drawing tool")
            }
            state.canvasTool = .select
            state.brush = brush
            surface.setToolState(state)
            try await waitUntil("Select before temporary drawing") {
                await surface.stateForTesting()?["productTool"] as? String == "select"
            }
            guard await surface.keyboardEventForTesting(
                type: "keydown", key: "Meta", code: "MetaLeft", metaKey: true
            ) != nil else {
                throw probeError("Could not hold Command for temporary drawing")
            }
            try await verifyDrawnWidth(surface, width: width, y: y)
            guard await surface.keyboardEventForTesting(
                      type: "keyup", key: "Meta", code: "MetaLeft"
                  ) != nil,
                  let restored = await surface.stateForTesting(),
                  restored["selectedTool"] as? String == "select",
                  (restored["width"] as? NSNumber)?.doubleValue == state.width
            else {
                throw probeError("Temporary drawing changed the persistent tool width")
            }
        }
        state.canvasTool = .highlighter
        state.brush = .highlighter
        state.width = 124
        surface.setToolState(state)
        try await waitUntil("124 point Highlighter") {
            let value = await surface.stateForTesting()
            return (value?["width"] as? NSNumber)?.intValue == 124
                && value?["productTool"] as? String == "highlighter"
                && (value?["textSize"] as? NSNumber)?.intValue == 57
        }
        try await verifyDrawnWidth(surface, width: 124, y: 0.85)
    }

    @MainActor
    private static func verifyRectangleWidths(
        _ surface: TldrawProductCanvasView
    ) async throws {
        guard let initial = await surface.stateForTesting(),
              let originalCount =
                  (initial["rectangleCount"] as? NSNumber)?.intValue
        else {
            throw probeError("Could not read rectangle count before drawing")
        }
        var state = TraceToolState()
        for (index, width) in [1.0, 12.0].enumerated() {
            state.canvasTool = .pen
            state.brush = .pen
            state.width = width
            surface.setToolState(state)
            try await waitUntil("Pen before \(width) pt Rectangle") {
                let value = await surface.stateForTesting()
                return value?["productTool"] as? String == "pen"
                    && (value?["width"] as? NSNumber)?.doubleValue == width
            }
            if index == 0 {
                state.canvasTool = .rectangle
                surface.setToolState(state)
            } else {
                guard await surface.keyboardEventForTesting(
                    type: "keydown", key: "r", code: "KeyR"
                ) != nil else {
                    throw probeError("Rectangle shortcut did not activate")
                }
            }
            try await waitUntil("Rectangle using \(width) pt Pen width") {
                let value = await surface.stateForTesting()
                return value?["productTool"] as? String == "rectangle"
                    && (value?["width"] as? NSNumber)?.doubleValue == width
            }
            let y = index == 0 ? 0.15 : 0.55
            for (phase, x) in [("began", 0.55), ("moved", 0.7), ("ended", 0.7)] {
                guard await surface.emitPointerForTesting(phase: phase, x: x, y: y)
                else {
                    throw probeError("Could not create a \(width) pt rectangle")
                }
            }
            try await waitUntil("rendered \(width) pt rectangle") {
                guard let value = await surface.stateForTesting(),
                      (value["rectangleCount"] as? NSNumber)?.intValue
                          == originalCount + index + 1,
                      let metrics = (value["rectangleMetrics"] as? [[String: Any]])?.last,
                      let strokeWidth =
                          (metrics["strokeWidth"] as? NSNumber)?.doubleValue,
                      let perimeter =
                          (metrics["perimeter"] as? NSNumber)?.doubleValue,
                      let timedPathLength =
                          (metrics["timedPathLength"] as? NSNumber)?.doubleValue
                else {
                    return false
                }
                return abs(strokeWidth - width) < 0.001
                    && abs(timedPathLength - perimeter) < 0.001
            }
            state.canvasTool = .pen
            surface.setToolState(state)
            try await waitUntil("Pen after Rectangle") {
                let value = await surface.stateForTesting()
                return value?["productTool"] as? String == "pen"
                    && (value?["width"] as? NSNumber)?.doubleValue == width
            }
        }
    }

    @MainActor
    private static func verifyCapturedScreenshotOpacity(
        _ surface: TldrawProductCanvasView,
        document: TraceDrawingSession
    ) async throws {
        var highlighter = TraceToolState()
        highlighter.canvasTool = .highlighter
        highlighter.brush = .highlighter
        surface.setToolState(highlighter)
        try await waitUntil("Highlighter before screenshot capture") {
            let state = await surface.stateForTesting()
            return state?["productTool"] as? String == "highlighter"
        }

        let manifest = TraceDrawingManifest(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            sourceApplicationName: "Trace Probe",
            sourceWindowTitle: "Screenshot opacity",
            screenshotFileName: "opacity-probe-screenshot.png",
            screenshotPixelWidth: document.manifest.screenshotPixelWidth,
            screenshotPixelHeight: document.manifest.screenshotPixelHeight,
            sourceWindowBounds: TraceRect(
                x: 0,
                y: 0,
                width: Double(document.manifest.screenshotPixelWidth),
                height: Double(document.manifest.screenshotPixelHeight)
            ),
            pageKind: .screenshot,
            backgroundColor: TraceRGBAColor(red: 1, green: 1, blue: 1),
            viewport: TracePageViewport.full,
            strokes: []
        )
        let capture = TraceDrawingSession(
            manifest: manifest,
            screenshot: solidImage(color: .red, size: document.screenshot.size),
            packageURL: document.packageURL
        )
        surface.setDocument(capture, toolState: highlighter)
        try await waitUntil("screenshot after Highlighter") {
            (await surface.stateForTesting()?["userImageCount"] as? NSNumber)?.intValue == 1
        }
        let screenshotState = await surface.stateForTesting()
        let opacity = (screenshotState?["captureImageOpacity"] as? NSNumber)?.doubleValue
        guard opacity == 1 else {
            throw probeError(
                "Screenshot inherited Highlighter opacity: \(String(describing: opacity))"
            )
        }
        guard let exported = await surface.exportImageForTesting(pixelRatio: 1),
              let pixel = bitmapColor(exported, x: 512, y: 360),
              pixel.redComponent > 0.9,
              pixel.greenComponent < 0.25,
              pixel.blueComponent < 0.1
        else {
            throw probeError("Screenshot export is faded")
        }
    }

    @MainActor
    private static func verifySelectionCopy(_ surface: TldrawProductCanvasView) async throws {
        guard surface.insertImage(solidImage(color: .red, size: NSSize(width: 40, height: 40))) else {
            throw probeError("Could not create the copy-selection fixture")
        }
        try await waitUntil("copy-selection image") {
            (await surface.stateForTesting()?["userImageCount"] as? NSNumber)?.intValue == 1
        }
        guard await surface.keyboardEventForTesting(
                  type: "keydown", key: "v", code: "KeyV"
              ) != nil,
              await surface.selectFirstUserShapeForTesting()
        else {
            throw probeError("Could not select an object for Copy")
        }
        for releaseBeforeCopy in [false, true] {
            guard await surface.keyboardEventForTesting(
                type: "keydown", key: "Meta", code: "MetaLeft", metaKey: true
            ) != nil else {
                throw probeError("Could not hold Command before Copy")
            }
            if releaseBeforeCopy {
                _ = await surface.keyboardEventForTesting(
                    type: "keyup", key: "Meta", code: "MetaLeft"
                )
            }
            let copy = try await surface.captureSelectionCopyForTesting()
            guard copy["handled"] as? Bool == true,
                  (copy["events"] as? NSNumber)?.intValue == 1,
                  (copy["shapeCount"] as? NSNumber)?.intValue == 1,
                  copy["supportsClipboard"] as? Bool == true
            else {
                throw probeError("Command-C lost object selection: \(copy)")
            }
            _ = await surface.keyboardEventForTesting(
                type: "keyup", key: "Meta", code: "MetaLeft"
            )
        }
        let menuCopy = try await surface.captureSelectionCopyForTesting()
        guard menuCopy["handled"] as? Bool == true,
              (menuCopy["shapeCount"] as? NSNumber)?.intValue == 1
        else {
            throw probeError("Copy without Command did not target the selected object")
        }
        _ = await surface.keyboardEventForTesting(
            type: "keydown", key: "Meta", code: "MetaLeft", metaKey: true
        )
        for (phase, x) in [("began", 0.1), ("moved", 0.2), ("ended", 0.3)] {
            guard await surface.emitPointerForTesting(phase: phase, x: x, y: 0.7) else {
                throw probeError("Could not draw while holding Command")
            }
        }
        _ = await surface.keyboardEventForTesting(
            type: "keyup", key: "Meta", code: "MetaLeft"
        )
        let afterDrawing = await surface.stateForTesting()
        guard (afterDrawing?["selectedUserImageCount"] as? NSNumber)?.intValue == 0 else {
            throw probeError("Drawing resurrected the old object selection")
        }
        await surface.clearSelectionForTesting()
        let canvasCopy = try await surface.captureSelectionCopyForTesting()
        guard canvasCopy["handled"] as? Bool == false,
              (canvasCopy["events"] as? NSNumber)?.intValue == 0
        else {
            throw probeError("Copy without selection no longer allows canvas export")
        }
    }

    @MainActor
    private static func verifyDrawnWidth(
        _ surface: TldrawProductCanvasView,
        width: Double,
        y: Double
    ) async throws {
        guard let initial = await surface.stateForTesting(),
              let initialWidths = initial["drawWidths"] as? [NSNumber]
        else {
            throw probeError("Could not read strokes before drawing")
        }
        let initialMatchingCount = initialWidths.filter {
            abs($0.doubleValue - width) < 0.001
        }.count
        for (phase, x) in [("began", 0.15), ("moved", 0.3), ("ended", 0.4)] {
            guard await surface.emitPointerForTesting(phase: phase, x: x, y: y) else {
                throw probeError("Could not draw a \(width) pt stroke")
            }
        }
        try await waitUntil("rendered \(width) pt stroke") {
            guard let value = await surface.stateForTesting(),
                  let widths = value["drawWidths"] as? [NSNumber]
            else {
                return false
            }
            return widths.count == initialWidths.count + 1
                && widths.filter {
                    abs($0.doubleValue - width) < 0.001
                }.count == initialMatchingCount + 1
        }
    }

    @MainActor
    private static func waitUntil(
        _ description: String,
        _ condition: @MainActor @escaping () async -> Bool
    ) async throws {
        for _ in 0..<500 {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw probeError("timed out waiting for \(description)")
    }

    private static func solidImage(
        color: NSColor,
        size: NSSize
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private static func halfTransparentImage(
        color: NSColor,
        size: NSSize
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        color.setFill()
        NSRect(
            x: size.width / 2,
            y: 0,
            width: size.width / 2,
            height: size.height
        ).fill()
        image.unlockFocus()
        return image
    }

    private static func bitmapDimensions(_ image: NSImage) -> NSSize? {
        let representation = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max {
                $0.pixelsWide * $0.pixelsHigh
                    < $1.pixelsWide * $1.pixelsHigh
            }
            ?? image.tiffRepresentation.flatMap(NSBitmapImageRep.init)
        guard let representation else {
            return nil
        }
        return NSSize(
            width: representation.pixelsWide,
            height: representation.pixelsHigh
        )
    }

    private static func sameViewportCenter(
        _ lhs: [String: Any],
        _ rhs: [String: Any]
    ) -> Bool {
        guard let lhsX = (
                  lhs["viewportCenterX"] as? NSNumber
              )?.doubleValue,
              let lhsY = (
                  lhs["viewportCenterY"] as? NSNumber
              )?.doubleValue,
              let rhsX = (
                  rhs["viewportCenterX"] as? NSNumber
              )?.doubleValue,
              let rhsY = (
                  rhs["viewportCenterY"] as? NSNumber
              )?.doubleValue
        else {
            return false
        }
        return abs(lhsX - rhsX) < 0.001
            && abs(lhsY - rhsY) < 0.001
    }

    private static func framesDoNotOverlap(
        _ frames: [[String: Any]]
    ) -> Bool {
        let rects = frames.compactMap { frame -> NSRect? in
            guard let x = (frame["x"] as? NSNumber)?.doubleValue,
                  let y = (frame["y"] as? NSNumber)?.doubleValue,
                  let width = (
                      frame["width"] as? NSNumber
                  )?.doubleValue,
                  let height = (
                      frame["height"] as? NSNumber
                  )?.doubleValue
            else {
                return nil
            }
            return NSRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        }
        guard rects.count == frames.count else {
            return false
        }
        for first in rects.indices {
            for second in rects.indices where second > first {
                if rects[first].intersects(rects[second]) {
                    return false
                }
            }
        }
        return true
    }

    private static func bitmapColor(
        _ image: NSImage,
        x: Int,
        y: Int
    ) -> NSColor? {
        let representation = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max {
                $0.pixelsWide * $0.pixelsHigh
                    < $1.pixelsWide * $1.pixelsHigh
            }
            ?? image.tiffRepresentation.flatMap(NSBitmapImageRep.init)
        guard let representation else {
            return nil
        }
        return representation.colorAt(
            x: min(max(0, x), representation.pixelsWide - 1),
            y: min(max(0, y), representation.pixelsHigh - 1)
        )?.usingColorSpace(.deviceRGB)
    }

    private static func probeError(_ message: String) -> NSError {
        NSError(
            domain: "TraceProductTldrawProbe",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private final class ProductTldrawProbeTransport: NeoTransport {
    var eventHandler: ((NeoTransportEvent) -> Void)?
    let discoveredDevices: [NeoDevice] = []
    let connectionState: PenConnectionState = .idle

    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to deviceID: UUID) {}
    func disconnect() {}
    func requestStatus() {}
    func enableOnlineData() {}
    func setCurrentTime(milliseconds: UInt64) {}
    func setPenCapPowerOffEnabled(_ enabled: Bool) {}
    func setAutoPowerOnEnabled(_ enabled: Bool) {}
    func setBeepEnabled(_ enabled: Bool) {}
    func setHoverEnabled(_ enabled: Bool) {}
    func setOfflineDataEnabled(_ enabled: Bool) {}
    func setAutoPowerOffMinutes(_ minutes: UInt16) {}
    func setSensitivityStep(_ step: UInt8) {}
}
#endif
