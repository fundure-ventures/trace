import AppKit
import WebKit
import XCTest
@testable import TraceSidecarProbe

final class SidecarInputProbeTests: XCTestCase {
    func testWebProbeIsOptInAndDoesNotConsumeInput() {
        let configuration = WKWebViewConfiguration()
        let probe = SidecarInputProbe.shared
        probe.installWebProbe(in: configuration)
        let scripts = configuration.userContentController.userScripts
        let enabled = ProcessInfo.processInfo.environment[
            "TRACE_SIDECAR_INPUT_PROBE"
        ] == "1"
        XCTAssertEqual(probe.isEnabled, enabled)
        XCTAssertEqual(scripts.count, enabled ? 1 : 0)
        guard enabled, let script = scripts.first else { return }
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertTrue(script.isForMainFrameOnly)
        for field in [
            "pointerType", "pressure", "tiltX", "tiltY", "pointercancel",
            "pointerleave", "sidecarProbe", "eventType: 'installed'",
            "capture: true, passive: true",
        ] {
            XCTAssertTrue(script.source.contains(field), "Missing \(field)")
        }
        XCTAssertFalse(script.source.contains("preventDefault"))
        XCTAssertFalse(script.source.contains("stopPropagation"))
    }

    func testMouseEventDescriptionPreservesLocationAndPressure() throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 42, y: 17),
            modifierFlags: [],
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0.75
        ))
        let description = SidecarInputProbe.describe(event)
        for field in ["type=1", "x=42", "y=17", "pressure=0.75", "window=nil"] {
            XCTAssertTrue(description.contains(field), "Missing \(field)")
        }
    }
}
