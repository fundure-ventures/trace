#if DEBUG
import AppKit

@MainActor
enum TraceDeviceScreenshotProbe {
    private final class MenuTarget: NSObject, NSMenuDelegate {}

    static func run() throws {
        let android = TraceDeviceScreenshotDiscovery.androidDevices("""
        List of devices attached
        phone-a device usb:1-1 product:pixel model:Pixel_9 device:tokay
        phone-b unauthorized usb:1-2
        phone-c offline
        emulator-5554 device product:sdk model:Android_Emulator
        phone-d no permissions
        """)
        try check(android.count == 5, "ADB inventory omitted devices")
        try check(android[0].name == "Pixel 9", "ADB model was not human readable")
        try check(android[0].identifier == "phone-a", "ADB capture target changed")
        try check(android[0].unavailableReason == nil, "Ready ADB device disabled")
        try check(android[1].unavailableReason != nil, "Unauthorized ADB device enabled")
        try check(android[2].unavailableReason != nil, "Offline ADB device enabled")
        try check(android[4].unavailableReason != nil, "Inaccessible ADB device enabled")
        try check(TraceDeviceScreenshotDiscovery.androidDevices("List of devices attached\n").isEmpty, "Empty ADB inventory created a device")

        let modern = Data("""
        {"result":{"devices":[
          {"identifier":"iphone-a","properties":{"hardware":{"platform":"iOS","reality":"physical"},"connection":{"pairingState":"paired"},"state":{"name":"Test iPhone"}}},
          {"identifier":"simulator","properties":{"hardware":{"platform":"iOS","reality":"simulated"},"connection":{"pairingState":"paired"},"state":{"name":"Simulator"}}},
          {"identifier":"unpaired","properties":{"hardware":{"platform":"iOS","reality":"physical"},"connection":{"pairingState":"unpaired"},"state":{"name":"Unpaired"}}},
          {"identifier":"mac","properties":{"hardware":{"platform":"macOS","reality":"physical"},"connection":{"pairingState":"paired"},"state":{"name":"Mac"}}}
        ]}}
        """.utf8)
        let ios = try TraceDeviceScreenshotDiscovery.iosDevices(modern)
        try check(ios.count == 1 && ios[0].name == "Test iPhone", "iOS inventory included non-physical, unpaired, or non-iOS devices")
        try check(ios[0].identifier == "iphone-a", "iOS stable target lost")
        let legacy = Data("""
        {"result":{"devices":[{"identifier":"old-id","hardwareProperties":{"platform":"iOS","reality":"physical","marketingName":"iPhone"},"connectionProperties":{"pairingState":"paired"},"deviceProperties":{"name":"Legacy phone"}}]}}
        """.utf8)
        try check(try TraceDeviceScreenshotDiscovery.iosDevices(legacy).first?.name == "Legacy phone", "Legacy devicectl JSON rejected")
        do {
            _ = try TraceDeviceScreenshotDiscovery.iosDevices(Data("invalid".utf8))
            throw failure("Malformed iOS inventory was silently accepted")
        } catch is DecodingError {}

        let target = MenuTarget()
        let parent = NSMenuItem(title: "New Screenshot trace", action: nil, keyEquivalent: "2")
        let desktopAction = NSSelectorFromString("captureDesktop")
        let deviceAction = NSSelectorFromString("captureDevice:")
        TraceDeviceScreenshotMenu.configure(
            parent, devices: android + ios, applicationName: "GitHub.app",
            target: target, desktopAction: desktopAction, deviceAction: deviceAction, capturing: false
        )
        guard let submenu = parent.submenu else { throw failure("Device submenu missing") }
        try check(submenu.delegate === target, "Screenshot submenu does not notify its owner when opened")
        try check(submenu.items.first?.title == "from GitHub.app", "Desktop source must come first")
        try check(submenu.items.first?.action == desktopAction, "Desktop source lost its action")
        try check(submenu.items[1].isSeparatorItem, "Desktop/device separator missing")
        try check(submenu.items[2].title == "from Pixel 9", "Device source label incorrect")
        try check(submenu.items[2].representedObject as? TraceScreenshotDevice == android[0], "Device menu lost its capture target")
        try check(!submenu.items[3].isEnabled && !submenu.items[4].isEnabled, "Unavailable devices enabled")
        try check(parent.keyEquivalent == "2" && parent.action == desktopAction, "Parent desktop shortcut changed")
        TraceDeviceScreenshotMenu.configure(
            parent, devices: ios, applicationName: "GitHub.app",
            target: target, desktopAction: desktopAction, deviceAction: deviceAction, capturing: true
        )
        try check(parent.submenu?.items.last?.isEnabled == false, "Capture allowed duplicate requests")
        TraceDeviceScreenshotMenu.configure(
            parent, devices: [], applicationName: "GitHub.app",
            target: target, desktopAction: desktopAction, deviceAction: deviceAction, capturing: false
        )
        try check(parent.submenu == nil && parent.action == desktopAction, "No-device menu did not restore desktop capture")

        var created = 0
        var inserted = 0
        let create = { created += 1; return true }
        let insert = { inserted += 1; return true }
        try check(TraceDeviceScreenshotMenu.insert(hasDocument: true, createDocument: create, insertImage: insert), "Existing trace rejected screenshot")
        try check(created == 0 && inserted == 1, "Existing trace was replaced")
        try check(TraceDeviceScreenshotMenu.insert(hasDocument: false, createDocument: create, insertImage: insert), "New trace rejected screenshot")
        try check(created == 1 && inserted == 2, "Missing trace was not created before insertion")
        try check(!TraceDeviceScreenshotMenu.insert(hasDocument: false, createDocument: { false }, insertImage: insert), "Failed creation accepted screenshot")
        try check(inserted == 2, "Image inserted after document creation failed")
        try check(!TraceDeviceScreenshotMenu.insert(hasDocument: true, createDocument: create, insertImage: { false }), "Failed insertion reported success")

        var warmup = TraceDeviceWarmupPolicy()
        try check(!warmup.begin(android[0], now: 100), "Android device was warmed with iOS tools")
        try check(warmup.begin(ios[0], now: 100), "Available iPhone was not warmed")
        try check(!warmup.begin(ios[0], now: 101), "Duplicate in-flight warm-up allowed")
        warmup.finish(ios[0], now: 102)
        try check(!warmup.begin(ios[0], now: 111), "Recently warmed iPhone was warmed again")
        try check(warmup.begin(ios[0], now: 112), "Idle iPhone could not warm on another menu opening")
        warmup.finish(ios[0], now: 113)
        let blocked = TraceScreenshotDevice(
            platform: .ios, identifier: "blocked", name: "Blocked", unavailableReason: "Unavailable"
        )
        try check(!warmup.begin(blocked, now: 200), "Unavailable iPhone was warmed")

        let runner = TraceDeviceCommandRunner()
        let output = try runner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["PNG-test"])
        try check(String(decoding: output, as: UTF8.self) == "PNG-test", "Command stdout corrupted")
        do {
            _ = try runner.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
            throw failure("Failed command reported success")
        } catch is TraceDeviceScreenshotError {}
        do {
            _ = try runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], timeout: 0.05)
            throw failure("Timed-out command reported success")
        } catch let error as TraceDeviceScreenshotError {
            try check(error.localizedDescription.contains("timed out"), "Timeout lost its useful error")
        }
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw failure(message) }
    }

    private static func failure(_ message: String) -> Error {
        NSError(domain: "TraceDeviceScreenshotProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
