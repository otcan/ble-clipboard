import XCTest
@testable import BLEClipboardMac

final class CompanionTests: XCTestCase {
    let release = CompanionRelease(version: AppVersion("0.5.2")!)

    func metadata(assets: [String]? = nil, changes: [String: Any] = [:]) throws -> Data {
        let names = assets ?? [release.macName, "ble_clipboard.fap", "SHA256SUMS.txt"]
        var json: [String: Any] = [
            "tag_name": release.tag, "draft": false, "prerelease": false, "html_url": release.page.absoluteString,
            "assets": names.map { name in [
                "name": name, "state": "uploaded", "size": 42,
                "browser_download_url": "https://github.com/otcan/ble-clipboard/releases/download/\(release.tag)/\(name)",
            ] as [String: Any] },
        ]
        json.merge(changes) { _, new in new }
        return try JSONSerialization.data(withJSONObject: json)
    }

    func infoPayload() -> Data {
        var data = Data([1]); data.appendLE(UInt16(0)); data.appendLE(UInt16(5)); data.appendLE(UInt16(2))
        data.append(4); data.appendLE(UInt16(88)); data.appendLE(UInt16(2)); data.append(7)
        return data
    }

    func testCanonicalVersionsAndPinnedURLs() {
        XCTAssertEqual(AppVersion("0.5.2")?.description, "0.5.2")
        for invalid in ["0.5", "v0.5.2", "0.5.2\n", "01.5.2", "+0.5.2", "0.5.65536", "../latest", "0..2"] {
            XCTAssertNil(AppVersion(invalid), invalid)
        }
        XCTAssertEqual(release.mac.absoluteString, "https://github.com/otcan/ble-clipboard/releases/download/v0.5.2/BLE-Clipboard-0.5.2-universal.zip")
        XCTAssertEqual(release.flipper.lastPathComponent, "ble_clipboard.fap")
        XCTAssertTrue(release.api.path.hasSuffix("/releases/tags/v0.5.2"))
        XCTAssertFalse(release.api.path.contains("latest"))
        XCTAssertTrue(release.guide.path.contains("/v0.5.2/"))
    }

