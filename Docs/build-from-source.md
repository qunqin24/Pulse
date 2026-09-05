# Build from source

Pulse is a Swift package (`Package.swift`), macOS 14+, Swift tools 6.0. No test target, no linter. Open the package in Xcode or use the CLI.

User-facing clone-and-run stays in the README. **This file is the toolchain contract.** Shipping a tagged build, Sparkle, and the DMG: [releasing.md](releasing.md).

```bash
swift run Pulse              # build and run (no app bundle, no Sparkle, no SMAppService)
swift build                  # type-check, including #Preview
./Scripts/bundle.sh          # → build.noindex/Pulse.app
./Scripts/dmg.sh             # → build.noindex/Pulse-<version>.dmg
./Scripts/check-localization.sh
```

## Xcode, not Command Line Tools

`xcode-select` must point at **Xcode**. The `#Preview` macro is expanded by a plugin that ships with Xcode. Without it every build fails with `PreviewsMacros plugin not found`.

```bash
xcode-select -p
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

One-off without changing the system setting:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

**Never strip `#Preview` blocks to make the build green.** That hides errors inside them and has shipped a broken build. [decisions/never-strip-previews.md](decisions/never-strip-previews.md).

## Swift 6 and warnings

A clean `swift build` is not the check Xcode runs. Actor-isolation mistakes can be warnings here and hard errors in Xcode, where every `View` is `@MainActor` and one isolation slip produces a wall of “cannot find type X in scope.” Before claiming a change builds:

```bash
swift build -Xswiftc -swift-version -Xswiftc 6
```

Treat remaining warnings as failures.

CI and release pin a **macOS 26** image because `glassEffect` needs that SDK to compile even behind `#available`. A local build on an older SDK will not match CI.

## What `swift run` is not

A loose executable is a different app from `Pulse.app`:

- Different `UserDefaults` domain ([architecture.md](architecture.md))
- Launch-agent login item instead of `SMAppService`
- No Sparkle (`SUFeedURL` / framework missing)
- Safari Full Disk Access, if ever needed for a session cookie, is granted **per application** — the bundled app and `swift run` are not the same grant

Do not test shipping behaviour (updates, login item, Gatekeeper, DMG layout) on `swift run`.
