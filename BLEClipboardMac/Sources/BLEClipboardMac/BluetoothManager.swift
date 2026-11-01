import AppKit
import CoreBluetooth
import Foundation
import OSLog

final class BluetoothManager: NSObject, ObservableObject {
    private enum Command: UInt8 {
        case hello = 0x01
        case type = 0x02
        case cancel = 0x04
        case ready = 0x81
        case accepted = 0x82
        case done = 0x83
        case error = 0xFF
    }

    private static let logger = Logger(subsystem: "com.oguzcanunver.BLEClipboardMac", category: "connection")
    private static let serviceUUID = CBUUID(string: "A6F1D9C0-7B21-4C9A-8E52-3D7710AA0001")
    private static let txUUID = CBUUID(string: "A6F1D9C0-7B21-4C9A-8E52-3D7710AA0002")
    private static let rxUUID = CBUUID(string: "A6F1D9C0-7B21-4C9A-8E52-3D7710AA0003")
    private static let peripheralIdentifierKey = "usbPastePeripheralIdentifier"

    @Published private(set) var status = "Starting Bluetooth..." {
        didSet { Self.logger.notice("\(self.status, privacy: .public)") }
    }
    @Published private(set) var isReady = false
    @Published private(set) var isScanning = false
    @Published private(set) var deviceName = ""
    @Published private(set) var lastResult = ""
    @Published private(set) var isBusy = false
    @Published private(set) var transferProgress = 0.0
    @Published private(set) var lastDeliveryAt: Date?
    @Published private(set) var lastDeliveryBytes = 0

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    private var decoder = ClipboardFrameDecoder()
    private var writeChunks: [Data] = []
    private var writeIndex = 0
    private var hideAfterAccepted = false
    private var shouldReconnect = true
    private var excludedIdentifiers: Set<UUID> = []
    private var timeout: DispatchWorkItem?
    private var reconnectWork: DispatchWorkItem?
    private var cancelAfterWrite = false
    private var actionAccepted = false
    private var pendingTextBytes = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan(resetCandidates: Bool = true) {
        guard central.state == .poweredOn else {
            status = "Bluetooth is unavailable"
            return
        }
        shouldReconnect = true
        disconnect(clearReconnect: false)
        if resetCandidates { excludedIdentifiers.removeAll() }

        if let identifierText = UserDefaults.standard.string(forKey: Self.peripheralIdentifierKey),
           let identifier = UUID(uuidString: identifierText),
           !excludedIdentifiers.contains(identifier),
           let known = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            attach(to: known)
            return
        }

        if let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
            .first(where: { !excludedIdentifiers.contains($0.identifier) }) {
            attach(to: connected)
            return
        }

