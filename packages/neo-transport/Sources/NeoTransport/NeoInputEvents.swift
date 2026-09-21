import Foundation

public enum PenTipType: Equatable, Sendable {
    case normal
    case eraser
    case unknown(UInt8)

    public init(rawCode: UInt8) {
        switch rawCode {
        case 0:
            self = .normal
        case 1:
            self = .eraser
        default:
            self = .unknown(rawCode)
        }
    }
}

public enum PenSetting: UInt8, Equatable, Sendable {
    case timestamp = 1
    case autoPowerOff = 2
    case penCapPowerOff = 3
    case autoPowerOn = 4
    case beep = 5
    case hover = 6
    case offlineData = 7
    case ledColor = 8
    case sensitivity = 9
}

public struct PenDownEvent: Equatable, Sendable {
    public let eventCount: UInt8
    public let timestampMilliseconds: UInt64
    public let tipType: PenTipType
    public let color: UInt32

    public init(
        eventCount: UInt8,
        timestampMilliseconds: UInt64,
        tipType: PenTipType,
        color: UInt32
    ) {
        self.eventCount = eventCount
        self.timestampMilliseconds = timestampMilliseconds
        self.tipType = tipType
        self.color = color
    }
}

public struct PenUpEvent: Equatable, Sendable {
    public let eventCount: UInt8
    public let timestampMilliseconds: UInt64
    public let dotCount: UInt16
    public let totalImageCount: UInt16
    public let processedImageCount: UInt16
    public let successfulImageCount: UInt16
    public let sentImageCount: UInt16

    public init(
        eventCount: UInt8,
        timestampMilliseconds: UInt64,
        dotCount: UInt16,
        totalImageCount: UInt16,
        processedImageCount: UInt16,
        successfulImageCount: UInt16,
        sentImageCount: UInt16
    ) {
        self.eventCount = eventCount
        self.timestampMilliseconds = timestampMilliseconds
        self.dotCount = dotCount
        self.totalImageCount = totalImageCount
        self.processedImageCount = processedImageCount
        self.successfulImageCount = successfulImageCount
        self.sentImageCount = sentImageCount
    }
}

public struct PenPageInfo: Equatable, Sendable {
    public let eventCount: UInt8
    public let section: UInt8
    public let owner: UInt32
    public let note: UInt32
    public let page: UInt32

    public init(
        eventCount: UInt8,
        section: UInt8,
        owner: UInt32,
        note: UInt32,
        page: UInt32
    ) {
        self.eventCount = eventCount
        self.section = section
        self.owner = owner
        self.note = note
        self.page = page
    }
}

public struct PenDotEvent: Equatable, Sendable {
    public let eventCount: UInt8
    public let timeDeltaMilliseconds: UInt8
    public let force: UInt16
    public let x: UInt16
    public let y: UInt16
    public let fractionX: UInt8
    public let fractionY: UInt8
    public let tiltX: UInt8
    public let tiltY: UInt8
    public let twist: UInt16

    public var preciseX: Double {
        Double(x) + Double(fractionX) / 100
    }

    public var preciseY: Double {
        Double(y) + Double(fractionY) / 100
    }

    public init(
        eventCount: UInt8,
        timeDeltaMilliseconds: UInt8,
        force: UInt16,
        x: UInt16,
        y: UInt16,
        fractionX: UInt8,
        fractionY: UInt8,
        tiltX: UInt8,
        tiltY: UInt8,
        twist: UInt16
    ) {
        self.eventCount = eventCount
        self.timeDeltaMilliseconds = timeDeltaMilliseconds
        self.force = force
        self.x = x
        self.y = y
        self.fractionX = fractionX
        self.fractionY = fractionY
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.twist = twist
    }
}

public struct PenImageProcessingError: Equatable, Sendable {
    public let eventCount: UInt8
    public let timeDeltaMilliseconds: UInt8
    public let force: UInt16
    public let imageBrightness: UInt8
    public let exposureTime: UInt8
    public let processingTime: UInt8
    public let labelCount: UInt16
    public let errorCode: UInt8
    public let classType: UInt8
    public let errorCount: UInt8

    public init(
        eventCount: UInt8,
        timeDeltaMilliseconds: UInt8,
        force: UInt16,
        imageBrightness: UInt8,
        exposureTime: UInt8,
        processingTime: UInt8,
        labelCount: UInt16,
        errorCode: UInt8,
        classType: UInt8,
        errorCount: UInt8
    ) {
        self.eventCount = eventCount
        self.timeDeltaMilliseconds = timeDeltaMilliseconds
        self.force = force
        self.imageBrightness = imageBrightness
        self.exposureTime = exposureTime
        self.processingTime = processingTime
        self.labelCount = labelCount
        self.errorCode = errorCode
        self.classType = classType
        self.errorCount = errorCount
    }
}

public struct PenHoverEvent: Equatable, Sendable {
    public let timeDeltaMilliseconds: UInt8
    public let x: UInt16
    public let y: UInt16
    public let fractionX: UInt8
    public let fractionY: UInt8

    public var preciseX: Double {
        Double(x) + Double(fractionX) / 100
    }

    public var preciseY: Double {
        Double(y) + Double(fractionY) / 100
    }

    public init(
        timeDeltaMilliseconds: UInt8,
        x: UInt16,
        y: UInt16,
        fractionX: UInt8,
        fractionY: UInt8
    ) {
        self.timeDeltaMilliseconds = timeDeltaMilliseconds
        self.x = x
        self.y = y
        self.fractionX = fractionX
        self.fractionY = fractionY
    }
}
