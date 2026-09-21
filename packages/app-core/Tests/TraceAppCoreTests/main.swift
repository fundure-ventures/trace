import Darwin
import Foundation
import TraceAppCore

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private var failureCount = 0

private func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("PASS \(name)")
    } catch {
        failureCount += 1
        fputs("FAIL \(name): \(error)\n", stderr)
    }
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard condition() else {
        throw TestFailure(description: "\(message) (\(file):\(line))")
    }
}

test("first launch remains usable before optional setup is dismissed") {
    var machine = TraceAppStateMachine(
        penConnected: false
    )
    try expect(
        machine.phase == .waitingForPen,
        "first launch still entered a blocking setup phase"
    )

    let blankDocumentID = UUID()
    machine.receive(.drawingOpened(blankDocumentID))
    try expect(
        machine.phase == .annotating(documentID: blankDocumentID),
        "first launch could not open a mouse-drawable blank document"
    )

}

test("blank viewport sizing validates persistence and fits calibration") {
    try expect(
        TraceBlankViewportPolicy.validated(
            TraceSize(width: 1_120, height: 760)
        ) == TraceSize(width: 1_120, height: 760),
        "valid saved blank viewport size changed"
    )
    try expect(
        TraceBlankViewportPolicy.validated(
            TraceSize(width: .nan, height: 760)
        ) == TraceBlankViewportPolicy.defaultSize,
        "invalid saved blank viewport size was not rejected"
    )
    try expect(
        TraceBlankViewportPolicy.validated(
            TraceSize(width: 120, height: 90)
        ) == TraceBlankViewportPolicy.minimumSize,
        "too-small saved blank viewport size was not clamped"
    )
    try expect(
        TraceBlankViewportPolicy.validated(
            TraceSize(width: 8_000, height: 6_000)
        ) == TraceBlankViewportPolicy.maximumSize,
        "oversized saved blank viewport size was not clamped"
    )

    let portrait = TraceBlankViewportPolicy.calibrated(
        aspectRatio: 0.7,
        reference: TraceSize(width: 900, height: 650),
        maximum: TraceSize(width: 780, height: 720)
    )
    try expect(
        abs(portrait.width / portrait.height - 0.7) < 0.000_001,
        "calibrated blank viewport lost the paper aspect ratio"
    )
    try expect(
        portrait.width <= 780 && portrait.height <= 720,
        "calibrated blank viewport exceeded the usable screen area"
    )
    try expect(
        portrait.width >= TraceBlankViewportPolicy.minimumSize.width
            && portrait.height
                >= TraceBlankViewportPolicy.minimumSize.height,
        "calibrated blank viewport became impractically small"
    )
}

test("app lifecycle captures on ready pen and annotates the first stroke") {
    var machine = TraceAppStateMachine(
        penConnected: false
    )

    machine.receive(.penConnected)
    try expect(
        machine.phase == .armed,
        "connected pen did not arm frontmost capture"
    )
    machine.receive(.captureStarted)
    try expect(
        machine.phase == .capturing,
        "ready pen did not enter frontmost capture"
    )
    machine.receive(.penConnected)
    try expect(
        machine.phase == .capturing,
        "duplicate ready event restarted frontmost capture"
    )
    try expect(
        !machine.shouldAnnotate(strokeID: 42),
        "capture-in-flight input annotated before a document existed"
    )

    let documentID = UUID()
    machine.receive(.captureSucceeded(documentID))
    try expect(
        machine.phase == .annotating(documentID: documentID),
        "capture did not open annotation"
    )
    try expect(
        machine.shouldAnnotate(strokeID: 43),
        "buffered first stroke did not become annotation"
    )

    machine.receive(.copiedAndHidden)
    try expect(machine.phase == .armed, "copy did not re-arm capture")
    machine.receive(.penDisconnected)
    try expect(
        machine.phase == .waitingForPen,
        "disconnect did not close the active workflow"
    )
    machine.receive(.drawingOpened(documentID))
    machine.receive(.penConnected)
    try expect(
        machine.phase == .annotating(documentID: documentID),
        "pen connection replaced a reopened drawing with capture mode"
    )
    machine.receive(.penDisconnected)
    machine.receive(.penConnected)
    machine.receive(.drawingOpened(documentID))
    try expect(
        machine.phase == .annotating(documentID: documentID),
        "retained drawing did not recover after reconnect"
    )
}

