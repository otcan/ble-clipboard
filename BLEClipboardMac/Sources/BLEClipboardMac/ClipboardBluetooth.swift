import AppKit
import CoreBluetooth
import Combine
import Foundation
import OSLog

final class ClipboardBluetooth: NSObject, ObservableObject {
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
    @Published private(set) var remainingSeconds: UInt32 = 0
    @Published private(set) var elapsedSeconds: UInt32 = 0
    @Published private(set) var standaloneActive = false
    @Published private(set) var companionInfo: CompanionInfo?

    private static let service = CBUUID(string: "A6F1D9C0-7B21-4C9A-8E52-3D7710AA0301")
    private static let rx = CBUUID(string: "A6F1D9C0-7B21-4C9A-8E52-3D7710AA0303")
    private static let tx = CBUUID(string: "A6F1D9C0-7B21-4C9A-8E52-3D7710AA0302")
    private static let logger = Logger(subsystem: "com.oguzcanunver.BLEClipboardMac", category: "ClipboardBluetooth")
    private var central: CBCentralManager?
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var session = TransferSession()
    private var decoder = TransferFrameDecoder()
    private var writes: [Data] = []
    private var writeInFlight = false
    private var watchdog: DispatchWorkItem?
    private var wantsScan = false
    private let preview: Bool
    private var sleepObserver: NSObjectProtocol?

