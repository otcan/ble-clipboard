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