test("manual screenshot capture works without a connected pen") {
    var machine = TraceAppStateMachine(
        penConnected: false
    )
    machine.receive(.manualCaptureStarted)
    try expect(
        machine.phase == .capturing,
        "manual screenshot capture still waited for the pen"
    )
}

test("capture input buffer preserves a complete first stroke once") {
    var router = TraceCaptureEventRouter<String>()
    router.startCapture()
    try expect(
        router.route("start") == nil
            && router.route("sample-1") == nil
            && router.route("sample-2") == nil
            && router.route("complete") == nil,
        "capture events escaped before the document existed"
    )
    try expect(
        router.finishCapture() == [
            "start",
            "sample-1",
            "sample-2",
            "complete",
        ],
        "capture buffer reordered or dropped first-stroke events"
    )
    try expect(
        router.route("next-start") == "next-start"
            && router.finishCapture().isEmpty,
        "capture router replayed events twice or kept buffering"
    )
    router.startCapture()
    _ = router.route("discarded")
    router.cancelCapture()
    try expect(
        router.route("after-failure") == "after-failure"
            && router.finishCapture().isEmpty,
        "failed capture retained or kept buffering stale input"
    )
}

test("pen autosave requires 600 ms without another pen down") {
    try expect(
        TraceAutosavePolicy.idleDelaySeconds == 0.6,
        "pen autosave delay changed from 600 ms"
    )
    var gate = TraceAutosaveGate()
    let firstPenUp = gate.schedule()
    try expect(
        gate.isCurrent(firstPenUp),
        "pen-up did not schedule an idle save"
    )
    gate.cancel()
    try expect(
        !gate.isCurrent(firstPenUp),
        "a following pen-down did not cancel the pending save"
    )
    let secondPenUp = gate.schedule()
    try expect(
        gate.isCurrent(secondPenUp)
            && !gate.isCurrent(firstPenUp),
        "the next pen-up did not replace the cancelled save"
    )
}

test("presenting a document cancels only the stale copy operation") {
    var progress = TraceDocumentCopyProgress()
    let firstDocumentID = UUID()
    let secondDocumentID = UUID()

    try expect(
        progress.begin(for: firstDocumentID),
        "the first document could not begin copying"
    )
    try expect(
        !progress.begin(for: secondDocumentID),
        "a second copy replaced an active operation"
    )
    try expect(
        progress.cancelForDocumentPresentation(),
        "new document presentation did not cancel stale copy progress"
    )
    try expect(
        progress.begin(for: secondDocumentID),
        "the newly presented document remained blocked from copying"
    )
    try expect(
        !progress.end(for: firstDocumentID)
            && progress.isActive,
        "an old callback cleared the new document's copy operation"
    )
    try expect(
        progress.end(for: secondDocumentID)
            && !progress.isActive,
        "the active document could not finish copying"
    )
}

test("window selection uses the topmost mapped app window") {
    let windows = [
        TraceWindowDescriptor(
            id: 1,
            ownerPID: 100,
            layer: 0,
            alpha: 1,
            bounds: TraceRect(x: 0, y: 0, width: 900, height: 700),
            ownerName: "Back",
            title: "Background"
        ),
        TraceWindowDescriptor(
            id: 2,
            ownerPID: 200,
            layer: 0,
            alpha: 1,
            bounds: TraceRect(x: 200, y: 100, width: 500, height: 400),
            ownerName: "Front",
            title: "Document"
        ),
        TraceWindowDescriptor(
            id: 3,
            ownerPID: 999,
            layer: 0,
            alpha: 1,
            bounds: TraceRect(x: 250, y: 150, width: 100, height: 100),
            ownerName: "Trace",
            title: "Board"
        ),
    ]
    let selected = WindowSelectionPolicy.select(
        at: TracePoint(x: 300, y: 200),
        windowsFrontToBack: windows.reversed(),
        excludingOwnerPID: 999
    )

    try expect(selected?.id == 2, "topmost eligible window was not selected")
    try expect(
        WindowSelectionPolicy.select(
            at: TracePoint(x: 850, y: 650),
            windowsFrontToBack: windows.reversed(),
            excludingOwnerPID: 999
        )?.id == 1,
        "background window could not be selected"
    )
    try expect(
        WindowSelectionPolicy.frontmost(
            windowsFrontToBack: windows.reversed(),
            excludingOwnerPID: 999
        )?.id == 2,
        "frontmost fallback selected the wrong window"
    )
}

