#if DEBUG
import AppKit
import NeoTransport
import TraceAppCore
import TraceVoice

enum ProductTldrawProbe {
    @MainActor
    static func run() async throws {
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
              abs(
                  ((state["opacity"] as? NSNumber)?.doubleValue ?? 0)
                      - 0.5
              ) < 0.001,
              abs(
                  ((state["width"] as? NSNumber)?.doubleValue ?? 0)
                      - 7.5
              ) < 0.001,
              (state["drawWidths"] as? [NSNumber])?.contains(where: {
                  abs($0.doubleValue - 7.5) < 0.001
              }) == true,
              (state["drawOpacities"] as? [NSNumber])?.contains(where: {
                  abs($0.doubleValue - 0.5) < 0.001
              }) == true,
              (state["drawColors"] as? [String])?.contains("green")
                  == true,
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
                && center["fill"] as? String == "#099268"
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
            width: 5,
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
