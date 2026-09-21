import Foundation

public enum NeoBluetoothState: String, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

public enum PenConnectionState: String, Sendable {
    case idle
    case waitingForBluetooth
    case discovering
    case connecting
    case connected
    case disconnecting
    case disconnected
    case reconnecting
    case failed
}

public struct NeoDevice: Equatable, Sendable {
    public let id: UUID
    public let name: String?
    public let rssi: Int
    public let advertisedServiceUUIDs: [String]
    public let manufacturerData: Data?
    public let isConnectable: Bool?

    public init(
        id: UUID,
        name: String?,
        rssi: Int,
        advertisedServiceUUIDs: [String],
        manufacturerData: Data?,
        isConnectable: Bool?
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.advertisedServiceUUIDs = advertisedServiceUUIDs
        self.manufacturerData = manufacturerData
        self.isConnectable = isConnectable
    }

    public func hasSamePhysicalIdentity(as other: NeoDevice) -> Bool {
        if id == other.id {
            return true
        }
        guard let manufacturerData,
              !manufacturerData.isEmpty,
              let otherManufacturerData = other.manufacturerData,
              !otherManufacturerData.isEmpty
        else {
            return false
        }
        return manufacturerData == otherManufacturerData
    }
}

public enum NeoRawLayer: String, Sendable {
    case advertisement
    case gatt
    case `protocol`
}

public enum NeoRawDirection: String, Sendable {
    case observed
    case inbound
    case outbound
}

public struct NeoRawEvent: Equatable, Sendable {
    public let layer: NeoRawLayer
    public let direction: NeoRawDirection
    public let deviceID: UUID?
    public let serviceUUID: String?
    public let characteristicUUID: String?
    public let bytes: Data?
    public let detail: String

    public init(
        layer: NeoRawLayer,
        direction: NeoRawDirection,
        deviceID: UUID? = nil,
        serviceUUID: String? = nil,
        characteristicUUID: String? = nil,
        bytes: Data? = nil,
        detail: String
    ) {
        self.layer = layer
        self.direction = direction
        self.deviceID = deviceID
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.bytes = bytes
        self.detail = detail
    }
}

public struct NeoTransportFailure: Equatable, Sendable {
    public let stage: String
    public let message: String

    public init(stage: String, message: String) {
        self.stage = stage
        self.message = message
    }
}

public struct NeoNotificationBatch: Equatable, Sendable {
    public let id: UInt64
    public let receivedWallClockMilliseconds: UInt64
    public let receivedUptimeNanoseconds: UInt64
    public let byteCount: Int
    public let frameCount: Int

    public init(
        id: UInt64,
        receivedWallClockMilliseconds: UInt64,
        receivedUptimeNanoseconds: UInt64,
        byteCount: Int,
        frameCount: Int
    ) {
        self.id = id
        self.receivedWallClockMilliseconds = receivedWallClockMilliseconds
        self.receivedUptimeNanoseconds = receivedUptimeNanoseconds
        self.byteCount = byteCount
        self.frameCount = frameCount
    }
}

public enum NeoTransportEvent: Sendable {
    case bluetoothState(NeoBluetoothState)
    case discoveryStarted
    case discoveryStopped
    case deviceDiscovered(NeoDevice)
    case connectionState(PenConnectionState, deviceID: UUID?)
    case gattService(deviceID: UUID, uuid: String)
    case gattCharacteristic(
        deviceID: UUID,
        serviceUUID: String,
        uuid: String,
        properties: [String]
    )
    case deviceMetadata(key: String, value: String)
    case deviceInfo(PenDeviceInfo)
    case status(PenDeviceStatus)
    case onlineDataEnabled
    case settingChanged(PenSetting)
    case penDown(PenDownEvent)
    case penUp(PenUpEvent)
    case pageChanged(PenPageInfo)
    case dot(PenDotEvent)
    case imageProcessingError(PenImageProcessingError)
    case hover(PenHoverEvent)
    case lowBattery(percent: UInt8)
    case shutdown(reason: PenShutdownReason)
    case protocolMessage(NeoProtocolMessage)
    case notificationBatch(NeoNotificationBatch)
    case raw(NeoRawEvent)
    case failure(NeoTransportFailure)
}

public protocol NeoTransport: AnyObject {
    var eventHandler: ((NeoTransportEvent) -> Void)? { get set }
    var discoveredDevices: [NeoDevice] { get }
    var connectionState: PenConnectionState { get }

    func startDiscovery()
    func stopDiscovery()
    func connect(to deviceID: UUID)
    func disconnect()
    func requestStatus()
    func enableOnlineData()
    func setCurrentTime(milliseconds: UInt64)
    func setHoverEnabled(_ enabled: Bool)
    func setBeepEnabled(_ enabled: Bool)
    func setOfflineDataEnabled(_ enabled: Bool)
    func setAutoPowerOnEnabled(_ enabled: Bool)
    func setPenCapPowerOffEnabled(_ enabled: Bool)
    func setAutoPowerOffMinutes(_ minutes: UInt16)
    func setSensitivityStep(_ step: UInt8)
}