test("drawing manifest round trips brushes colors and normalized points") {
    let document = TraceDrawingManifest(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000),
        sourceApplicationName: "Preview",
        sourceWindowTitle: "Reference",
        screenshotFileName: "screenshot.png",
        screenshotPixelWidth: 800,
        screenshotPixelHeight: 600,
        sourceWindowCornerRadius: 17.5,
        pageKind: .blank,
        backgroundColor: TraceRGBAColor(
            red: 0.95,
            green: 0.9,
            blue: 0.8
        ),
        viewport: TraceRect(x: 0, y: 0, width: 1, height: 1),
        voiceRecordingFileName: "voice.wav",
        transcriptFileName: "transcript.txt",
        transcriptText: "Sketch the arrow.",
        transcriptWords: [
            TraceTranscriptWord(
                id: 1,
                text: "Sketch",
                startedAtAppClockSeconds: 1_000.25,
                endedAtAppClockSeconds: 1_000.75
            ),
        ],
        strokes: [
            TraceDrawingStroke(
                id: 7,
                color: .red,
                brush: .marker,
                width: 7.5,
                startedAtAppClockSeconds: 1_000.2,
                endedAtAppClockSeconds: 1_000.8,
                transcriptAnnotation: TraceTranscriptAnnotation(
                    id: 1,
                    wordID: 1
                ),
                points: [
                    TraceDrawingPoint(
                        x: 0.25,
                        y: 0.75,
                        pressure: 0.6,
                        tiltX: 105,
                        tiltY: 54,
                        twistDegrees: 86,
                        connectsToPrevious: false
                    ),
                ]
            ),
        ]
    )

    let encoded = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(
        TraceDrawingManifest.self,
        from: encoded
    )
    try expect(decoded == document, "saved drawing manifest changed")
    try expect(
        decoded.sourceWindowCornerRadius == 17.5,
        "saved source corner radius was lost"
    )
    try expect(
        decoded.voiceRecordingFileName == "voice.wav"
            && decoded.transcriptFileName == "transcript.txt",
        "saved voice package metadata was lost"
    )
    try expect(
        decoded.transcriptText == "Sketch the arrow."
            && decoded.transcriptWords?.first?.text == "Sketch"
            && decoded.strokes.first?.startedAtAppClockSeconds == 1_000.2
            && decoded.strokes.first?.endedAtAppClockSeconds == 1_000.8
            && decoded.strokes.first?.transcriptAnnotation
                == TraceTranscriptAnnotation(id: 1, wordID: 1),
        "saved timed transcript annotations were lost"
    )
    try expect(
        decoded.pageKind == .blank
            && decoded.backgroundColor
                == TraceRGBAColor(red: 0.95, green: 0.9, blue: 0.8)
            && decoded.viewport
                == TraceRect(x: 0, y: 0, width: 1, height: 1),
        "saved page kind, background, or viewport was lost"
    )
    guard var legacyObject = try JSONSerialization.jsonObject(
        with: encoded
    ) as? [String: Any] else {
        throw TestFailure(description: "encoded manifest was not an object")
    }
    legacyObject.removeValue(forKey: "sourceWindowCornerRadius")
    legacyObject.removeValue(forKey: "voiceRecordingFileName")
    legacyObject.removeValue(forKey: "transcriptFileName")
    legacyObject.removeValue(forKey: "transcriptText")
    legacyObject.removeValue(forKey: "transcriptWords")
    legacyObject.removeValue(forKey: "pageKind")
    legacyObject.removeValue(forKey: "backgroundColor")
    legacyObject.removeValue(forKey: "viewport")
    if var strokes = legacyObject["strokes"] as? [[String: Any]],
       !strokes.isEmpty
    {
        strokes[0].removeValue(forKey: "startedAtAppClockSeconds")
        strokes[0].removeValue(forKey: "endedAtAppClockSeconds")
        strokes[0].removeValue(forKey: "transcriptAnnotation")
        legacyObject["strokes"] = strokes
    }
    let legacy = try JSONDecoder().decode(
        TraceDrawingManifest.self,
        from: JSONSerialization.data(withJSONObject: legacyObject)
    )
    try expect(
        legacy.sourceWindowCornerRadius == nil,
        "legacy drawing without a corner radius did not decode"
    )
    try expect(
        legacy.voiceRecordingFileName == nil
            && legacy.transcriptFileName == nil,
        "legacy drawing without voice metadata did not decode"
    )
    try expect(
        legacy.transcriptText == nil
            && legacy.transcriptWords == nil
            && legacy.strokes.first?.startedAtAppClockSeconds == nil
            && legacy.strokes.first?.endedAtAppClockSeconds == nil
            && legacy.strokes.first?.transcriptAnnotation == nil,
        "legacy drawing without timed annotations did not decode"
    )
    try expect(
        legacy.pageKind == nil
            && legacy.backgroundColor == nil
            && legacy.viewport == nil,
        "legacy screenshot page metadata did not decode"
    )
    var strokeIDs = TraceDocumentStrokeIDAllocator(
        existingStrokes: [
            TraceDrawingStroke(
                id: 1,
                color: .blue,
                brush: .pen,
                width: 4,
                points: []
            ),
            TraceDrawingStroke(
                id: 7,
                color: .green,
                brush: .highlighter,
                width: 8,
                points: []
            ),
        ]
    )
    try expect(
        strokeIDs.allocate() == 8 && strokeIDs.allocate() == 9,
        "reopened drawing did not allocate unique stroke IDs"
    )
}

