import XCTest
@testable import BLEClipboardMac

final class KeyboardSettingsTests: XCTestCase {
    private let helper = TransferProtocolTests()

    private func ready(capabilities: UInt8 = 127) -> TransferFrame {
        var frame = helper.ready(); frame.payload[8] = capabilities; return frame
    }

    private func reply(_ settings: KeyboardSettings, request: UInt16 = 1, result: UInt8 = 0) -> TransferFrame {
        var data = Data([1]); data.appendLE(request)
        data.append(contentsOf: [result, settings.layout.wireID, settings.target.wireID, settings.useForSavedRuns ? 1 : 0])
        data.appendLE(settings.revision)
        return .init(command: .keyboardReply, payload: data)
    }

    private func connected(_ settings: KeyboardSettings = .init()) throws -> TransferSession {
        var session = TransferSession()
        _ = try session.receive(ready())
        _ = try session.receive(reply(settings))
        return session
    }

    func testOptionalHandshakeAndLegacyCompanions() throws {
        for capability: UInt8 in [31, 63] {
            var old = TransferSession()
            let events = try old.receive(ready(capabilities: capability))
            XCTAssertEqual(events.count, capability == 31 ? 1 : 2)
            XCTAssertFalse(old.supportsKeyboardSync)
            XCTAssertEqual(try old.receive(reply(.init())), [])
            XCTAssertThrowsError(try old.requestKeyboardSettings())
            XCTAssertNoThrow(try old.begin(helper.plan(), jobID: 7))
        }
        var current = TransferSession()
        let events = try current.receive(ready())
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(try helper.request(events[2]), .init(command: .getKeyboard, payload: Data([1, 0])))
        XCTAssertTrue(current.keyboardSyncPending)
        XCTAssertThrowsError(try current.begin(helper.plan(), jobID: 7))
        XCTAssertEqual(try current.receive(reply(.init())), [.keyboardSettings(.init())])
        XCTAssertFalse(current.keyboardSyncPending)
    }

    func testAllLayoutAndTargetIDsAndMalformedReplies() throws {
        for layout in KeyboardLayout.allCases {
            for target in TargetSystem.allCases {
                let settings = KeyboardSettings(layout: layout, target: target, useForSavedRuns: true, revision: 17)
                XCTAssertEqual(KeyboardSettingsReply(payload: reply(settings).payload)?.settings, settings)
                let payload = settings.requestPayload(id: 42)
                XCTAssertEqual(payload.count, 10)
                XCTAssertEqual(Array(payload.prefix(6)), [42, 0, 1, layout.wireID, target.wireID, 1])
            }
        }
        let valid = reply(.init(layout: .turkishQ, useForSavedRuns: true, revision: 1)).payload
        for offset in 0..<valid.count { XCTAssertNil(KeyboardSettingsReply(payload: valid.prefix(offset))) }
        XCTAssertNil(KeyboardSettingsReply(payload: valid + Data([0])))
        for (offset, byte): (Int, UInt8) in [(0, 2), (3, 6), (4, 28), (5, 3), (6, 2)] {
            var bad = valid; bad[offset] = byte
            XCTAssertNil(KeyboardSettingsReply(payload: bad))
        }
        var decoder = TransferFrameDecoder()
        let frame = reply(.init())
        XCTAssertEqual(try decoder.append(frame.encoded().prefix(8)), [])
        XCTAssertEqual(try decoder.append(frame.encoded().dropFirst(8)), [frame])
    }

