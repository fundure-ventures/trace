#if DEBUG
import AppKit
import CoreGraphics
import Darwin

@objc private protocol SidecarCaptureManagerAPI {
    func devices() -> [NSObject]
    func connectedDevices() -> [NSObject]
    @objc(configForDevice:)
    func config(for device: NSObject) -> NSObject?
    @objc(connectToDevice:withConfig:completion:)
    func connect(
        to device: NSObject,
        config: NSObject,
        completion: @escaping (NSError?) -> Void
    )
}

enum SidecarCaptureProbeError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): return message
        }
    }
}

@MainActor
final class SidecarCaptureProbe {
    private var connectionResult: Result<Void, Error>?

    func connectDisplay() async throws -> NSScreen {
        guard dlopen(
            "/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore",
            RTLD_NOW
        ) != nil,
        let managerType = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
        managerType.responds(to: NSSelectorFromString("sharedManager")),
        let object = managerType.perform(NSSelectorFromString("sharedManager"))?
            .takeUnretainedValue() as? NSObject
        else {
            throw SidecarCaptureProbeError.failed("SidecarCore is unavailable on this Mac.")
        }
        for selector in [
            "devices", "connectedDevices", "configForDevice:",
            "connectToDevice:withConfig:completion:",
        ] where !object.responds(to: NSSelectorFromString(selector)) {
            throw SidecarCaptureProbeError.failed("SidecarCore API changed: \(selector)")
        }
        // Private Objective-C interfaces do not declare our local protocol conformance.
        let manager = unsafeBitCast(object, to: SidecarCaptureManagerAPI.self)
        var devices = manager.connectedDevices()
        for device in manager.devices() where !devices.contains(device) {
            devices.append(device)
        }
        guard devices.count == 1, let device = devices.first else {
            throw SidecarCaptureProbeError.failed(
                "Expected one Sidecar iPad, found \(devices.count). Keep the target iPad awake and nearby."
            )
        }
        let configType = NSClassFromString("SidecarDisplayConfig") as? NSObject.Type
        guard let config = manager.config(for: device) ?? configType?.init(),
              config.responds(to: NSSelectorFromString("displayID"))
        else {
            throw SidecarCaptureProbeError.failed("Sidecar did not provide a display configuration.")
        }
        if !manager.connectedDevices().contains(device) {
            for key in ["showSideBar", "showTouchBar"] {
                let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
                guard config.responds(to: NSSelectorFromString(setter)) else {
                    throw SidecarCaptureProbeError.failed("Sidecar configuration API changed: \(key)")
                }
                config.setValue(false, forKey: key)
            }
            connectionResult = nil
            manager.connect(to: device, config: config) { [weak self] error in
                DispatchQueue.main.async {
                    self?.connectionResult = error.map { .failure($0) } ?? .success(())
                }
            }
            let deadline = Date().addingTimeInterval(40)
            while connectionResult == nil, Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let connectionResult else {
                throw SidecarCaptureProbeError.failed("Sidecar connection timed out.")
            }
            try connectionResult.get()
        }

        let deadline = Date().addingTimeInterval(15)
        var unmirrored = false
        while Date() < deadline {
            if let currentConfig = manager.config(for: device),
               let number = currentConfig.value(forKey: "displayID") as? NSNumber,
               number.uint32Value != 0
            {
                let displayID = number.uint32Value
                if CGDisplayMirrorsDisplay(displayID) != kCGNullDirectDisplay, !unmirrored {
                    var transaction: CGDisplayConfigRef?
                    guard CGBeginDisplayConfiguration(&transaction) == .success,
                          let transaction
                    else {
                        throw SidecarCaptureProbeError.failed("Could not configure an extended display.")
                    }
                    let result = CGConfigureDisplayMirrorOfDisplay(
                        transaction, displayID, kCGNullDirectDisplay
                    )
                    guard result == .success else {
                        CGCancelDisplayConfiguration(transaction)
                        throw SidecarCaptureProbeError.failed("Could not turn off Sidecar mirroring.")
                    }
                    guard CGCompleteDisplayConfiguration(transaction, .forSession) == .success else {
                        throw SidecarCaptureProbeError.failed("Could not apply Sidecar extension mode.")
                    }
                    unmirrored = true
                } else if CGDisplayMirrorsDisplay(displayID) == kCGNullDirectDisplay,
                          let screen = NSScreen.screens.first(where: {
                              ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                                  as? NSNumber)?.uint32Value == displayID
                          })
                {
                    return screen
                }
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw SidecarCaptureProbeError.failed("Sidecar connected, but its extended screen did not appear.")
    }
}
#endif