test("timed transcript annotations align strokes with words") {
    let early = TraceDrawingStroke(
        id: 1,
        color: .red,
        brush: .pen,
        width: 5,
        startedAtAppClockSeconds: 100.2,
        endedAtAppClockSeconds: 100.8,
        points: [
            TraceDrawingPoint(
                x: 0.1,
                y: 0.2,
                pressure: 0.5,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: false
            ),
        ]
    )
    let late = TraceDrawingStroke(
        id: 2,
        color: .blue,
        brush: .pen,
        width: 5,
        startedAtAppClockSeconds: 102.2,
        endedAtAppClockSeconds: 102.4,
        points: early.points
    )
    let distant = TraceDrawingStroke(
        id: 3,
        color: .green,
        brush: .pen,
        width: 5,
        startedAtAppClockSeconds: 110,
        endedAtAppClockSeconds: 110.2,
        points: early.points
    )
    let words = [
        TraceTranscriptWord(
            id: 1,
            text: "Sketch",
            startedAtAppClockSeconds: 100,
            endedAtAppClockSeconds: 101
        ),
        TraceTranscriptWord(
            id: 2,
            text: "arrow",
            startedAtAppClockSeconds: 103,
            endedAtAppClockSeconds: 104
        ),
    ]
    let annotated = TraceTranscriptAnnotationPlanner.annotating(
        strokes: [late, distant, early],
        words: words
    )
    try expect(
        annotated[2].transcriptAnnotation
            == TraceTranscriptAnnotation(id: 1, wordID: 1),
        "overlapping early stroke did not receive the first annotation"
    )
    try expect(
        annotated[0].transcriptAnnotation
            == TraceTranscriptAnnotation(id: 2, wordID: 2),
        "nearby later stroke did not align with the closest word"
    )
    try expect(
        annotated[1].transcriptAnnotation == nil,
        "distant stroke was assigned to unrelated speech"
    )
    try expect(
        TraceTranscriptAnnotationPlanner.annotatedTranscript(
            "Sketch the arrow.",
            words: words,
            strokes: annotated
        ) == "Sketch [1] the arrow [2].",
        "transcript did not mark the corresponding words"
    )
    let mouseShape = TraceTimedCanvasShape(
        id: "shape:mouse",
        startedAtAppClockSeconds: 102.2,
        endedAtAppClockSeconds: 102.4,
        pathLength: 80
    )
    let mixed = TraceTranscriptAnnotationPlanner.annotating(
        strokes: [early],
        canvasShapes: [mouseShape],
        words: words
    )
    try expect(
        mixed.strokes[0].transcriptAnnotation
            == TraceTranscriptAnnotation(id: 1, wordID: 1),
        "mixed annotation did not retain chronological pen ordering"
    )
    try expect(
        mixed.canvasShapes[0].transcriptAnnotation
            == TraceTranscriptAnnotation(id: 2, wordID: 2),
        "timed tldraw shape did not receive a transcript annotation"
    )
    try expect(
        TraceTranscriptAnnotationPlanner.annotatedTranscript(
            "Sketch the arrow.",
            words: words,
            strokes: mixed.strokes,
            canvasShapes: mixed.canvasShapes
        ) == "Sketch [1] the arrow [2].",
        "transcript did not include the timed tldraw shape marker"
    )
    try expect(
        TraceTranscriptAnnotationPlanner.labelDiameter(
            pathLength: 250,
            annotationID: 2,
            scale: .medium
        ) > TraceTranscriptAnnotationPlanner.labelDiameter(
            pathLength: 4,
            annotationID: 1,
            scale: .medium
        ),
        "annotation label size did not respond to stroke length"
    )
    let small = TraceTranscriptAnnotationPlanner.labelDiameter(
        pathLength: 80,
        annotationID: 1,
        scale: .small
    )
    let medium = TraceTranscriptAnnotationPlanner.labelDiameter(
        pathLength: 80,
        annotationID: 1,
        scale: .medium
    )
    try expect(
        abs(medium - small / 0.75) < 0.000_001,
        "medium annotation scale was not the base size"
    )
    try expect(
        abs(
            TraceTranscriptAnnotationPlanner.labelDiameter(
                pathLength: 80,
                annotationID: 1,
                scale: .large
            ) - medium * 1.5
        ) < 0.000_001,
        "large annotation scale was not 1.5x"
    )
}