    func testReleaseRequiresBothExactAssetsAndChecksums() throws {
        XCTAssertEqual(release.availability(status: 200, data: try metadata()), .available(prerelease: false))
        XCTAssertEqual(release.availability(status: 200, data: try metadata(changes: ["prerelease": true])), .available(prerelease: true))
        XCTAssertEqual(release.availability(status: 404, data: Data()), .notPublished)
        XCTAssertEqual(release.availability(status: 403, data: Data()), .unavailable)
        XCTAssertEqual(release.availability(status: 200, data: Data("invalid".utf8)), .unavailable)
        XCTAssertEqual(release.availability(status: 200, data: try metadata(changes: ["draft": true])), .notPublished)
        XCTAssertEqual(release.availability(status: 200, data: try metadata(changes: ["tag_name": "v0.1.0"])), .incomplete)
        for missing in [release.macName, "ble_clipboard.fap", "SHA256SUMS.txt"] {
            let names = [release.macName, "ble_clipboard.fap", "SHA256SUMS.txt"].filter { $0 != missing }
            XCTAssertEqual(release.availability(status: 200, data: try metadata(assets: names)), .incomplete)
        }
        XCTAssertEqual(release.availability(status: 200, data: try metadata(assets: [release.macName, "ble_clipboard.fap", "SHA256SUMS.txt", "ble_clipboard.fap"])), .incomplete)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata()) as? [String: Any])
        var assets = try XCTUnwrap(json["assets"] as? [[String: Any]])
        assets[0]["browser_download_url"] = "https://example.com/app.zip"
        json["assets"] = assets
        XCTAssertEqual(release.availability(status: 200, data: try JSONSerialization.data(withJSONObject: json)), .incomplete)
        XCTAssertFalse(ReleaseAvailability.unavailable.canDownload)
        XCTAssertTrue(ReleaseAvailability.available(prerelease: true).canDownload)
    }

    func testOptionalVersionQueryKeepsLegacyConnectionsAndJobState() throws {
        let helper = TransferProtocolTests()
        var old = TransferSession()
        XCTAssertEqual(try old.receive(helper.ready()), [.ready(65536, "Test Flipper")])
        XCTAssertEqual(try old.receive(.init(command: .infoReply, payload: infoPayload())), [])
        var ready = helper.ready(); ready.payload[8] = 63
        var session = TransferSession()
        let events = try session.receive(ready)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(try helper.request(events[1]), .init(command: .info))
        _ = try session.begin(helper.plan(), jobID: 7)
        let stage = session.stage
        for payload in [Data(), Data(repeating: 0, count: 13), infoPayload() + Data([0])] {
            XCTAssertEqual(try session.receive(.init(command: .infoReply, payload: payload)), [])
            XCTAssertEqual(session.stage, stage)
            XCTAssertEqual(session.jobID, 7)
        }
        let info = try XCTUnwrap(CompanionInfo(payload: infoPayload()))
        XCTAssertEqual(try session.receive(.init(command: .infoReply, payload: infoPayload())), [.companionInfo(info)])
        XCTAssertEqual(info.version.description, "0.5.2")
        XCTAssertEqual(info.sdkMajor, 88)
        XCTAssertEqual(session.stage, stage)
        XCTAssertEqual(session.jobID, 7)
        XCTAssertEqual(try session.receive(.init(command: .infoReply, payload: infoPayload())), [])
        var decoder = TransferFrameDecoder()
        let frame = TransferFrame(command: .infoReply, payload: infoPayload())
        XCTAssertEqual(try decoder.append(frame.encoded().prefix(5)), [])
        XCTAssertEqual(try decoder.append(frame.encoded().dropFirst(5)), [frame])
    }

    func testWindowsReleaseRequiresMatchingWindowsAssetsToo() throws {
        let current = CompanionRelease(version: AppVersion("0.5.4")!)
        let names = [current.macName, "ble_clipboard.fap", "SHA256SUMS.txt", current.windowsInstallerName, current.windowsPortableName]
        var json: [String: Any] = ["tag_name": current.tag, "draft": false, "prerelease": false, "html_url": current.page.absoluteString]
        func data(_ names: [String]) throws -> Data {
            json["assets"] = names.map { ["name": $0, "state": "uploaded", "size": 1, "browser_download_url": "https://github.com/otcan/ble-clipboard/releases/download/\(current.tag)/\($0)"] as [String: Any] }
            return try JSONSerialization.data(withJSONObject: json)
        }
        XCTAssertEqual(current.availability(status: 200, data: try data(names)), .available(prerelease: false))
        XCTAssertEqual(current.availability(status: 200, data: try data(Array(names.dropLast()))), .incomplete)
        XCTAssertFalse(release.includesWindows)
    }

    @MainActor func testPreviewChecksNeverOpenTheNetwork() async {
        let check = CompanionReleaseCheck(release: release, preview: true)
        await check.check()
        XCTAssertEqual(check.availability, .notPublished)
    }

    @MainActor func testReleaseCheckUsesPinnedAnonymousGETAndHandlesOffline() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseStubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for (status, expected) in [(200, ReleaseAvailability.available(prerelease: false)),
                                   (404, .notPublished), (403, .unavailable)] {
            ReleaseStubProtocol.configure(status: status, data: try metadata(), offline: false)
            let check = CompanionReleaseCheck(release: release, session: session)
            await check.check()
            XCTAssertEqual(check.availability, expected)
            let request = try XCTUnwrap(ReleaseStubProtocol.lastRequest)
            XCTAssertEqual(request.url, release.api)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
        ReleaseStubProtocol.configure(status: 200, data: Data(), offline: true)
        let check = CompanionReleaseCheck(release: release, session: session)
        await check.check()
        XCTAssertEqual(check.availability, .unavailable)
    }
}

private final class ReleaseStubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var result = (status: 404, data: Data(), offline: false)
    private static var recordedRequest: URLRequest?

    static func configure(status: Int, data: Data, offline: Bool) {
        lock.lock(); defer { lock.unlock() }
        result = (status, data, offline); recordedRequest = nil
    }
    static var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return recordedRequest
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequest = request
        let result = Self.result
        Self.lock.unlock()
        if result.offline { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
