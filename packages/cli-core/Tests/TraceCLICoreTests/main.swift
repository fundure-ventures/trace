import Foundation
import TraceCLICore

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
    _ message: String
) throws {
    guard condition() else {
        throw TestFailure(description: message)
    }
}

test("bare invocation starts a new trace and supports no-recording") {
    let command = try TraceCLIArguments.parse([])
    try expect(command.action == .newTrace, "bare invocation was not newTrace")
    try expect(!command.noRecording, "recording was suppressed by default")

    let suppressed = try TraceCLIArguments.parse(["--no-recording"])
    try expect(suppressed.noRecording, "--no-recording was ignored")
}

test("capture device list and format parsing are explicit") {
    let devices = try TraceCLIArguments.parse(["capture", "devices"])
    try expect(devices.action == .devices, "capture devices was not recognized")
    let capture = try TraceCLIArguments.parse(["capture", "--device", "Pixel"])
    try expect(capture.action == .captureDevice("Pixel"), "device name was lost")

    let copy = try TraceCLIArguments.parse(["copy", "--format", "pdf"])
    try expect(copy.format == .pdf, "pdf format was not parsed")
}

test("omitting the format defaults to image-dictation") {
    let copy = try TraceCLIArguments.parse(["copy"])
    let export = try TraceCLIArguments.parse(["export", "out"])
    try expect(
        copy.format == .imageDictation && export.format == .imageDictation,
        "an omitted format did not default to image-dictation"
    )
}

test("format or device flags without values are usage errors") {
    for arguments in [["copy", "--format"], ["capture", "--device"]] {
        do {
            _ = try TraceCLIArguments.parse(arguments)
            throw TestFailure(description: "incomplete option was accepted")
        } catch TraceCLIParseError.incompleteOption {
        }
    }
}

test("file arguments retain paths and classify image versus document") {
    let image = try TraceCLIArguments.parse(["--", "a.png", "b.jpeg"])
    try expect(image.action == .openImages(["a.png", "b.jpeg"]), "image paths changed")

    let document = try TraceCLIArguments.parse(["notes.traceboard"])
    try expect(document.action == .openDocument("notes.traceboard"), "document was not recognized")
    let reservedName = try TraceCLIArguments.parse(["./capture"])
    try expect(
        reservedName.action == .openImages(["./capture"]),
        "qualified reserved-name file was not preserved")
}

test("CLI replies map file, usage, and no-document errors to stable exit codes") {
    try expect(
        TraceCLIExitCode.forReply(TraceCLIReply(ok: false, code: "unknownDevice")).rawValue == 64,
        "unknown device was not a usage error"
    )
    try expect(
        TraceCLIExitCode.forReply(TraceCLIReply(ok: false, code: "unreadable")).rawValue == 66,
        "unreadable file was not a file error"
    )
    try expect(
        TraceCLIExitCode.forReply(TraceCLIReply(ok: false, code: "noDocument")).rawValue == 70,
        "missing open trace was not an action failure"
    )
}

test("wire messages round-trip and reject unsupported versions") {
    let request = TraceCLIRequest(action: .copy, format: .image, noRecording: true)
    do {
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(TraceCLIRequest.self, from: data)
        try expect(decoded == request, "request did not round-trip")
        try expect(decoded.v == 1, "request protocol version changed")
    } catch {
        throw TestFailure(description: "request encoding failed: \(error)")
    }
}

if failureCount > 0 {
    exit(1)
}
print("All Trace CLI core tests passed.")
