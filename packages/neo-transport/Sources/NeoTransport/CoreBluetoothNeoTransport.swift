import CoreBluetooth
import Foundation

public final class CoreBluetoothNeoTransport: NSObject, NeoTransport {
    private enum UUIDs {
        static let protocolV2Service = CBUUID(string: "19F1")
        static let protocolV2Write = CBUUID(string: "2BA0")
        static let protocolV2Receive = CBUUID(string: "2BA1")

        static let protocolV5Service = CBUUID(
            string: "4F99F138-9D53-5BFA-9E50-B147491AFE68"
        )
        static let protocolV5Write = CBUUID(
            string: "8BC8CC7D-88CA-56B0-AF9A-9BF514D0D61A"
        )
        static let protocolV5Receive = CBUUID(
            string: "64CD86B1-2256-5AEB-9F04-2CAF6C60AE57"
        )

        static let batteryLevel = "2A19"
        static let modelNumber = "2A24"
        static let serialNumber = "2A25"
        static let firmwareRevision = "2A26"
        static let hardwareRevision = "2A27"
        static let softwareRevision = "2A28"
        static let manufacturerName = "2A29"

        static let neoServices: Set<String> = [
            protocolV2Service.uuidString.uppercased(),
            protocolV5Service.uuidString.uppercased(),
        ]
        static let writeCharacteristics: Set<String> = [
            protocolV2Write.uuidString.uppercased(),
            protocolV5Write.uuidString.uppercased(),
        ]
        static let receiveCharacteristics: Set<String> = [
            protocolV2Receive.uuidString.uppercased(),
            protocolV5Receive.uuidString.uppercased(),
        ]
        static let readableMetadataCharacteristics: Set<String> = [
            batteryLevel,
            modelNumber,
            serialNumber,
            firmwareRevision,
            hardwareRevision,
            softwareRevision,
            manufacturerName,
        ]
    }

    public var eventHandler: ((NeoTransportEvent) -> Void)?

    public var discoveredDevices: [NeoDevice] {
        devicesByID.values.sorted {
            ($0.name ?? $0.id.uuidString) < ($1.name ?? $1.id.uuidString)
        }
    }

    public private(set) var connectionState: PenConnectionState = .idle {
        didSet {
            guard oldValue != connectionState else {
                return
            }
            emit(.connectionState(connectionState, deviceID: currentPeripheral?.identifier))
        }
    }

    private lazy var centralManager = CBCentralManager(
        delegate: self,
        queue: nil,
        options: [CBCentralManagerOptionShowPowerAlertKey: true]
    )

    private let automaticallyReconnect: Bool
    private let reconnectDelay: TimeInterval
    private let appVersion: String

    private var wantsDiscovery = false
    private var devicesByID: [UUID: NeoDevice] = [:]
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var currentPeripheral: CBPeripheral?
    private var pendingServiceUUIDs = Set<String>()
    private var writeCharacteristic: CBCharacteristic?
    private var receiveCharacteristic: CBCharacteristic?
    private var packetParser = NeoPacketStreamParser()
    private var handshakeStarted = false
    private var intentionalDisconnect = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var connectedDeviceIdentity: NeoDevice?
    private var reconnectScanActive = false
    private var pendingWriteChunks: [Data] = []
    private var writeInFlight = false
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var nextNotificationBatchID: UInt64 = 1

    public init(
        automaticallyReconnect: Bool = true,
        reconnectDelay: TimeInterval = 2,
        appVersion: String = "0.1.0"
    ) {
        self.automaticallyReconnect = automaticallyReconnect
        self.reconnectDelay = reconnectDelay
        self.appVersion = appVersion
        super.init()
        _ = centralManager
    }

    public func startDiscovery() {
        wantsDiscovery = true

        switch centralManager.state {
        case .poweredOn:
            beginDiscovery()
        case .unknown, .resetting:
            connectionState = .waitingForBluetooth
        case .poweredOff:
            connectionState = .waitingForBluetooth
            emitFailure(stage: "bluetooth", message: "Bluetooth is powered off")
        case .unauthorized:
            connectionState = .failed
            emitFailure(
                stage: "bluetooth",
                message: "Bluetooth access is not authorized for this app"
            )
        case .unsupported:
            connectionState = .failed
            emitFailure(stage: "bluetooth", message: "Bluetooth LE is not supported")
        @unknown default:
            connectionState = .failed
            emitFailure(stage: "bluetooth", message: "Unknown Bluetooth manager state")
        }
    }