test("screenshot resizing computes a centered source crop") {
    let crop = TracePageViewport.centeredCrop(
        source: TraceSize(width: 1_200, height: 800),
        viewport: TraceSize(width: 600, height: 400)
    )
    try expect(
        crop == TraceRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
        "half-size screenshot window did not crop the source center"
    )
    let mapped = TracePageViewport.map(
        TracePoint(x: 0.5, y: 0.5),
        through: crop
    )
    try expect(
        mapped == TracePoint(x: 0.5, y: 0.5),
        "crop center did not map to the window center"
    )
    try expect(
        TracePageViewport.unmap(mapped, through: crop)
            == TracePoint(x: 0.5, y: 0.5),
        "crop mapping did not round trip"
    )
    try expect(
        TracePageViewport.unmap(
            TracePoint(x: 0, y: 0),
            through: crop
        ) == TracePoint(x: 0.25, y: 0.25),
        "live input did not map to the cropped source origin"
    )
    try expect(
        TracePageViewport.unmap(
            TracePoint(x: 1, y: 1),
            through: crop
        ) == TracePoint(x: 0.75, y: 0.75),
        "live input did not map to the cropped source extent"
    )
}

test("paper projection aspect-fits portrait and landscape surfaces") {
    let portrait = TracePageViewport.centeredFit(
        contentAspectRatio: 0.5,
        in: TraceSize(width: 1_200, height: 800)
    )
    try expect(
        abs(portrait.x - 1.0 / 3.0) < 0.000_001
            && portrait.y == 0
            && abs(portrait.width - 1.0 / 3.0) < 0.000_001
            && portrait.height == 1,
        "portrait paper did not center-fit in a landscape viewport"
    )
    let portraitTopLeft = TracePageViewport.unmap(
        TracePoint(x: 0, y: 0),
        through: portrait
    )
    let portraitBottomRight = TracePageViewport.unmap(
        TracePoint(x: 1, y: 1),
        through: portrait
    )
    try expect(
        abs(
            (portraitBottomRight.x - portraitTopLeft.x) * 1_200
                / ((portraitBottomRight.y - portraitTopLeft.y) * 800)
                - 0.5
        ) < 0.000_001,
        "portrait paper distances changed aspect ratio"
    )

    let landscape = TracePageViewport.centeredFit(
        contentAspectRatio: 2,
        in: TraceSize(width: 600, height: 900)
    )
    try expect(
        landscape.x == 0
            && abs(landscape.y - 1.0 / 3.0) < 0.000_001
            && landscape.width == 1
            && abs(landscape.height - 1.0 / 3.0) < 0.000_001,
        "landscape paper did not center-fit in a portrait viewport"
    )
    try expect(
        TracePageViewport.unmap(
            TracePoint(x: 0.5, y: 0.5),
            through: landscape
        ) == TracePoint(x: 0.5, y: 0.5),
        "resizing moved the calibrated paper center"
    )
}

