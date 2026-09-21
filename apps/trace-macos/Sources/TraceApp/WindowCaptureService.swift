import AppKit
import CoreGraphics
import ScreenCaptureKit
import TraceAppCore

struct CapturedWindow {
    let descriptor: TraceWindowDescriptor
    let cgImage: CGImage
    let sourceScreenFrame: NSRect
}

enum WindowCaptureError: LocalizedError {
    case permissionRequired
    case noWindow
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Trace needs Screen Recording access to capture windows."
        case .noWindow:
            return "No capturable frontmost window was found."
        case .captureFailed:
            return "macOS could not capture the selected window."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionRequired:
            return "Allow Trace in System Settings → Privacy & Security → "
                + "Screen Recording, then reopen Trace. If Trace is already "
                + "enabled, remove that stale row with the minus button and "
                + "launch it again."
        case .noWindow:
            return "Bring the target application forward and retry the capture."
        case .captureFailed:
            return "Try another visible application window."
        }
    }
}

final class WindowCaptureService {
    var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @discardableResult
    func openPermissionSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    func capture(
        at unitPoint: TracePoint,
        completion: @escaping (Result<CapturedWindow, Error>) -> Void
    ) {
        do {
            let selection = try selectedWindow(at: unitPoint)
            capture(selection, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func captureFrontmost(
        completion: @escaping (Result<CapturedWindow, Error>) -> Void
    ) {
        do {
            let selection = try selectedFrontmostWindow()
            capture(selection, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    private func capture(
        _ selection: TraceWindowDescriptor,
        completion: @escaping (Result<CapturedWindow, Error>) -> Void
    ) {
        if #available(macOS 14.0, *) {
            captureModern(selection, completion: completion)
        } else {
            do {
                completion(.success(try captureLegacy(selection)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func selectedWindow(
        at unitPoint: TracePoint
    ) throws -> TraceWindowDescriptor {
        let descriptors = try windowDescriptors()
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        let point = TracePoint(
            x: displayBounds.minX
                + min(1, max(0, unitPoint.x)) * displayBounds.width,
            y: displayBounds.minY
                + min(1, max(0, unitPoint.y)) * displayBounds.height
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let selected = WindowSelectionPolicy.select(
            at: point,
            windowsFrontToBack: descriptors,
            excludingOwnerPID: ownPID
        ) ?? WindowSelectionPolicy.frontmost(
            windowsFrontToBack: descriptors,
            excludingOwnerPID: ownPID
        ) else {
            throw WindowCaptureError.noWindow
        }
        return selected
    }

    private func selectedFrontmostWindow() throws -> TraceWindowDescriptor {
        let descriptors = try windowDescriptors()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let selected = WindowSelectionPolicy.frontmost(
            windowsFrontToBack: descriptors,
            excludingOwnerPID: ownPID
        ) else {
            throw WindowCaptureError.noWindow
        }
        return selected
    }

    private func windowDescriptors() throws -> [TraceWindowDescriptor] {
        guard hasPermission else {
            throw WindowCaptureError.permissionRequired
        }
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw WindowCaptureError.noWindow
        }
        return windowInfo.compactMap(descriptor)
    }

    @available(macOS 14.0, *)
    private func captureModern(
        _ selected: TraceWindowDescriptor,
        completion: @escaping (Result<CapturedWindow, Error>) -> Void
    ) {
        Task {
            do {
                let content = try await SCShareableContent
                    .excludingDesktopWindows(
                        true,
                        onScreenWindowsOnly: true
                    )
                guard let window = content.windows.first(where: {
                    $0.windowID == selected.id
                }) else {
                    throw WindowCaptureError.noWindow
                }
                let configuration = SCStreamConfiguration()
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                configuration.width = max(
                    1,
                    Int(window.frame.width * scale)
                )
                configuration.height = max(
                    1,
                    Int(window.frame.height * scale)
                )
                configuration.showsCursor = false
                configuration.scalesToFit = true
                configuration.ignoreShadowsSingleWindow = true
                let filter = SCContentFilter(
                    desktopIndependentWindow: window
                )
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                let capture = CapturedWindow(
                    descriptor: selected,
                    cgImage: image,
                    sourceScreenFrame: appKitFrame(
                        for: selected.bounds
                    )
                )
                await MainActor.run {
                    completion(.success(capture))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private func captureLegacy(
        _ selected: TraceWindowDescriptor
    ) throws -> CapturedWindow {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(selected.id),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw WindowCaptureError.captureFailed
        }
        return CapturedWindow(
            descriptor: selected,
            cgImage: image,
            sourceScreenFrame: appKitFrame(for: selected.bounds)
        )
    }

    private func descriptor(
        _ row: [String: Any]
    ) -> TraceWindowDescriptor? {
        guard let id = (row[kCGWindowNumber as String] as? NSNumber)?
            .uint32Value,
            let ownerPID = (row[kCGWindowOwnerPID as String] as? NSNumber)?
                .int32Value,
            let layer = (row[kCGWindowLayer as String] as? NSNumber)?
                .intValue,
            let alpha = (row[kCGWindowAlpha as String] as? NSNumber)?
                .doubleValue,
            let boundsDictionary = row[kCGWindowBounds as String]
                as? NSDictionary,
            let bounds = CGRect(
                dictionaryRepresentation: boundsDictionary
            )
        else {
            return nil
        }
        return TraceWindowDescriptor(
            id: id,
            ownerPID: ownerPID,
            layer: layer,
            alpha: alpha,
            bounds: TraceRect(
                x: bounds.origin.x,
                y: bounds.origin.y,
                width: bounds.width,
                height: bounds.height
            ),
            ownerName: row[kCGWindowOwnerName as String] as? String ?? "App",
            title: row[kCGWindowName as String] as? String ?? "Window"
        )
    }

    private func appKitFrame(for rect: TraceRect) -> NSRect {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                continue
            }
            let displayBounds = CGDisplayBounds(
                CGDirectDisplayID(number.uint32Value)
            )
            let quartzRect = CGRect(
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            )
            guard displayBounds.intersects(quartzRect) else {
                continue
            }
            return NSRect(
                x: screen.frame.minX + rect.x - displayBounds.minX,
                y: screen.frame.maxY
                    - (rect.y - displayBounds.minY)
                    - rect.height,
                width: rect.width,
                height: rect.height
            )
        }
        return NSRect(
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        )
    }
}
