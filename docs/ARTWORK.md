# Artwork

Master app icon: `BLEClipboardMac/Resources/AppIcon.png`.
Generated with the built-in OpenAI image-generation tool on 2026-11-01.
`scripts/build_icon.sh` resizes the master and produces `AppIcon.icns`.

## Generation Prompt

> Use case: logo-brand. Asset type: production macOS application icon, square
> 1024x1024, for a native utility called BLE Clipboard that transfers clipboard
> text wirelessly to a Flipper Zero and types it through USB. Create one polished,
> immediately legible macOS app icon: a thick matte off-white clipboard silhouette
> and a single vivid orange right-pointing transfer arrow through its lower half,
> on a softly raised graphite-black macOS superellipse tile with subtle restrained
> dimensional lighting. A tiny mint-green circular connected indicator near the
> clipboard's upper-right. Simple bold geometry, excellent silhouette at 32x32,
> precise high contrast, premium understated desktop utility, centered on canvas
> with normal macOS icon safe margins. The rounded-square tile is the icon itself;
> outside that tile use a genuinely transparent alpha background. No text, no
> letters, no watermark, no extra objects, no animals or mascots, no background
> scene, no large shadow outside the tile. Return a single icon, not a sheet or mockup.

The icon uses a status indicator as part of its mark; it does not indicate the
application's live connection state. Screenshots in the README show the actual
native app rather than an image-generated UI mockup.

## Documentation Screenshots

`docs/assets/mac-quick-paste.jpg` and `docs/assets/mac-macros.jpg` are unedited
2040x1440 captures of the native 0.5.3 Mac UI. They were captured from a separate
copy of the released bundle with the isolated
`com.oguzcanunver.BLEClipboardMac.Readme.InfoPreview` identity and `--ui-testing`.
That mode disables Bluetooth and uses a temporary library with built-in example
macros. The checklist is manually entered, non-sensitive sample text. No clipboard
load, connection, job execution or saved-job transfer was performed. The temporary
app was closed after capture; the owner's installed app was not replaced or quit.
The JPEG files are the original window captures, without cropping, compositing,
retouching or generated UI elements.

`BluetoothClipboard/screenshots/info.png` and `downloads.png` are the existing
genuine 0.5.3 device screenshots exported by qFlipper. Their original PNG bytes
are unchanged. See the [device capture record](../BluetoothClipboard/screenshots/README.md)
for the read-only Info-mode procedure and provenance.

The older `docs/assets/mac-app.png` records the historical 0.1.0 UI; it is not
used to represent the current app.