test("drawing history restores strokes moves and deletions") {
    let original = TraceDrawingStroke(
        id: 1,
        color: .red,
        brush: .pen,
        width: 5.25,
        points: [
            TraceDrawingPoint(
                x: 0.2,
                y: 0.3,
                pressure: 0.5,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: false
            ),
        ]
    )
    var moved = original
    moved.points = [
        TraceDrawingPoint(
            x: 0.6,
            y: 0.7,
            pressure: 0.5,
            tiltX: nil,
            tiltY: nil,
            twistDegrees: nil,
            connectsToPrevious: false
        ),
    ]
    let second = TraceDrawingStroke(
        id: 2,
        color: .blue,
        brush: .highlighter,
        width: 8,
        points: []
    )

    var history = TraceDrawingHistory()
    history.record(before: [], after: [original])
    history.record(before: [original], after: [moved])
    history.record(before: [moved], after: [])
    try expect(
        history.canUndo && !history.canRedo,
        "new drawing edits did not populate undo history"
    )
    try expect(
        history.undo() == [moved],
        "undo did not restore a deleted drawing"
    )
    try expect(
        history.undo() == [original],
        "undo did not restore a drawing before movement"
    )
    try expect(
        history.undo() == [],
        "undo did not remove the newly drawn stroke"
    )
    try expect(
        history.redo() == [original]
            && history.redo() == [moved],
        "redo did not restore drawing and movement"
    )
    history.record(before: [moved], after: [moved, second])
    try expect(
        !history.canRedo,
        "a new edit after undo did not clear redo history"
    )
    history.clear()
    try expect(
        !history.canUndo && !history.canRedo,
        "closing a document did not clear drawing history"
    )
}

test("drawing history retains asynchronous transcript annotations") {
    let first = TraceDrawingStroke(
        id: 1,
        color: .red,
        brush: .pen,
        width: 5,
        points: []
    )
    let second = TraceDrawingStroke(
        id: 2,
        color: .blue,
        brush: .pen,
        width: 5,
        points: []
    )
    var history = TraceDrawingHistory()
    history.record(before: [], after: [first])
    history.record(before: [first], after: [first, second])

    var annotatedFirst = first
    annotatedFirst.startedAtAppClockSeconds = 10
    annotatedFirst.endedAtAppClockSeconds = 11
    annotatedFirst.transcriptAnnotation =
        TraceTranscriptAnnotation(id: 1, wordID: 1)
    var annotatedSecond = second
    annotatedSecond.startedAtAppClockSeconds = 12
    annotatedSecond.endedAtAppClockSeconds = 13
    annotatedSecond.transcriptAnnotation =
        TraceTranscriptAnnotation(id: 2, wordID: 2)
    history.updateTranscriptMetadata(
        from: [annotatedFirst, annotatedSecond]
    )

    try expect(
        history.undo() == [annotatedFirst],
        "undo discarded an asynchronously added annotation"
    )
    try expect(
        history.redo() == [annotatedFirst, annotatedSecond],
        "redo discarded an asynchronously added annotation"
    )
    history.clearTranscriptAnnotations()
    try expect(
        history.undo()?.allSatisfy {
            $0.transcriptAnnotation == nil
        } == true,
        "new voice session left stale annotations in history"
    )
}

