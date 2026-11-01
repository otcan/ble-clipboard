import AppKit
import CoreBluetooth
import Combine
import Foundation
import OSLog

final class DuckerBluetooth: NSObject, ObservableObject {
    struct Candidate: Identifiable {
        let id: UUID
        let name: String
    }
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var status = "Disconnected"
    @Published private(set) var deviceName = "Flipper Zero"
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var progress = 0.0
    @Published private(set) var capacity = 0

    private static let service = CBUUID(string: "8FE5B3D5-2E7F-4A98-2A48-7ACC60FE0000")
    private static let rx = CBUUID(string: "19ED82AE-ED21-4C9D-4145-228E62FE0000")
    private static let tx = CBUUID(string: "19ED82AE-ED21-4C9D-4145-228E61FE0000")
    private static let logger = Logger(subsystem: "com.oguzcanunver.BLEClipboardMac", category: "DuckerBluetooth")
    private var central: CBCentralManager?
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var session = DuckerSession()
    private var decoder = DuckerLineDecoder()
    private var writes: [Data] = []
    private var writeInFlight = false
    private var watchdog: DispatchWorkItem?
    private var pacedWrite: DispatchWorkItem?
    private var wantsScan = false
    private let preview: Bool
    private var sleepObserver: NSObjectProtocol?

    init(preview: Bool = false) {
        self.preview = preview
        super.init()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isConnected else { return }
            self.disconnect()
            self.status = "Disconnected before sleep. Check the USB target before resending."
        }
    }

    deinit { if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) } }

    func scan() {
        guard !preview, !isBusy else { return }
        disconnect()
        wantsScan = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central?.state == .poweredOn { startScan() }
        else if let central { status = Self.unavailableStatus(for: central.state) }
    }

    static func unavailableStatus(for state: CBManagerState) -> String {
        switch state {
        case .unknown: return "Waiting for Bluetooth initialization or authorization..."
        case .resetting: return "Bluetooth is resetting. Reconnect when it is available."
        case .unsupported: return "Bluetooth LE is not supported on this Mac."
        case .unauthorized: return "Allow Bluetooth access for the preview app in System Settings."
        case .poweredOff: return "Turn on Bluetooth in System Settings."
        case .poweredOn: return "Bluetooth is available."
        @unknown default: return "Bluetooth is unavailable. Check System Settings."
        }
    }

    private func startScan() {
        guard let central, central.state == .poweredOn, wantsScan else { return }
        candidates = []
        discovered = [:]
        // Flipper may advertise a short UUID rather than the serial service UUID.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        for item in central.retrieveConnectedPeripherals(withServices: [Self.service]) { remember(item) }
        isScanning = true
        status = "Choose your Flipper"
        deadline(20) { [weak self] in
            self?.central?.stopScan()
            self?.isScanning = false
            self?.status = self?.candidates.isEmpty == true ? "No Flipper found. Open DuckerTheFlipper and enable Bluetooth." : "Choose your Flipper"
        }
    }

    private func remember(_ item: CBPeripheral, name: String? = nil) {
        guard discovered[item.identifier] == nil else { return }
        let title = name ?? item.name ?? "Flipper Zero"
        discovered[item.identifier] = item
        candidates.append(Candidate(id: item.identifier, name: title))
    }

    func connect(_ id: UUID) {
        guard let item = discovered[id], peripheral == nil else { return }
        wantsScan = false
        central?.stopScan()
        isScanning = false
        peripheral = item
        item.delegate = self
        deviceName = item.name ?? "Flipper Zero"
        isConnecting = true
        status = "Connecting to \(deviceName)..."
        central?.connect(item)
        deadline(60) { [weak self] in self?.fail("Pairing timed out. Connect again to retry.") }
    }

    func run(_ compiled: CompiledMacro, hideApp: Bool = false) {
        guard isReady, !isBusy else { return }
        do {
            let events = try session.begin(compiled)
            isBusy = true
            progress = 0
            status = "Confirming target layout..."
            if hideApp { NSApp.hide(nil) }
            handle(events)
            watchJob()
        } catch { status = error.localizedDescription }
    }

    func cancel() {
        guard isBusy else { return }
        status = "Cancelling; keep the USB target focused"
        handle(session.cancel())
    }

    func disconnect() {
        wantsScan = false
        if central?.state == .poweredOn { central?.stopScan() }
        if let item = peripheral { central?.cancelPeripheralConnection(item) }
        clear()
        status = "Disconnected"
    }

    private func clear() {
        watchdog?.cancel()
        pacedWrite?.cancel()
        peripheral?.delegate = nil
        peripheral = nil
        rx = nil
        tx = nil
        writes = []
        writeInFlight = false
        session = DuckerSession()
        decoder = DuckerLineDecoder()
        isScanning = false
        isConnected = false
        isConnecting = false
        isReady = false
        isBusy = false
        capacity = 0
        progress = 0
    }

    private func fail(_ message: String) {
        disconnect()
        status = message
    }

    private func deadline(_ seconds: Double, _ action: @escaping () -> Void) {
        watchdog?.cancel()
        let task = DispatchWorkItem(block: action)
        watchdog = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    private func watchJob() {
        deadline(45) { [weak self] in
            self?.fail("No completion received. Connection closed to stop output. Check the target before resending.")
        }
    }

    private func enqueue(_ data: Data) {
        guard let peripheral, rx != nil else { return }
        let size = min(20, max(1, peripheral.maximumWriteValueLength(for: .withResponse)))
        writes += stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
        writeNext()
    }

    private func writeNext() {
        guard !writeInFlight, pacedWrite == nil, let item = peripheral, let rx, let data = writes.first else { return }
        writeInFlight = true
        item.writeValue(data, for: rx, type: .withResponse)
    }

    private func handle(_ events: [DuckerSession.Event]) {
        for event in events {
            switch event {
            case .write(let data):
                if session.stage == .receiving { status = "Transferring macro to Flipper..." }
                else if session.stage == .verified { status = "Starting USB output..." }
                enqueue(data)
            case .ready(let limit):
                watchdog?.cancel()
                capacity = limit
                isReady = true
                isConnecting = false
                status = "Connected to \(deviceName)"
            case .cancelCapability: break
            case .accepted: status = "Typing on USB target..."
            case .waitingUSB: status = "Waiting for USB target; Stop cancels the queued run"
            case .progress(let fraction): progress = fraction
            case .done(let cancelled):
                watchdog?.cancel()
                isBusy = false
                progress = cancelled ? progress : 1
                status = cancelled ? "Cancelled; some input may already have been typed" : "USB output complete"
            case .failed(let error):
                if error == "ERR:LAYOUT" {
                    fail("Keyboard layout unavailable. Install its .kl file in /ext/badusb/assets/layouts, then reconnect.")
                } else {
                    fail("Flipper rejected the run. Connection closed; check layout, SD card and USB before retrying.")
                }
            case .disconnectToCancel:
                disconnect()
                status = "Connection closed to cancel. Some input may already have been typed."
            }
        }
    }
}