    func testAcknowledgedUpdatesConflictsAndStaleNotifications() throws {
        var session = try connected()
        let changed = KeyboardSettings(layout: .turkishQ, useForSavedRuns: true)
        let events = try session.setKeyboardSettings(changed)
        XCTAssertEqual(try helper.request(events[0]), .init(command: .setKeyboard, payload: changed.requestPayload(id: 2)))
        XCTAssertEqual(try session.receive(reply(.init(), request: 1)), [])
        XCTAssertTrue(session.keyboardSyncPending)
        var actual = changed; actual.revision = 1
        XCTAssertEqual(try session.receive(reply(actual, request: 2)), [.keyboardSettings(actual)])
        XCTAssertFalse(session.keyboardSyncPending)
        XCTAssertEqual(try session.receive(reply(.init(), request: 0)), [])
        var desired = actual; desired.layout = .german
        _ = try session.setKeyboardSettings(desired)
        var physical = actual; physical.layout = .swedish; physical.revision = 2
        XCTAssertEqual(try session.receive(reply(physical, request: 0)), [.keyboardSettings(physical)])
        XCTAssertTrue(session.keyboardSyncPending)
        let rejected = try session.receive(reply(physical, request: 3, result: 1))
        XCTAssertEqual(rejected.count, 2)
        guard case .keyboardSyncFailed(let message) = rejected[1] else { return XCTFail("Expected keyboard conflict") }
        XCTAssertTrue(message.contains("changed on Flipper"))
        XCTAssertEqual(session.keyboardSettings, physical)
        XCTAssertFalse(session.keyboardSyncPending)
        XCTAssertEqual(session.stage, .idle)
    }

    func testSettingsMessagesNeverExecuteOrResetAnActiveJob() throws {
        var session = try connected()
        _ = try session.begin(helper.plan(), jobID: 7)
        let stage = session.stage
        let changed = KeyboardSettings(layout: .turkishQ, useForSavedRuns: true, revision: 1)
        XCTAssertEqual(try session.receive(reply(changed, request: 0)), [.keyboardSettings(changed)])
        XCTAssertEqual(session.stage, stage); XCTAssertEqual(session.jobID, 7)
        XCTAssertThrowsError(try session.setKeyboardSettings(changed))
        XCTAssertEqual(try session.receive(.init(command: .keyboardReply, payload: Data([1]))), [])
        XCTAssertEqual(session.stage, stage); XCTAssertEqual(session.jobID, 7)
        _ = try session.requestKeyboardSettings()
        let expired = session.keyboardSyncTimedOut()
        XCTAssertEqual(expired.count, 1)
        XCTAssertEqual(session.stage, stage); XCTAssertEqual(session.jobID, 7)
        XCTAssertEqual(session.keyboardSettings, changed)
    }

    func testTimeoutAndSaveFailuresKeepConfirmedSettings() throws {
        var session = try connected(.init(layout: .turkishQ, useForSavedRuns: true, revision: 4))
        let confirmed = try XCTUnwrap(session.keyboardSettings)
        var desired = confirmed; desired.layout = .german
        _ = try session.setKeyboardSettings(desired)
        let rejected = try session.receive(reply(confirmed, request: 2, result: 5))
        XCTAssertEqual(rejected.count, 2)
        XCTAssertEqual(session.keyboardSettings, confirmed)
        _ = try session.setKeyboardSettings(desired)
        XCTAssertEqual(session.keyboardSyncTimedOut().count, 1)
        XCTAssertFalse(session.keyboardSyncPending)
        XCTAssertEqual(session.keyboardSettings, confirmed)
        XCTAssertEqual(try session.receive(reply(desired, request: 3)), []) // Late acknowledgement cannot silently apply.
        XCTAssertNoThrow(try session.requestKeyboardSettings())
    }

    func testLocalDefaultsPersistWithoutBluetoothAndSurviveDisconnect() throws {
        let suite = "BLEClipboard.KeyboardSettingsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bluetooth = ClipboardBluetooth(preferences: defaults)
        bluetooth.changeKeyboard(layout: .turkishQ, target: .windows)
        XCTAssertEqual(bluetooth.keyboardSettings.layout, .turkishQ)
        XCTAssertEqual(bluetooth.keyboardSettings.target, .windows)
        bluetooth.disconnect()
        XCTAssertEqual(bluetooth.keyboardSettings.layout, .turkishQ)
        let restarted = ClipboardBluetooth(preferences: defaults)
        XCTAssertEqual(restarted.keyboardSettings, bluetooth.keyboardSettings)
        XCTAssertFalse(restarted.isConnected)
        let preview = ClipboardBluetooth(preview: true, preferences: defaults)
        preview.changeKeyboard(layout: .german)
        XCTAssertEqual(KeyboardSettings.load(from: defaults).layout, .turkishQ)
        defaults.set(Data("corrupt".utf8), forKey: "keyboard-settings-v1")
        XCTAssertEqual(KeyboardSettings.load(from: defaults), .init())
    }
}
