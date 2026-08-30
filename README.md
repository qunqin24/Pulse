# Pulse

Pulse is a macOS floating usage monitor for Claude Code and Codex. SwiftUI renders the interface while a transparent AppKit `NSPanel` anchors it to the edge of the desktop.

## Run

```bash
swift run Pulse
```

```bash
swift build   # type-check without running
```

Both require `xcode-select` to point at Xcode rather than CommandLineTools, since the `#Preview` macro is expanded by a plugin that ships with Xcode. If a build fails with `PreviewsMacros plugin not found`:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

There is no test target and no linter configured yet.

## Features

It includes:

- a real borderless, transparent floating panel docked to either screen edge — drag it by the rail to reposition it, and it remembers where you left it;
- stays out of other apps' full-screen Spaces by default, with an opt-out in Settings;
- a collapsed dock of per-provider usage rings that expands into a detail card (current session + all-models progress) when a provider is selected;
- provider marks from [Lobe Icons](https://github.com/lobehub/lobe-icons), bundled as SVG and rendered as vectors at every size;
- a menu bar item with a settings window (sidebar + grouped preference cards) for showing/hiding the panel, choosing its screen edge, and picking which providers appear;
- English and Simplified Chinese, following the system language or set explicitly in Settings (applies immediately);
- **real usage, not estimates**: Codex is read live from the endpoint its own CLI polls; Claude Code reports its official 5-hour and weekly limits through the status line hook Pulse registers (connect it in Settings → Claude Code).

## Requirements

The package targets macOS 14 or newer, uses Swift tools 6.0, and can be opened directly in Xcode through `Package.swift`.

## Project layout

All source lives in `Sources/Pulse`, one SwiftUI view per file, with provider icon assets under `Sources/Pulse/Resources`. See [CLAUDE.md](CLAUDE.md) for a deeper architecture walkthrough (the AppKit panel/SwiftUI split, the data model seam, etc.).

## License

Pulse is licensed under the [Apache License 2.0](LICENSE). Bundled third-party
assets retain their original licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
