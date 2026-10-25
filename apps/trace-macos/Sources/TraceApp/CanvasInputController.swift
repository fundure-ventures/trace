import AppKit

/// Owns tablet input before WebKit can reduce it to mouse events.
final class CanvasInputController: NSObject, NSGestureRecognizerDelegate {
    var onInput: (([[String: Any]]) -> Void)?
    var tool: TraceCanvasTool = .pen
    private weak var view: NSView?
    private let pencil = CanvasPencilRecognizer(target: nil, action: nil)
    private let pan = CanvasFingerPanRecognizer(target: nil, action: nil)
    private let pinch = NSMagnificationGestureRecognizer(target: nil, action: nil)

    init(view: NSView) {
        self.view = view
        super.init()
        pencil.target = self
        pencil.action = #selector(pencilChanged)
        pencil.delegate = self
        pencil.delaysPrimaryMouseButtonEvents = true
        pencil.allowedTouchTypes = []
        view.addGestureRecognizer(pencil)

        // Older Sidecar versions expose scrolling, but not direct finger drags.
        if #available(macOS 27.0, *) {
            pan.target = self
            pan.action = #selector(panChanged)
            pan.delegate = self
            pan.allowedTouchTypes = .direct
            view.addGestureRecognizer(pan)
        }
        pinch.target = self
        pinch.action = #selector(pinchChanged)
        pinch.delegate = self
        pinch.allowedTouchTypes = .direct
        pinch.delaysMagnificationEvents = true
        view.addGestureRecognizer(pinch)
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        if gestureRecognizer === pencil {
            // Keep WebKit's text caret and selection-handle hit testing.
            return event.subtype == .tabletPoint
                && tool != .select && tool != .text
                && !event.modifierFlags.contains(.command)
        }
        // Never turn ordinary mouse drags into canvas pans.
        return gestureRecognizer === pinch
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldReceive touch: NSTouch
    ) -> Bool {
        gestureRecognizer !== pencil && touch.type == .direct
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === pan && otherGestureRecognizer === pinch)
            || (gestureRecognizer === pinch && otherGestureRecognizer === pan)
    }

    private func point(_ location: NSPoint, in view: NSView) -> [String: Any] {
        [
            "x": (location.x - view.bounds.minX) / max(1, view.bounds.width),
            "y": (view.isFlipped
                ? location.y - view.bounds.minY
                : view.bounds.maxY - location.y) / max(1, view.bounds.height),
        ]
    }

    @objc private func pencilChanged() {
        guard let view else { return }
        var samples = pencil.samples
        pencil.samples.removeAll(keepingCapacity: true)
        if pencil.state == .cancelled, samples.last?.phase != "cancelled",
           let event = pencil.lastEvent
        {
            samples.append(CanvasPencilRecognizer.Sample(event: event, phase: "cancelled"))
        }
        onInput?(samples.map { sample in
            let event = sample.event
            var payload = point(view.convert(event.locationInWindow, from: nil), in: view)
            payload["kind"] = "pencil"
            payload["phase"] = sample.phase
            if event.subtype == .tabletPoint {
                payload["pressure"] = min(1, max(0, event.pressure))
                payload["tiltX"] = event.tilt.x * 90
                payload["tiltY"] = -event.tilt.y * 90
                payload["rotation"] = event.rotation
                payload["tangentialPressure"] = event.tangentialPressure
            } else {
                payload["pressure"] = 0
                payload["tiltX"] = 0
                payload["tiltY"] = 0
                payload["rotation"] = 0
                payload["tangentialPressure"] = 0
            }
            payload["shiftKey"] = event.modifierFlags.contains(.shift)
            payload["altKey"] = event.modifierFlags.contains(.option)
            payload["ctrlKey"] = event.modifierFlags.contains(.control)
            payload["metaKey"] = event.modifierFlags.contains(.command)
            return payload
        })
    }

    @objc private func panChanged() {
        guard let view, pencil.state != .began, pencil.state != .changed else { return }
        let translation = pan.translation
        guard pan.state == .began || pan.state == .changed || pan.state == .ended else { return }
        onInput?([[
            "kind": "pan",
            "dx": translation.x / max(1, view.bounds.width),
            "dy": (view.isFlipped ? translation.y : -translation.y) / max(1, view.bounds.height),
        ]])
    }

    @objc private func pinchChanged() {
        guard let view, pencil.state != .began, pencil.state != .changed else { return }
        let scale = max(0.01, 1 + pinch.magnification)
        pinch.magnification = 0
        guard pinch.state == .began || pinch.state == .changed || pinch.state == .ended else { return }
        var payload = point(pinch.location(in: view), in: view)
        payload["kind"] = "pinch"
        payload["scale"] = scale
        onInput?([payload])
    }
}

/// Claims direct touches before WebKit's own drag/scroll recognizers.
private final class CanvasFingerPanRecognizer: NSGestureRecognizer {
    private(set) var translation = NSPoint.zero

    override func canBePrevented(by preventingGestureRecognizer: NSGestureRecognizer) -> Bool {
        false
    }

    override func canPrevent(_ preventedGestureRecognizer: NSGestureRecognizer) -> Bool {
        !(preventedGestureRecognizer is NSMagnificationGestureRecognizer)
    }

    override func touchesBegan(with event: NSEvent) {
        let touches = event.touches(matching: .touching, in: view)
            .filter { $0.type == .direct }
        guard touches.count == 1 else {
            translation = .zero
            state = state == .possible ? .failed : .cancelled
            return
        }
        translation = .zero
        state = .began
    }

    override func touchesMoved(with event: NSEvent) {
        guard state == .began || state == .changed, let view else { return }
        let touches = event.touches(matching: .touching, in: view)
            .filter { $0.type == .direct }
        guard touches.count == 1, let touch = touches.first else {
            translation = .zero
            state = .cancelled
            return
        }
        let current = touch.location(in: view)
        let previous = touch.previousLocation(in: view)
        translation = NSPoint(x: current.x - previous.x, y: current.y - previous.y)
        state = .changed
    }

    override func touchesEnded(with event: NSEvent) {
        translation = .zero
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(with event: NSEvent) {
        translation = .zero
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        super.reset()
        translation = .zero
    }
}

private final class CanvasPencilRecognizer: NSGestureRecognizer {
    struct Sample {
        let event: NSEvent
        let phase: String
    }

    var samples: [Sample] = []
    private(set) var lastEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        guard event.subtype == .tabletPoint else {
            state = .failed
            return
        }
        lastEvent = event
        samples.append(Sample(event: event, phase: "began"))
        state = .began
    }

    override func mouseDragged(with event: NSEvent) {
        guard state == .began || state == .changed else { return }
        lastEvent = event
        samples.append(Sample(event: event, phase: "moved"))
        state = .changed
    }

    override func mouseUp(with event: NSEvent) {
        guard state == .began || state == .changed else { return }
        lastEvent = event
        samples.append(Sample(event: event, phase: "ended"))
        state = .ended
    }

    override func mouseCancelled(with event: NSEvent) {
        guard state == .began || state == .changed else {
            state = .failed
            return
        }
        samples.append(Sample(event: event, phase: "cancelled"))
        state = .cancelled
    }

    override func reset() {
        super.reset()
        samples.removeAll(keepingCapacity: true)
        lastEvent = nil
    }
}