extension DuckerBluetooth: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { if wantsScan { startScan() } }
        else if central.state != .unknown {
            fail(Self.unavailableStatus(for: central.state))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover item: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? item.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.localizedCaseInsensitiveContains("flipper") || services.contains(Self.service) else { return }
        remember(item, name: name)
    }

    func centralManager(_ central: CBCentralManager, didConnect item: CBPeripheral) {
        guard item == peripheral else { return }
        isConnected = true
        Self.logger.notice("BLE link connected; discovering serial service")
        status = "Confirm the Bluetooth pairing code on both devices"
        item.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect item: CBPeripheral, error: Error?) {
        guard item == peripheral else { return }
        fail("Could not connect. Open DuckerTheFlipper and try again.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral item: CBPeripheral, error: Error?) {
        guard item == peripheral else { return }
        let wasBusy = isBusy
        clear()
        status = wasBusy ? "Disconnected during output. Check the target before resending." : "Disconnected"
    }
}

extension DuckerBluetooth: CBPeripheralDelegate {
    func peripheral(_ item: CBPeripheral, didDiscoverServices error: Error?) {
        guard item == peripheral else { return }
        guard error == nil, let service = item.services?.first(where: { $0.uuid == Self.service }) else {
            fail("Ducker serial service not found. Open DuckerTheFlipper, then reconnect.")
            return
        }
        item.discoverCharacteristics([Self.rx, Self.tx], for: service)
    }

    func peripheral(_ item: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard item == peripheral else { return }
        rx = service.characteristics?.first { $0.uuid == Self.rx }
        tx = service.characteristics?.first { $0.uuid == Self.tx }
        guard error == nil, let rx, let tx, rx.properties.contains(.write),
              tx.properties.contains(.notify) || tx.properties.contains(.indicate) else {
            fail("Ducker characteristics are unavailable.")
            return
        }
        item.setNotifyValue(true, for: tx)
    }

    func peripheral(_ item: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard item == peripheral, characteristic == tx else { return }
        guard error == nil, characteristic.isNotifying else { fail("Could not subscribe to Flipper status."); return }
        enqueue(DuckerProtocol.hello)
    }

    func peripheral(_ item: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard item == peripheral, characteristic == rx else { return }
        if let error {
            let detail = error as NSError
            Self.logger.error("GATT write failed: \(detail.domain, privacy: .public) / \(detail.code): \(detail.localizedDescription, privacy: .public)")
            fail("Bluetooth write failed (\(detail.domain) \(detail.code)): \(detail.localizedDescription). No automatic retry.")
            return
        }
        if !writes.isEmpty { writes.removeFirst() }
        writeInFlight = false
        if isBusy { watchJob() }
        let task = DispatchWorkItem { [weak self] in
            self?.pacedWrite = nil
            self?.writeNext()
        }
        pacedWrite = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
    }

    func peripheral(_ item: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard item == peripheral, characteristic == tx else { return }
        guard error == nil, let value = characteristic.value else { fail("Could not read Flipper status."); return }
        do {
            let lines = try decoder.append(value)
            for line in lines {
                if isBusy { watchJob() }
                handle(try session.receive(line))
                if peripheral == nil { break }
            }
        } catch { fail(error.localizedDescription) }
    }
}
