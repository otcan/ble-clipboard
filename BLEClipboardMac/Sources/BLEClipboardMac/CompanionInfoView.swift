import AppKit
import SwiftUI

struct CompanionInfoView: View {
    @ObservedObject var bluetooth: ClipboardBluetooth
    @StateObject private var check: CompanionReleaseCheck
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var refreshID = 0

    init(bluetooth: ClipboardBluetooth) {
        self.bluetooth = bluetooth
        _check = StateObject(wrappedValue: CompanionReleaseCheck(
            release: .init(version: CompanionRelease.currentVersion),
            preview: CompanionRelease.isPreview))
    }

    private var compatibility: String {
        guard bluetooth.isReady else { return "Not connected" }
        guard let info = bluetooth.companionInfo else { return "Protocol 4; app version unknown" }
        return info.version == check.release.version ? "Matching app versions" : "Protocol 4; app versions differ"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 36, height: 36)
                Text("Info & Companions").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).help("Close Info & Companions")
                    .accessibilityLabel("Close Info & Companions")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        infoRow("Mac app", check.release.version.description)
                        infoRow("Flipper app", bluetooth.companionInfo?.version.description ?? (bluetooth.isReady ? "Unknown" : "Not connected"))
                        infoRow("Compatibility", compatibility)
                        if let info = bluetooth.companionInfo {
                            infoRow("Flipper build API", "\(info.sdkMajor).\(info.sdkMinor) / Target \(info.hardwareTarget)")
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Companion Downloads").font(.headline)
                            Spacer()
                            Text(check.release.tag).font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            if check.availability == .checking { ProgressView().controlSize(.small) }
                            else { Image(systemName: check.availability.canDownload ? "checkmark.circle" : "circle.dashed") }
                            Text(check.availability.title).font(.callout).accessibilityIdentifier("release-availability")
                            Spacer(minLength: 8)
                            Button { refreshID += 1 } label: {
                                Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                            }
                            .disabled(check.availability == .checking)
                            .help("Check this release on GitHub")
                            .accessibilityLabel("Check Release Availability")
                        }.foregroundStyle(.secondary)
                        download("Mac App", detail: "macOS 14+ / Apple Silicon + Intel", icon: "laptopcomputer", url: check.release.mac, id: "download-mac")
                        if check.release.includesWindows {
                            download("Windows App", detail: "Windows 10/11 / x64 / unsigned beta installer", icon: "pc", url: check.release.windowsInstaller, id: "download-windows")
                        }
                        download("Flipper App", detail: "Firmware 1.5.1 / API 88.2 / .fap", icon: "antenna.radiowaves.left.and.right", url: check.release.flipper, id: "download-flipper")
                        HStack(spacing: 18) {
                            releaseLink("Release Notes", check.release.page)
                            releaseLink("Checksums", check.release.checksums)
                            releaseLink("Setup Guide", check.release.guide)
                            releaseLink("Source Code", check.release.source)
                        }.font(.callout)
                    }
                    Divider()
                    HStack(spacing: 18) {
                        Link("Repository", destination: CompanionRelease.repository)
                        Link("Report an Issue", destination: CompanionRelease.repository.appendingPathComponent("issues/new"))
                        LicenseNoticesButton()
                    }.font(.callout)
                    Text("GPL-3.0-only").font(.caption).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 580, height: 590)
        .task(id: refreshID) { await check.check() }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 108, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout)
    }

    private func download(_ title: String, detail: String, icon: String, url: URL, id: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                guard check.availability.canDownload else { return }
                openURL(url)
            } label: { Label("Download", systemImage: "arrow.down.to.line") }
                .buttonStyle(.bordered).disabled(!check.availability.canDownload)
                .accessibilityIdentifier(id)
        }.padding(.vertical, 4)
    }

    private func releaseLink(_ title: String, _ url: URL) -> some View {
        Button(title) {
            guard check.availability.canDownload else { return }
            openURL(url)
        }.buttonStyle(.link).disabled(!check.availability.canDownload)
    }
}