    public func stopDiscovery() {
        wantsDiscovery = false
        guard centralManager.isScanning else {
            return
        }
        centralManager.stopScan()
        emit(.discoveryStopped)
        if connectionState == .discovering {
            connectionState = .idle
        }
    }

    public func connect(to deviceID: UUID) {
        guard centralManager.state == .poweredOn else {
            emitFailure(stage: "connect", message: "Bluetooth is not powered on")
            return
        }

        let peripheral = peripheralsByID[deviceID]
            ?? centralManager.retrievePeripherals(withIdentifiers: [deviceID]).first
        guard let peripheral else {
            emitFailure(
                stage: "connect",
                message: "Device \(deviceID.uuidString) has not been discovered"
            )
            return
        }

        if currentPeripheral?.identifier == peripheral.identifier,
           peripheral.state == .connected
        {
            return
        }

        stopDiscovery()
        reconnectWorkItem?.cancel()
        reconnectScanActive = false
        intentionalDisconnect = false
        connectedDeviceIdentity = devicesByID[deviceID]
        currentPeripheral = peripheral
        peripheralsByID[peripheral.identifier] = peripheral
        peripheral.delegate = self
        resetProtocolState()
        connectionState = .connecting
        emitRaw(
            layer: .gatt,
            direction: .outbound,
            peripheral: peripheral,
            detail: "connect requested"
        )
        centralManager.connect(
            peripheral,
            options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true]
        )
    }

    public func disconnect() {
        reconnectWorkItem?.cancel()
        reconnectScanActive = false
        intentionalDisconnect = true

        guard let peripheral = currentPeripheral else {
            connectionState = .disconnected
            return
        }

        connectionState = .disconnecting
        emitRaw(
            layer: .gatt,
            direction: .outbound,
            peripheral: peripheral,
            detail: "disconnect requested"
        )
        centralManager.cancelPeripheralConnection(peripheral)
    }

    public func requestStatus() {
        guard writeCharacteristic != nil else {
            emitFailure(
                stage: "protocol",
                message: "Cannot request pen status before the Neo channel is ready"
            )
            return
        }
        sendProtocolPacket(NeoProtocol.makeStatusRequest(), detail: "pen status request")
    }

    public func enableOnlineData() {
        guard writeCharacteristic != nil else {
            emitFailure(
                stage: "protocol",
                message: "Cannot enable online data before the Neo channel is ready"
            )
            return
        }
        sendProtocolPacket(
            NeoProtocol.makeEnableOnlineDataRequest(),
            detail: "enable all available Ncode notes"
        )
    }

    public func setHoverEnabled(_ enabled: Bool) {
        sendSettingRequest(
            NeoProtocol.makeSetHoverRequest(enabled: enabled),
            detail: "set hover \(enabled ? "on" : "off")"
        )
    }

    public func setBeepEnabled(_ enabled: Bool) {
        sendSettingRequest(
            NeoProtocol.makeSetBeepRequest(enabled: enabled),
            detail: "set beep \(enabled ? "on" : "off")"
        )
    }

    public func setOfflineDataEnabled(_ enabled: Bool) {
        sendSettingRequest(
            NeoProtocol.makeSetOfflineDataRequest(enabled: enabled),
            detail: "set offline storage \(enabled ? "on" : "off")"
        )
    }

    public func setAutoPowerOnEnabled(_ enabled: Bool) {
        sendSettingRequest(
            NeoProtocol.makeSetAutoPowerOnRequest(enabled: enabled),
            detail: "set auto power-on \(enabled ? "on" : "off")"
        )
    }

    public func setPenCapPowerOffEnabled(_ enabled: Bool) {
        sendSettingRequest(
            NeoProtocol.makeSetPenCapPowerOffRequest(enabled: enabled),
            detail: "set cap power-off \(enabled ? "on" : "off")"
        )
    }

    public func setAutoPowerOffMinutes(_ minutes: UInt16) {
        sendSettingRequest(
            NeoProtocol.makeSetAutoPowerOffRequest(minutes: minutes),
            detail: "set auto power-off \(minutes)m"
        )
    }

    public func setSensitivityStep(_ step: UInt8) {
        sendSettingRequest(
            NeoProtocol.makeSetSensitivityRequest(step: step),
            detail: "set sensitivity \(step)"
        )
    }

    private func sendSettingRequest(
        _ request: Data,
        detail: String
    ) {
        guard writeCharacteristic != nil else {
            emitFailure(
                stage: "protocol",
                message: "Cannot change pen settings before the Neo channel is ready"
            )
            return
        }
        sendProtocolPacket(
            request,
            detail: detail
        )
    }

    public func setCurrentTime(milliseconds: UInt64) {
        guard writeCharacteristic != nil else {
            emitFailure(
                stage: "protocol",
                message: "Cannot synchronize time before the Neo channel is ready"
            )
            return
        }
        sendProtocolPacket(
            NeoProtocol.makeSetTimeRequest(milliseconds: milliseconds),
            detail: "synchronize pen clock"
        )
    }

    private func beginDiscovery() {
        guard !centralManager.isScanning else {
            return
        }

        connectionState = .discovering
        emit(.discoveryStarted)
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey:
                    reconnectScanActive,
            ]
        )
    }

    private func isLikelyNeoDevice(
        peripheral: CBPeripheral,
        advertisementData: [String: Any]
    ) -> Bool {
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey]
            as? [CBUUID] ?? []
        if services.contains(where: {
            UUIDs.neoServices.contains($0.uuidString.uppercased())
        }) {
            return true
        }

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = (advertisedName ?? peripheral.name ?? "").uppercased()
        return name.contains("SMARTPEN")
            || name.hasPrefix("NWP-")
            || name.hasPrefix("NEO")
    }

    private func resetProtocolState() {
        pendingServiceUUIDs.removeAll()
        writeCharacteristic = nil
        receiveCharacteristic = nil
        packetParser.reset()
        handshakeStarted = false
        pendingWriteChunks.removeAll()
        writeInFlight = false
    }

    private func beginHandshakeIfReady() {
        guard !handshakeStarted,
              writeCharacteristic != nil,
              receiveCharacteristic?.isNotifying == true
        else {
            return
        }

        handshakeStarted = true
        let packet = NeoProtocol.makeVersionRequest(appVersion: appVersion)
        sendProtocolPacket(packet, detail: "version request")
    }

    private func sendProtocolPacket(_ packet: Data, detail: String) {
        guard let peripheral = currentPeripheral,
              let characteristic = writeCharacteristic
        else {
            emitFailure(stage: "protocol", message: "Neo write channel is unavailable")
            return
        }

        emitRaw(
            layer: .protocol,
            direction: .outbound,
            peripheral: peripheral,
            characteristic: characteristic,
            bytes: packet,
            detail: detail
        )

        if characteristic.properties.contains(.write) {
            writeType = .withResponse
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else {
            emitFailure(
                stage: "gatt",
                message: "Neo write characteristic does not support writes"
            )
            return
        }

        let maximumLength = max(
            1,
            peripheral.maximumWriteValueLength(for: writeType)
        )
        var offset = 0
        while offset < packet.count {
            let end = min(packet.count, offset + maximumLength)
            pendingWriteChunks.append(packet.subdata(in: offset..<end))
            offset = end
        }
        drainWriteQueue()
    }

    private func drainWriteQueue() {
        guard let peripheral = currentPeripheral,
              let characteristic = writeCharacteristic,
              !pendingWriteChunks.isEmpty
        else {
            return
        }

        switch writeType {
        case .withResponse:
            guard !writeInFlight else {
                return
            }
            writeInFlight = true
            let chunk = pendingWriteChunks.removeFirst()
            emitRaw(
                layer: .gatt,
                direction: .outbound,
                peripheral: peripheral,
                characteristic: characteristic,
                bytes: chunk,
                detail: "write chunk"
            )
            peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
        case .withoutResponse:
            while !pendingWriteChunks.isEmpty,
                  peripheral.canSendWriteWithoutResponse
            {
                let chunk = pendingWriteChunks.removeFirst()
                emitRaw(
                    layer: .gatt,
                    direction: .outbound,
                    peripheral: peripheral,
                    characteristic: characteristic,
                    bytes: chunk,
                    detail: "write chunk"
                )
                peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            }
        @unknown default:
            emitFailure(stage: "gatt", message: "Unknown CoreBluetooth write type")
        }
    }

    private func processNeoData(
        _ data: Data,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        receivedWallClockMilliseconds: UInt64,
        receivedUptimeNanoseconds: UInt64
    ) {
        let frames = packetParser.append(data)
        emit(
            .notificationBatch(
                NeoNotificationBatch(
                    id: nextNotificationBatchID,
                    receivedWallClockMilliseconds: receivedWallClockMilliseconds,
                    receivedUptimeNanoseconds: receivedUptimeNanoseconds,
                    byteCount: data.count,
                    frameCount: frames.count
                )
            )
        )
        nextNotificationBatchID += 1

        for frame in frames {
            emitRaw(
                layer: .protocol,
                direction: .inbound,
                peripheral: peripheral,
                characteristic: characteristic,
                bytes: frame,
                detail: "decoded frame"
            )

            do {
                let message = try NeoProtocolDecoder.decode(frame: frame)
                switch message {
                case let .deviceInfo(info):
                    emit(.deviceInfo(info))
                    requestStatus()
                case let .status(status):
                    emit(.status(status))
                case .onlineDataEnabled:
                    emit(.onlineDataEnabled)
                case let .settingChanged(setting):
                    emit(.settingChanged(setting))
                case let .penDown(event):
                    emit(.penDown(event))
                case let .penUp(event):
                    emit(.penUp(event))
                case let .pageChanged(page):
                    emit(.pageChanged(page))
                case let .dot(event):
                    emit(.dot(event))
                case let .imageProcessingError(error):
                    emit(.imageProcessingError(error))
                case let .hover(event):
                    emit(.hover(event))
                case let .lowBattery(percent):
                    emit(.lowBattery(percent: percent))
                case let .shutdown(reason):
                    emit(.shutdown(reason: reason))
                case .unhandled:
                    emit(.protocolMessage(message))
                }
            } catch {
                emitFailure(stage: "protocol", message: String(describing: error))
            }
        }
    }

    private func readStandardValue(
        _ data: Data,
        characteristicUUID: String
    ) {
        switch characteristicUUID {
        case UUIDs.batteryLevel:
            guard let battery = data.first else {
                return
            }
            emit(.deviceMetadata(key: "standard-battery", value: "\(battery)%"))
        case UUIDs.modelNumber:
            emitStringMetadata(key: "standard-model", data: data)
        case UUIDs.serialNumber:
            emitStringMetadata(key: "standard-serial", data: data)
        case UUIDs.firmwareRevision:
            emitStringMetadata(key: "standard-firmware", data: data)
        case UUIDs.hardwareRevision:
            emitStringMetadata(key: "standard-hardware", data: data)
        case UUIDs.softwareRevision:
            emitStringMetadata(key: "standard-software", data: data)
        case UUIDs.manufacturerName:
            emitStringMetadata(key: "standard-manufacturer", data: data)
        default:
            break
        }
    }

    private func emitStringMetadata(key: String, data: Data) {
        let value = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        emit(.deviceMetadata(key: key, value: value))
    }

    private func scheduleReconnect(to peripheral: CBPeripheral) {
        guard automaticallyReconnect, !intentionalDisconnect else {
            return
        }

        reconnectWorkItem?.cancel()
        reconnectScanActive = true
        if connectedDeviceIdentity == nil {
            connectedDeviceIdentity = devicesByID[peripheral.identifier]
        }
        connectionState = .reconnecting
        let workItem = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral else {
                return
            }
            guard self.centralManager.state == .poweredOn,
                  !self.intentionalDisconnect
            else {
                return
            }
            self.emitRaw(
                layer: .gatt,
                direction: .outbound,
                peripheral: peripheral,
                detail: "automatic reconnect scan started"
            )
            self.wantsDiscovery = true
            self.beginDiscovery()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + reconnectDelay,
            execute: workItem
        )
    }

    private func emit(_ event: NeoTransportEvent) {
        eventHandler?(event)
    }

    private func emitFailure(stage: String, message: String) {
        emit(.failure(NeoTransportFailure(stage: stage, message: message)))
    }

    private func emitRaw(
        layer: NeoRawLayer,
        direction: NeoRawDirection,
        peripheral: CBPeripheral? = nil,
        service: CBService? = nil,
        characteristic: CBCharacteristic? = nil,
        bytes: Data? = nil,
        detail: String
    ) {
        emit(
            .raw(
                NeoRawEvent(
                    layer: layer,
                    direction: direction,
                    deviceID: peripheral?.identifier,
                    serviceUUID: service?.uuid.uuidString.uppercased()
                        ?? characteristic?.service?.uuid.uuidString.uppercased(),
                    characteristicUUID: characteristic?.uuid.uuidString.uppercased(),
                    bytes: bytes,
                    detail: detail
                )
            )
        )
    }
}

