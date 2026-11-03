import Combine
import Foundation

struct AppVersion: Equatable, CustomStringConvertible {
    let major: UInt16
    let minor: UInt16
    let patch: UInt16

    init(major: UInt16, minor: UInt16, patch: UInt16) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> UInt16? in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = UInt16(part), String(number) == part else { return nil }
            return number
        }
        guard numbers.count == 3 else { return nil }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

struct CompanionInfo: Equatable {
    let version: AppVersion
    let protocolVersion: UInt8
    let sdkMajor: UInt16
    let sdkMinor: UInt16
    let hardwareTarget: UInt8

    init?(payload: Data) {
        guard payload.count == 13 else { return nil }
        var reader = BinaryReader(payload)
        guard (try? reader.byte()) == 1,
              let major = try? reader.u16(), let minor = try? reader.u16(), let patch = try? reader.u16(),
              let wire = try? reader.byte(), wire == 4,
              let sdkMajor = try? reader.u16(), sdkMajor > 0,
              let sdkMinor = try? reader.u16(), let target = try? reader.byte(), target == 7 else { return nil }
        self.version = AppVersion(major: major, minor: minor, patch: patch)
        self.protocolVersion = wire; self.sdkMajor = sdkMajor; self.sdkMinor = sdkMinor
        self.hardwareTarget = target
    }
}

enum ReleaseAvailability: Equatable {
    case notChecked, checking, notPublished, incomplete, unavailable
    case available(prerelease: Bool)

    var canDownload: Bool { if case .available = self { return true }; return false }
    var title: String {
        switch self {
        case .notChecked: return "Release not checked"
        case .checking: return "Checking matching release..."
        case .notPublished: return "Not published yet"
        case .incomplete: return "Matching release assets incomplete"
        case .unavailable: return "Release check unavailable"
        case .available(let prerelease): return prerelease ? "Matching prerelease available" : "Matching release available"
        }
    }
}

struct CompanionRelease {
    static let repository = URL(string: "https://github.com/otcan/ble-clipboard")!
    static var isPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ||
            Bundle.main.bundleIdentifier?.hasSuffix(".InfoPreview") == true
    }
    static var currentVersion: AppVersion {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return bundled.flatMap(AppVersion.init) ?? AppVersion(BuildRelease.version)!
    }

    let version: AppVersion
    var tag: String { "v\(version)" }
    var page: URL { Self.repository.appendingPathComponent("releases/tag/\(tag)") }
    var api: URL { URL(string: "https://api.github.com/repos/otcan/ble-clipboard/releases/tags/\(tag)")! }
    var guide: URL { Self.repository.appendingPathComponent("blob/\(tag)/README.md") }
    var source: URL { Self.repository.appendingPathComponent("tree/\(tag)") }
    var macName: String { "BLE-Clipboard-\(version)-universal.zip" }
    var mac: URL { asset(macName) }
    var flipper: URL { asset("ble_clipboard.fap") }
    var checksums: URL { asset("SHA256SUMS.txt") }
    private func asset(_ name: String) -> URL { Self.repository.appendingPathComponent("releases/download/\(tag)/\(name)") }

    private struct PublishedRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let state: String
            let size: Int
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let html_url: String
        let assets: [Asset]
    }

    func availability(status: Int, data: Data) -> ReleaseAvailability {
        if status == 404 { return .notPublished }
        guard status == 200, data.count <= 1_000_000,
              let release = try? JSONDecoder().decode(PublishedRelease.self, from: data) else { return .unavailable }
        guard !release.draft else { return .notPublished }
        guard release.tag_name == tag, release.html_url == page.absoluteString,
              release.assets.count <= 64 else { return .incomplete }
        let expected = [(macName, mac), ("ble_clipboard.fap", flipper), ("SHA256SUMS.txt", checksums)]
        guard expected.allSatisfy({ name, url in
            let matches = release.assets.filter { $0.name == name }
            return matches.count == 1 && matches[0].state == "uploaded" && matches[0].size > 0 &&
                matches[0].browser_download_url == url.absoluteString
        }) else { return .incomplete }
        return .available(prerelease: release.prerelease)
    }
}

@MainActor
final class CompanionReleaseCheck: ObservableObject {
    @Published private(set) var availability = ReleaseAvailability.notChecked
    let release: CompanionRelease
    private let preview: Bool
    private let session: URLSession

    init(release: CompanionRelease, preview: Bool = false, session: URLSession? = nil) {
        self.release = release; self.preview = preview
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        self.session = session ?? URLSession(configuration: config)
    }

    func check() async {
        guard availability != .checking else { return }
        if preview { availability = .notPublished; return }
        availability = .checking
        var request = URLRequest(url: release.api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BLE-Clipboard/\(release.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.url == release.api else {
                availability = .unavailable; return
            }
            availability = release.availability(status: response.statusCode, data: data)
        } catch is CancellationError { availability = .notChecked }
        catch { availability = .unavailable }
    }
}

extension Notification.Name {
    static let showCompanionInfo = Notification.Name("BLEClipboard.showCompanionInfo")
}
