# Changelog

## 0.1.0 - 2026-11-01

- Initial native Mac and Flipper Zero clipboard bridge.
- Authenticated Bluetooth LE text transfer with USB keyboard output.
- US and Turkish Q layouts; validated ASCII, tabs, and line breaks.
- Native editor, file import, clipboard loading, transfer status, and cancellation.
- Redesigned compact Flipper status screen with separated title and detail lines.
- Custom macOS application icon and universal Apple Silicon/Intel bundle.
- Tests, CI, release checksums, and third-party Homebrew tap packaging.

Known limits: 3071 text bytes per request; no arbitrary Unicode; early release is
ad-hoc signed and not Apple-notarized. Broader hardware edge-case testing remains.