extension CoreBluetoothNeoTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: NeoBluetoothState
        switch central.state {
        case .unknown:
            state = .unknown
        case .resetting:
            state = .resetting
        case .unsupported:
            state = .unsupported
        case .unauthorized:
            state = .unauthorized
        case .poweredOff:
            state = .poweredOff
        case .poweredOn:
            state = .poweredOn
        @unknown default:
            state = .unknown
        }
        emit(.bluetoothState(state))

        if central.state == .poweredOn {
            if wantsDiscovery {
                beginDiscovery()
            } else if let peripheral = currentPeripheral,
                      automaticallyReconnect,
                      !intentionalDisconnect,
                      peripheral.state != .connected
            {
                scheduleReconnect(to: peripheral)
            }
        } else if central.state == .poweredOff {
            connectionState = .waitingForBluetooth
        } else if central.state == .unauthorized || central.state == .unsupported {
            connectionState = .failed
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isLikelyNeoDevice(
            peripheral: peripheral,
            advertisementData: advertisementData
        ) else {
            return
        }

        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey]
            as? [CBUUID] ?? [])
            .map { $0.uuidString.uppercased() }
            .sorted()
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey]
            as? Data
        let connectable = (
            advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber
        )?.boolValue
        let device = NeoDevice(
            id: peripheral.identifier,
            name: advertisedName ?? peripheral.name,
            rssi: RSSI.intValue,
            advertisedServiceUUIDs: services,
            manufacturerData: manufacturerData,
            isConnectable: connectable
        )

        peripheralsByID[device.id] = peripheral
        devicesByID[device.id] = device
        emit(.deviceDiscovered(device))
        emit(
            .raw(
                NeoRawEvent(
                    layer: .advertisement,
                    direction: .observed,
                    deviceID: device.id,
                    bytes: manufacturerData,
                    detail: "name=\(device.name ?? "unknown") rssi=\(device.rssi) "
                        + "services=\(services.joined(separator: ","))"
                )
            )
        )
        if reconnectScanActive,
           connectedDeviceIdentity?.hasSamePhysicalIdentity(as: device) == true,
           automaticallyReconnect,
           !intentionalDisconnect
        {
            connect(to: device.id)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reconnectScanActive = false
        resetProtocolState()
        currentPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connected
        emitRaw(
            layer: .gatt,
            direction: .inbound,
            peripheral: peripheral,
            detail: "connected; discovering services"
        )
        peripheral.discoverServices(nil)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectionState = .failed
        emitFailure(
            stage: "connect",
            message: error?.localizedDescription ?? "CoreBluetooth failed to connect"
        )
        scheduleReconnect(to: peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        emitRaw(
            layer: .gatt,
            direction: .inbound,
            peripheral: peripheral,
            detail: "disconnected"
                + (error.map { ": \($0.localizedDescription)" } ?? "")
        )
        resetProtocolState()
        connectionState = .disconnected

        if intentionalDisconnect {
            currentPeripheral = nil
            connectedDeviceIdentity = nil
        } else {
            scheduleReconnect(to: peripheral)
        }
    }
}

