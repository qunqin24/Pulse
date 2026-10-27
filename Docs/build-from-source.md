# Build from source

Pulse is a Swift package (`Package.swift`), macOS 14+, Swift tools 6.0. No linter; `swift test` covers rules and parsing ([testing.md](testing.md)). Open the package in Xcode or use the CLI.

User-facing clone-and-run stays in the README. **This file is the toolchain contract.** Shipping a tagged build, Sparkle, and the DMG: [releasing.md](releasing.md).

```bash
swift run Pulse              # build and run (no app bundle, no Sparkle, no SMAppService)
swift build                  # type-check, including #Preview
./Scripts/bundle.sh          # → build.noindex/Pulse.app
./Scripts/dmg.sh             # → build.noindex/Pulse-<version>.dmg
./Scripts/check-localization.sh
```

## mise development environment

The project mise configuration pins Node and Python and selects the full Xcode toolchain through `DEVELOPER_DIR` and PATH. Run `mise trust`, then `mise run build`, `mise run test`, or `mise run localization`. For packaging, use `mise exec -- ./Scripts/bundle.sh`.

Swift, its preview macro plugins and the platform SDK come together from Xcode rather than a separately installed Swift runtime. This integration was checked with Xcode 27.1 / Apple Swift 6.4 / macOS SDK 27.0. Xcode remains a platform SDK installation; the project configuration selects it, and `mise exec -- swift --version` verifies the selected compiler. Change `DEVELOPER_DIR` and the toolchain path together if Xcode is installed elsewhere.

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
swift build
```

Treat remaining warnings as failures.

CI and release pin a **macOS 26** image because `glassEffect` needs that SDK to compile even behind `#available`. A local build on an older SDK will not match CI.

macOS also draws an app's controls to the SDK recorded in its binary, not to the version it is running on, and SwiftPM has stamped the **deployment target** there instead. `Package.swift` sets it explicitly in `linkerSettings` so that every build path agrees — including running the package from Xcode, which does not go through `Scripts/bundle.sh`. If a build ever comes out with the pre-Tahoe controls, read the stamp before looking for a UI bug: `otool -arch arm64 -l <binary> | grep -A 4 LC_BUILD_VERSION`, and anything below 26 is this. [decisions/sdk-stamp-and-appearance.md](decisions/sdk-stamp-and-appearance.md)

## What `swift run` is not

A loose executable is a different app from `Pulse.app`:

- Different `UserDefaults` domain ([architecture.md](architecture.md))
- Launch-agent login item instead of `SMAppService`
- No Sparkle (`SUFeedURL` / framework missing)
- Safari Full Disk Access, if ever needed for a session cookie, is granted **per application** — the bundled app and `swift run` are not the same grant

Do not test shipping behaviour (updates, login item, Gatekeeper, DMG layout) on `swift run`.
