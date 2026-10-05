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

test("unknown options are usage errors before the option separator") {
    for arguments in [["--bogus"], ["copy", "--frmat", "image"]] {
        do {
            _ = try TraceCLIArguments.parse(arguments)
            throw TestFailure(description: "unknown option was accepted")
        } catch TraceCLIParseError.invalidOption {
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

test("the option separator keeps every later token literal") {
    let command = try TraceCLIArguments.parse([
        "--", "--format.png", "--no-recording.png", "--help.jpg", "-device.webp", "-dash.png",
    ])
    try expect(
        command.action == .openImages([
            "--format.png", "--no-recording.png", "--help.jpg", "-device.webp", "-dash.png",
        ]),
        "tokens after -- were interpreted as options"
    )
    try expect(!command.noRecording, "--no-recording after -- changed capture behavior")
}

test("framed IPC handles partial reads, partial writes, and multi-megabyte replies") {
    let payload = Data(repeating: 0x5A, count: 6 * 1024 * 1024)
    let expected = try JSONEncoder().encode(
        TraceCLIReply(
            ok: true,
            exports: [TraceCLIExport(filename: "large.png", data: payload)]
        )
    )
    let framed = expected + Data([0x0A])
    var inputOffset = 0
    var interruptRead = true
    let line = try TraceCLIStream.readLine(
        maximumBytes: TraceCLIStream.maximumReplyBytes,
        read: { buffer in
            if interruptRead {
                interruptRead = false
                return -1
            }
            let count = min(buffer.count, 997, framed.count - inputOffset)
            guard count > 0 else { return 0 }
            framed.withUnsafeBytes { source in
                buffer.copyMemory(
                    from: UnsafeRawBufferPointer(
                        start: source.baseAddress!.advanced(by: inputOffset),
                        count: count
                    )
                )
            }
            inputOffset += count
            return count
        },
        isInterrupted: { !interruptRead }
    )
    let decoded = try JSONDecoder().decode(TraceCLIReply.self, from: line)
    try expect(decoded.exports?.first?.data == payload, "large reply payload changed")

    var output = Data()
    var interruptWrite = true
    try TraceCLIStream.writeAll(
        framed,
        write: { buffer in
            if interruptWrite {
                interruptWrite = false
                return -1
            }
            let count = min(313, buffer.count)
            output.append(contentsOf: UnsafeRawBufferPointer(
                start: buffer.baseAddress,
                count: count
            ))
            return count
        },
        isInterrupted: { !interruptWrite }
    )
    try expect(output == framed, "partial writes or EINTR lost request bytes")
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
    try expect(
        TraceCLIExitCode.forReply(TraceCLIReply(ok: false, code: "busy")).rawValue == 75,
        "busy action did not map to its documented exit code"
    )
    try expect(
        TraceCLIExitCode.forReply(TraceCLIReply(ok: false, code: "timeout")).rawValue == 70,
        "timed-out action was not an action failure"
    )
}

test("a timed-out CLI request ignores its late completion") {
    var replies: [TraceCLIReply] = []
    let gate = TraceCLIReplyGate { replies.append($0) }
    let timeout = TraceCLIReply(ok: false, code: "timeout")
    let lateSuccess = TraceCLIReply(ok: true)
    gate.send(timeout)
    gate.send(lateSuccess)
    try expect(replies == [timeout], "a late action completion replied a second time")
}

test("device selection resolves against the refreshed inventory") {
    var devices = ["stale"]
    var refreshCompletion: (() -> Void)?
    var selected: String?
    var documentID = "origin"
    var selectedDocumentID: String?
    TraceCLIRefreshPolicy.resolveAfterRefresh(
        captureOrigin: { documentID },
        refresh: { refreshCompletion = $0 },
        resolve: { devices.first(where: { $0 == "new-device" }) },
        completion: { selectedDocumentID = $0; selected = $1 }
    )
    try expect(selected == nil, "device selection ran before discovery completed")
    devices = ["new-device"]
    documentID = "replacement"
    refreshCompletion?()
    try expect(
        selected == "new-device" && selectedDocumentID == "origin",
        "device selection did not use refreshed inventory and its originating document"
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