    init(preview: Bool = false) {
        self.preview = preview
        super.init()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isConnected else { return }
            let standalone = self.session.autonomous && self.isBusy
            self.disconnect()
            self.status = standalone ? "Mac sleeping; the standalone run may remain active. Use Stop on Flipper." : "Disconnected before sleep. Check Flipper before resending."
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
        case .unauthorized: return "Allow Bluetooth access for BLE Clipboard in System Settings."
        case .poweredOff: return "Turn on Bluetooth in System Settings."
        case .poweredOn: return "Bluetooth is available."
        @unknown default: return "Bluetooth is unavailable. Check System Settings."
        }
    }

    private func startScan() {
        guard let central, central.state == .poweredOn, wantsScan else { return }
        candidates = []
        discovered = [:]
        central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        for item in central.retrieveConnectedPeripherals(withServices: [Self.service]) { remember(item) }
        isScanning = true
        status = "Choose your Flipper"
        deadline(20) { [weak self] in
            self?.central?.stopScan()
            self?.isScanning = false
            self?.status = self?.candidates.isEmpty == true ? "No Flipper found. Open BLE Clipboard \(BuildRelease.version) on the Flipper." : "Choose your Flipper"
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

    func run(_ compiled: CompiledMacro, hideApp: Bool = false, standalone: Bool = false) {
        transfer(compiled, hideApp: hideApp, standalone: standalone)
    }

    func saveToFlipper(_ compiled: CompiledMacro, id: UUID, name: String) {
        transfer(compiled, saved: .init(id: id, name: name))
    }

    private func transfer(_ compiled: CompiledMacro, hideApp: Bool = false,
                          standalone: Bool = false, saved: SavedProgramRequest? = nil) {
        guard isReady, !isBusy else { return }
        do {
            let events = try session.begin(compiled, saved: saved, standalone: standalone)
            isBusy = true
            standaloneActive = false
            remainingSeconds = 0; elapsedSeconds = 0
            progress = 0
            status = "Preparing macro and target layout..."
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
        let continues = isBusy && session.autonomous
        let wasSaving = isBusy && session.isSaving
        wantsScan = false
        if central?.state == .poweredOn { central?.stopScan() }
        if let item = peripheral { central?.cancelPeripheralConnection(item) }
        clear()
        status = continues ? "Disconnected; the standalone run may remain active. Use Stop on Flipper." :
            wasSaving ? "Disconnected during save; check Flipper's saved list before retrying." : "Disconnected"
    }

    private func clear() {
        watchdog?.cancel()
        peripheral?.delegate = nil
        peripheral = nil
        rx = nil
        tx = nil
        writes = []
        writeInFlight = false
        session = TransferSession()
        decoder = TransferFrameDecoder()
        isScanning = false
        isConnected = false
        isConnecting = false
        isReady = false
        companionInfo = nil
        isBusy = false
        capacity = 0
        progress = 0
        standaloneActive = false
        remainingSeconds = 0; elapsedSeconds = 0
    }

    private func fail(_ message: String) {
        let continues = isBusy && session.autonomous
        disconnect()
        status = message + (continues ? " The standalone run may still be active; use Stop on Flipper." : "")
    }

    private func deadline(_ seconds: Double, _ action: @escaping () -> Void) {
        watchdog?.cancel()
        let task = DispatchWorkItem(block: action)
        watchdog = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    private func watchJob() {
        deadline(45) { [weak self] in
            self?.fail("Flipper status timed out. Check the target and Flipper before resending.")
        }
    }

    private func enqueue(_ data: Data) {
        guard let peripheral, rx != nil else { return }
        let size = min(128, max(1, peripheral.maximumWriteValueLength(for: .withResponse)))
        writes += stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
        writeNext()
    }

    private func writeNext() {
        guard !writeInFlight, let item = peripheral, let rx, let data = writes.first else { return }
        writeInFlight = true
        item.writeValue(data, for: rx, type: .withResponse)
    }

    private func handle(_ events: [TransferSession.Event]) {
        for event in events {
            switch event {
            case .write(let data):
                if session.stage == .receiving { status = "Transferring macro to Flipper..." }
                else if session.stage == .saving { status = "Saving plaintext snapshot to Flipper SD..." }
                else if session.stage == .waitingUSB { status = "Starting USB output..." }
                enqueue(data)
            case .ready(let limit, let name):
                watchdog?.cancel()
                capacity = limit
                deviceName = name
                isReady = true
                isConnecting = false
                status = "Connected to \(deviceName)"
            case .companionInfo(let info): companionInfo = info
            case .accepted:
                standaloneActive = session.autonomous
                status = session.autonomous ? "Standalone run active on Flipper" : "Running on USB target..."
            case .resumed:
                isBusy = true; standaloneActive = true
                status = "Reconnected to the standalone run; Stop is available"
                watchJob()
            case .timer(let elapsed, let remaining):
                elapsedSeconds = elapsed; remainingSeconds = remaining
                if remaining > 0 {
                    status = "Timed sequence running on Flipper"
                    progress = Double(elapsed) / (Double(elapsed) + Double(remaining))
                }
            case .saved:
                watchdog?.cancel(); isBusy = false; standaloneActive = false; progress = 1
                status = "Saved on Flipper SD; not started"
            case .waitingUSB: status = "Waiting for USB target; Stop cancels the queued run"
            case .progress(let fraction): progress = fraction
            case .done(let cancelled):
                watchdog?.cancel()
                isBusy = false
                standaloneActive = false; remainingSeconds = 0
                progress = cancelled ? progress : 1
                status = cancelled ? "Cancelled; some input may already have been typed" : "USB output complete"
            case .failed(let error):
                fail("Flipper rejected the run: \(error). Check the target before retrying.")
            }
        }
    }
}

extension ClipboardBluetooth: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { if wantsScan { startScan() } }
        else if central.state != .unknown {
            fail(Self.unavailableStatus(for: central.state))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover item: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? item.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard services.contains(Self.service) || name.localizedCaseInsensitiveContains("paste") else { return }
        remember(item, name: name)
    }

    func centralManager(_ central: CBCentralManager, didConnect item: CBPeripheral) {
        guard item == peripheral else { return }
        isConnected = true
        Self.logger.notice("BLE link connected; discovering clipboard service")
        status = "Discovering BLE Clipboard \(BuildRelease.version) service..."
        item.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect item: CBPeripheral, error: Error?) {
        guard item == peripheral else { return }
        fail("Could not connect. Open BLE Clipboard \(BuildRelease.version) on the Flipper and try again.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral item: CBPeripheral, error: Error?) {
        guard item == peripheral else { return }
        let wasBusy = isBusy
        let standalone = session.autonomous && wasBusy
        let wasSaving = session.isSaving && wasBusy
        clear()
        status = standalone ? "Standalone run may remain active. Reconnect for Stop, or use physical Stop." :
            wasSaving ? "Save status unknown; check Flipper's saved list before retrying." :
            wasBusy ? "Disconnected during output. Check the target before resending." : "Disconnected"
    }
}

extension ClipboardBluetooth: CBPeripheralDelegate {
    func peripheral(_ item: CBPeripheral, didDiscoverServices error: Error?) {
        guard item == peripheral else { return }
        guard error == nil, let service = item.services?.first(where: { $0.uuid == Self.service }) else {
            fail("BLE Clipboard \(BuildRelease.version) service not found. Install the matching Flipper app, then reconnect.")
            return
        }
        item.discoverCharacteristics([Self.rx, Self.tx], for: service)
        status = "Discovering clipboard characteristics..."
    }

    func peripheral(_ item: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard item == peripheral else { return }
        rx = service.characteristics?.first { $0.uuid == Self.rx }
        tx = service.characteristics?.first { $0.uuid == Self.tx }
        guard error == nil, let rx, let tx, rx.properties.contains(.write),
              tx.properties.contains(.notify) || tx.properties.contains(.indicate) else {
            fail("BLE Clipboard characteristics are unavailable.")
            return
        }
        item.setNotifyValue(true, for: tx)
        status = "Securing the status channel; approve pairing if prompted"
    }

    func peripheral(_ item: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard item == peripheral, characteristic == tx else { return }
        guard error == nil, characteristic.isNotifying else { fail("Could not subscribe to Flipper status."); return }
        status = "Checking BLE Clipboard protocol v4..."
        enqueue(TransferProtocol.hello)
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
        writeNext()
    }

    func peripheral(_ item: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard item == peripheral, characteristic == tx else { return }
        guard error == nil, let value = characteristic.value else { fail("Could not read Flipper status."); return }
        do {
            let frames = try decoder.append(value)
            for frame in frames {
                let events = try session.receive(frame)
                if isBusy, !events.isEmpty { watchJob() }
                handle(events)
                if peripheral == nil { break }
            }
        } catch { fail(error.localizedDescription) }
    }
}