        isScanning = true
        status = "Looking for BLE Clipboard..."
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        armTimeout(seconds: 20) { [weak self] in
            guard let self else { return }
            self.central.stopScan()
            self.isScanning = false
            self.status = "Flipper not found. Open BLE Clipboard on the Flipper, then Connect."
        }
    }

    private func armTimeout(seconds: Double, action: @escaping () -> Void) {
        timeout?.cancel()
        let work = DispatchWorkItem(block: action)
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func attach(to peripheral: CBPeripheral) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        isScanning = false
        status = "Attaching to \(peripheral.name ?? "Paste Flipper")..."
        central.connect(peripheral)
        armTimeout(seconds: 15) { [weak self] in
            self?.forgetPeripheralAndScan("Connection timed out; searching again...")
        }
    }

    private func forgetPeripheralAndScan(_ message: String) {
        UserDefaults.standard.removeObject(forKey: Self.peripheralIdentifierKey)
        if let peripheral {
            excludedIdentifiers.insert(peripheral.identifier)
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
        status = message
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectWork?.cancel()
        guard shouldReconnect else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.shouldReconnect else { return }
            self.scan(resetCandidates: false)
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func disconnect(clearReconnect: Bool = true) {
        reconnectWork?.cancel()
        if clearReconnect { shouldReconnect = false }
        central.stopScan()
        isScanning = false
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        resetConnection()
        status = "Disconnected"
    }

    func type(_ text: String, layout: UInt8, hideOnAccept: Bool = true) {
        guard isReady, !isBusy else { return }
        let data: Data
        do {
            data = try USBText.payload(text, layout: layout)
        } catch {
            lastResult = error.localizedDescription
            return
        }
        hideAfterAccepted = hideOnAccept
        pendingTextBytes = data.count - 1
        transferProgress = 0
        actionAccepted = false
        send(command: .type, payload: data)
        status = "Sending text to USB target..."
        armTimeout(seconds: 120) { [weak self] in
            guard let self else { return }
            self.disconnect()
            self.status = "No completion received. Check the target before resending."
        }
    }

    func cancel() {
        guard isReady else { return }
        hideAfterAccepted = false
        if !writeChunks.isEmpty || !actionAccepted {
            cancelAfterWrite = true
            return
        }
        send(command: .cancel, payload: Data())
    }

    private func resetConnection() {
        timeout?.cancel()
        peripheral?.delegate = nil
        peripheral = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        decoder = ClipboardFrameDecoder()
        writeChunks.removeAll()
        writeIndex = 0
        isReady = false
        isBusy = false
        transferProgress = 0
        hideAfterAccepted = false
        cancelAfterWrite = false
        actionAccepted = false
        deviceName = ""
    }

    private func sendHello() {
        send(command: .hello, payload: Data("BTPASTE-MAC/2".utf8))
        status = "Confirm the pairing code on both devices"
        armTimeout(seconds: 60) { [weak self] in
            guard let self else { return }
            self.disconnect()
            self.status = "Pairing or handshake timed out. Connect to try again."
        }
    }

    private func send(command: Command, payload: Data) {
        guard let peripheral, rxCharacteristic != nil, writeChunks.isEmpty else { return }
        let frame = ClipboardFrame(command: command.rawValue, payload: payload).encoded()
        isBusy = true

        let maximum = min(128, max(1, peripheral.maximumWriteValueLength(for: .withResponse)))
        writeChunks = stride(from: 0, to: frame.count, by: maximum).map {
            frame.subdata(in: $0..<min($0 + maximum, frame.count))
        }
        writeIndex = 0
        writeNextChunk()
    }

    private func writeNextChunk() {
        guard let peripheral, let rxCharacteristic, writeIndex < writeChunks.count else { return }
        peripheral.writeValue(writeChunks[writeIndex], for: rxCharacteristic, type: .withResponse)
    }

    private func handle(command: Command?, payload: Data) {
        let message = String(data: payload, encoding: .utf8) ?? ""
        switch command {
        case .ready:
            timeout?.cancel()
            if let peripheral {
                UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.peripheralIdentifierKey)
            }
            isBusy = false
            isReady = true
            deviceName = message
            status = "Paired with \(message)"
            lastResult = "Ready"
        case .accepted:
            transferProgress = 1
            actionAccepted = true
            status = "Text accepted for USB output"
            if cancelAfterWrite {
                cancelAfterWrite = false
                cancel()
                return
            }
            if hideAfterAccepted {
                hideAfterAccepted = false
                NSApp.hide(nil)
            }
        case .done:
            if message != "cancelled" {
                lastDeliveryAt = Date()
                lastDeliveryBytes = pendingTextBytes
            }
            actionAccepted = false
            timeout?.cancel()
            isBusy = false
            status = "Paired with \(deviceName)"
            lastResult = message.capitalized
        case .error:
            actionAccepted = false
            cancelAfterWrite = false
            timeout?.cancel()
            isBusy = false
            status = "Flipper rejected the request"
            lastResult = message
            hideAfterAccepted = false
        default:
            break
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            shouldReconnect = true
            scan()
        } else {
            disconnect()
            status = "Bluetooth is unavailable"
            isReady = false
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard self.peripheral == nil, isScanning,
              !excludedIdentifiers.contains(peripheral.identifier) else { return }
        central.stopScan()
        attach(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        status = "Discovering secure service..."
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        status = error?.localizedDescription ?? "Connection failed"
        forgetPeripheralAndScan(status)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        resetConnection()
        status = "Flipper disconnected"
        scheduleReconnect()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil else {
            status = error?.localizedDescription ?? "Service discovery failed"
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            forgetPeripheralAndScan("Refreshing the saved Flipper connection...")
            return
        }
        status = "Discovering clipboard controls..."
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        guard error == nil else {
            status = error?.localizedDescription ?? "Characteristic discovery failed"
            return
        }
        rxCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.rxUUID })
        txCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.txUUID })
        guard let txCharacteristic, rxCharacteristic != nil else {
            let discovered = service.characteristics?.map(\.uuid.uuidString).joined(separator: ", ") ?? "none"
            status = "Clipboard characteristics not found (saw: \(discovered))"
            return
        }
        status = "Enabling secure responses..."
        peripheral.setNotifyValue(true, for: txCharacteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, characteristic.uuid == Self.txUUID, characteristic.isNotifying else {
            status = error?.localizedDescription ?? "Could not enable secure responses"
            return
        }
        sendHello()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        if let error {
            let failure = error as NSError
            let pairingError = failure.domain == CBATTErrorDomain &&
                [CBATTError.insufficientAuthentication.rawValue,
                 CBATTError.insufficientEncryption.rawValue].contains(failure.code)
            if pairingError {
                disconnect()
                status = "Pairing incomplete. Connect, then approve the code on both devices."
                return
            }
            timeout?.cancel()
            status = error.localizedDescription
            writeChunks.removeAll()
            isBusy = false
            hideAfterAccepted = false
            return
        }
        writeIndex += 1
        transferProgress = Double(writeIndex) / Double(max(1, writeChunks.count))
        if writeIndex < writeChunks.count {
            writeNextChunk()
        } else {
            writeChunks.removeAll()
            writeIndex = 0
            if cancelAfterWrite && actionAccepted {
                cancelAfterWrite = false
                cancel()
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, characteristic.uuid == Self.txUUID, let value = characteristic.value else {
            if let error { status = error.localizedDescription }
            return
        }
        do {
            for frame in try decoder.append(value) {
                handle(command: Command(rawValue: frame.command), payload: frame.payload)
            }
        } catch {
            disconnect()
            status = "Invalid response from Flipper. Reconnect to retry."
        }
    }
}