extension CoreBluetoothNeoTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            emitFailure(stage: "gatt-services", message: error.localizedDescription)
            return
        }

        let services = peripheral.services ?? []
        pendingServiceUUIDs = Set(
            services.map { $0.uuid.uuidString.uppercased() }
        )
        for service in services {
            let uuid = service.uuid.uuidString.uppercased()
            emit(.gattService(deviceID: peripheral.identifier, uuid: uuid))
            emitRaw(
                layer: .gatt,
                direction: .observed,
                peripheral: peripheral,
                service: service,
                detail: "service discovered"
            )
            peripheral.discoverCharacteristics(nil, for: service)
        }

        if services.isEmpty {
            emitFailure(stage: "gatt-services", message: "No GATT services were discovered")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        defer {
            pendingServiceUUIDs.remove(service.uuid.uuidString.uppercased())
            if pendingServiceUUIDs.isEmpty,
               writeCharacteristic == nil || receiveCharacteristic == nil
            {
                emitFailure(
                    stage: "gatt-characteristics",
                    message: "Neo protocol service was found without usable write/receive channels"
                )
            }
        }

        if let error {
            emitFailure(stage: "gatt-characteristics", message: error.localizedDescription)
            return
        }

        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString.uppercased()
            let properties = characteristic.properties.traceNames
            emit(
                .gattCharacteristic(
                    deviceID: peripheral.identifier,
                    serviceUUID: service.uuid.uuidString.uppercased(),
                    uuid: uuid,
                    properties: properties
                )
            )
            emitRaw(
                layer: .gatt,
                direction: .observed,
                peripheral: peripheral,
                characteristic: characteristic,
                detail: "characteristic discovered properties=\(properties.joined(separator: ","))"
            )

            if UUIDs.writeCharacteristics.contains(uuid) {
                writeCharacteristic = characteristic
            }
            if UUIDs.receiveCharacteristics.contains(uuid) {
                receiveCharacteristic = characteristic
            }

            if UUIDs.readableMetadataCharacteristics.contains(uuid),
               characteristic.properties.contains(.read)
            {
                peripheral.readValue(for: characteristic)
            }

            if characteristic.properties.contains(.notify)
                || characteristic.properties.contains(.indicate)
            {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            emitFailure(stage: "gatt-notify", message: error.localizedDescription)
            return
        }

        emitRaw(
            layer: .gatt,
            direction: .observed,
            peripheral: peripheral,
            characteristic: characteristic,
            detail: characteristic.isNotifying
                ? "notifications enabled"
                : "notifications disabled"
        )
        beginHandshakeIfReady()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            emitFailure(stage: "gatt-read", message: error.localizedDescription)
            return
        }
        guard let data = characteristic.value else {
            return
        }
        let receivedWallClockMilliseconds = UInt64(
            Date().timeIntervalSince1970 * 1_000
        )
        let receivedUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

        let uuid = characteristic.uuid.uuidString.uppercased()
        emitRaw(
            layer: .gatt,
            direction: .inbound,
            peripheral: peripheral,
            characteristic: characteristic,
            bytes: data,
            detail: "characteristic value"
        )
        readStandardValue(data, characteristicUUID: uuid)

        if UUIDs.receiveCharacteristics.contains(uuid) {
            processNeoData(
                data,
                peripheral: peripheral,
                characteristic: characteristic,
                receivedWallClockMilliseconds: receivedWallClockMilliseconds,
                receivedUptimeNanoseconds: receivedUptimeNanoseconds
            )
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        writeInFlight = false
        if let error {
            emitFailure(stage: "gatt-write", message: error.localizedDescription)
            pendingWriteChunks.removeAll()
            return
        }
        drainWriteQueue()
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        drainWriteQueue()
    }
}

private extension CBCharacteristicProperties {
    var traceNames: [String] {
        var names: [String] = []
        if contains(.broadcast) { names.append("broadcast") }
        if contains(.read) { names.append("read") }
        if contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if contains(.write) { names.append("write") }
        if contains(.notify) { names.append("notify") }
        if contains(.indicate) { names.append("indicate") }
        if contains(.authenticatedSignedWrites) { names.append("signedWrite") }
        if contains(.extendedProperties) { names.append("extended") }
        if contains(.notifyEncryptionRequired) { names.append("notifyEncrypted") }
        if contains(.indicateEncryptionRequired) { names.append("indicateEncrypted") }
        return names
    }
}