test("drawing filename puts the app before a readable local date") {
    try expect(
        TraceDrawingFileName.make(
            applicationName: "A/B: Test",
            date: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "A B Test · 01-01-1970 00∶00.traceboard",
        "drawing package filename is not stable or safe"
    )
}

test("board layout preserves pixels and keeps the toolbar outside") {
    let layout = TraceBoardLayoutPolicy.place(
        source: TraceSize(width: 640, height: 480),
        visibleFrame: TraceRect(
            x: 0,
            y: 0,
            width: 1_200,
            height: 800
        ),
        toolbar: TraceSize(width: 656, height: 48),
        gap: 10,
        margin: 18
    )
    try expect(
        layout.board.width == 640 && layout.board.height == 480,
        "board upscaled or downscaled a source that fit"
    )
    try expect(
        layout.toolbar.y == layout.board.y + layout.board.height + 10,
        "toolbar overlaps the captured pixels"
    )

    let oversized = TraceBoardLayoutPolicy.place(
        source: TraceSize(width: 1_600, height: 1_000),
        visibleFrame: TraceRect(
            x: 0,
            y: 0,
            width: 1_200,
            height: 800
        ),
        toolbar: TraceSize(width: 656, height: 48),
        gap: 10,
        margin: 18
    )
    try expect(
        oversized.board.width <= 1_164
            && oversized.board.height <= 706
            && abs(
                oversized.board.width / oversized.board.height - 1.6
            ) < 0.000_001,
        "oversized board did not fit below the toolbar"
    )
}

test("captured alpha inset converts to source point radius") {
    let radius = TraceWindowSilhouette.cornerRadiusPoints(
        horizontalInsetPixels: 35,
        verticalInsetPixels: 35,
        pixelSize: TraceSize(width: 3_956, height: 2_328),
        sourceSize: TraceSize(width: 1_978, height: 1_164)
    )
    try expect(
        abs(radius - 17.5) < 0.000_001,
        "captured corner radius did not preserve source scale"
    )
}

test("grid metrics stay isotropic in view points") {
    let original = TraceGridPolicy.metrics(
        spacingPoints: 8,
        displaySize: TraceSize(width: 1_000, height: 500)
    )
    let widened = TraceGridPolicy.metrics(
        spacingPoints: 8,
        displaySize: TraceSize(width: 1_500, height: 500)
    )
    let expected = TraceGridMetrics(
        horizontalSpacing: 8,
        verticalSpacing: 8,
        dotDiameter: 1,
        lineWidth: 1
    )
    try expect(
        original == expected && widened == expected,
        "viewport resizing deformed point-based grid geometry"
    )
    try expect(
        TraceGridPolicy.clampedSpacing(1) == 4
            && TraceGridPolicy.clampedSpacing(80) == 64,
        "grid spacing did not clamp to 4–64 pt"
    )
}

test("grid control keeps an explicit no-grid segment") {
    let styles: [TraceGridStyle] = [
        .none,
        .dots,
        .square,
        .horizontal,
        .vertical,
    ]
    try expect(
        styles.enumerated().allSatisfy {
            TraceGridControlPolicy.style(forSegment: $0.offset) == $0.element
                && TraceGridControlPolicy.segment(for: $0.element)
                    == $0.offset
        },
        "grid segment ordering no longer includes an explicit no-grid state"
    )
}

test("grid spacing arrows step from the blank minimum") {
    try expect(
        TraceGridPolicy.spacing(from: "") == 4,
        "blank grid input did not resolve to the 4 pt minimum"
    )
    try expect(
        TraceGridPolicy.steppedSpacing(current: nil, delta: 1) == 5,
        "Up from a blank grid field did not step from 4 pt"
    )
    try expect(
        TraceGridPolicy.steppedSpacing(current: nil, delta: -1) == 4
            && TraceGridPolicy.steppedSpacing(current: 64, delta: 1) == 64,
        "grid arrow stepping escaped the 4–64 pt bounds"
    )
}

test("adaptive selection chooses black or white from local luminance") {
    try expect(
        TraceAdaptiveContrast.selectionTone(
            red: 0.95,
            green: 0.95,
            blue: 0.95
        ) == .black,
        "light screenshot pixels did not choose black selection dots"
    )
    try expect(
        TraceAdaptiveContrast.selectionTone(
            red: 0.05,
            green: 0.05,
            blue: 0.05
        ) == .white,
        "dark screenshot pixels did not choose white selection dots"
    )
}

private let bottomSelectionStroke = TraceDrawingStroke(
    id: 1,
    color: .red,
    brush: .pen,
    width: 4,
    points: [
        TraceDrawingPoint(
            x: 0.1,
            y: 0.5,
            pressure: 0.5,
            tiltX: nil,
            tiltY: nil,
            twistDegrees: nil,
            connectsToPrevious: false
        ),
        TraceDrawingPoint(
            x: 0.9,
            y: 0.5,
            pressure: 0.5,
            tiltX: nil,
            tiltY: nil,
            twistDegrees: nil,
            connectsToPrevious: true
        ),
    ]
)
private let topSelectionStroke = TraceDrawingStroke(
    id: 2,
    color: .blue,
    brush: .highlighter,
    width: 8,
    points: [
        TraceDrawingPoint(
            x: 0.5,
            y: 0.2,
            pressure: 0.5,
            tiltX: nil,
            tiltY: nil,
            twistDegrees: nil,
            connectsToPrevious: false
        ),
        TraceDrawingPoint(
            x: 0.5,
            y: 0.8,
            pressure: 0.5,
            tiltX: nil,
            tiltY: nil,
            twistDegrees: nil,
            connectsToPrevious: true
        ),
    ]
)

test("stroke editing selects the topmost visible geometry") {
    try expect(
        TraceStrokeEditing.selectStroke(
            at: TracePoint(x: 0.5, y: 0.5),
            strokes: [bottomSelectionStroke, topSelectionStroke],
            surface: TraceSize(width: 1_000, height: 600),
            tolerance: 8
        ) == 2,
        "mouse hit testing did not select the topmost stroke"
    )
}

test("shift selection toggles objects with standard group behavior") {
    var selection = TraceStrokeEditing.updatedSelection(
        current: [],
        hitStrokeID: 1,
        extending: false
    )
    selection = TraceStrokeEditing.updatedSelection(
        current: selection,
        hitStrokeID: 2,
        extending: true
    )
    try expect(
        selection == [1, 2],
        "Shift-click did not add a second stroke"
    )
    try expect(
        TraceStrokeEditing.updatedSelection(
            current: selection,
            hitStrokeID: 1,
            extending: false
        ) == selection,
        "clicking a selected stroke collapsed the drag group"
    )
    selection = TraceStrokeEditing.updatedSelection(
        current: selection,
        hitStrokeID: 1,
        extending: true
    )
    try expect(
        selection == [2],
        "Shift-click did not toggle an existing stroke out"
    )
    try expect(
        TraceStrokeEditing.updatedSelection(
            current: selection,
            hitStrokeID: nil,
            extending: true
        ) == selection,
        "Shift-clicking the background cleared the group"
    )
}

test("stroke editing never bridges a measured discontinuity") {
    let gapped = TraceDrawingStroke(
        id: 3,
        color: .green,
        brush: .pen,
        width: 4,
        points: [
            TraceDrawingPoint(
                x: 0.1,
                y: 0.1,
                pressure: 0.5,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: false
            ),
            TraceDrawingPoint(
                x: 0.9,
                y: 0.9,
                pressure: 0.5,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: false
            ),
        ]
    )
    try expect(
        TraceStrokeEditing.selectStroke(
            at: TracePoint(x: 0.5, y: 0.5),
            strokes: [gapped],
            surface: TraceSize(width: 1_000, height: 600),
            tolerance: 8
        ) == nil,
        "mouse hit testing bridged a measured discontinuity"
    )
}

test("stroke editing clamps movement to the drawing surface") {
    let moved = TraceStrokeEditing.translatedPoints(
        topSelectionStroke.points,
        requestedDelta: TracePoint(x: 0.8, y: 0.8)
    )
    try expect(
        moved.allSatisfy { abs($0.x - 1) < 0.000_001 }
            && abs(moved[0].y - 0.4) < 0.000_001
            && abs(moved[1].y - 1) < 0.000_001,
        "stroke movement escaped the drawing surface"
    )
}

test("group movement uses one shared clamped delta") {
    var annotatedBottom = bottomSelectionStroke
    annotatedBottom.startedAtAppClockSeconds = 100
    annotatedBottom.endedAtAppClockSeconds = 101
    annotatedBottom.transcriptAnnotation =
        TraceTranscriptAnnotation(id: 4, wordID: 2)
    let moved = TraceStrokeEditing.translatedStrokes(
        [annotatedBottom, topSelectionStroke],
        selectedIDs: [1, 2],
        requestedDelta: TracePoint(x: 0.5, y: 0)
    )
    let bottom = moved[0].points
    let top = moved[1].points
    try expect(
        abs(bottom[0].x - 0.2) < 0.000_001
            && abs(bottom[1].x - 1) < 0.000_001
            && abs(top[0].x - 0.6) < 0.000_001
            && abs(top[1].x - 0.6) < 0.000_001,
        "group movement changed relative stroke positions"
    )
    try expect(
        moved[0].startedAtAppClockSeconds == 100
            && moved[0].endedAtAppClockSeconds == 101
            && moved[0].transcriptAnnotation
                == TraceTranscriptAnnotation(id: 4, wordID: 2),
        "group movement discarded timed transcript metadata"
    )
}

if failureCount > 0 {
    fputs("\(failureCount) test(s) failed\n", stderr)
    exit(1)
}

print("All Trace app core tests passed.")
