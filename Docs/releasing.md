# Releasing

There is no Xcode project. `Scripts/bundle.sh` turns the package executable into something macOS treats as an app. Without a bundle there is no `Bundle.main` (no version for the update check, no `SMAppService` login item — hence the launch-agent fallback), and nothing to hand anyone but a build folder.

Toolchain and local `swift build`: [build-from-source.md](build-from-source.md). Why the bundle exists and how defaults migrate: [decisions/bundle-and-defaults.md](decisions/bundle-and-defaults.md). Changelog vs Sparkle: [decisions/release-notes-in-changelog.md](decisions/release-notes-in-changelog.md).

## Version and tag

The version lives in `VERSION` and nowhere else. Tag `v$(cat VERSION)`. The update check reads GitHub’s latest release tag against `CFBundleShortVersionString`.

**Pushing a tag is the whole release.** `CHANGELOG.md` needs a `## x.y.z` section **before** the tag: the workflow stops without one, before it builds. Those words are the GitHub release body **and** the Sparkle update window. Generating notes from commit subjects is a fallback for forgotten entries, not the path for a tagged release.

```bash
# CHANGELOG.md first. Then:
echo 1.0.1 > VERSION && git commit -am "Pulse 1.0.1"
git tag v1.0.1 && git push && git push origin v1.0.1
```

A tag/VERSION mismatch fails the run. A suffix (`v1.1.0-beta.1`) is a GitHub pre-release, excluded from “latest,” so the in-app check ignores it too.

## CI

`.github/workflows/release.yml` builds, packages, publishes, signs the archive, and commits the Sparkle feed. `ci.yml` runs the same build on every push.

Both pin **`macos-26`**, not `macos-latest`. `PanelSurface`’s Liquid Glass needs the macOS 26 SDK to compile even behind `#available`. Workflows check `xcrun --show-sdk-version` first. Warnings fail the build.

Release needs `SPARKLE_PRIVATE_KEY`. It fails without it rather than publishing a version no installed copy would be offered.

## Bundle (`Scripts/bundle.sh`)

- Resource bundle in `Contents/Resources` (`Bundle.module` via `Bundle.main.resourceURL`). Leave it out: English, no provider marks.
- `LSUIElement` = true.
- Universal: `--arch arm64 --arch x86_64`. Zip with **`ditto`**, not `zip` (plain zip flattens bundle symlinks).
- **Output is `build.noindex/`.** Spotlight indexes any `.app`; a project-folder build appears beside the installed copy, and whichever is opened claims the login item and rewrites Claude Code’s status-line path to itself. A `.metadata_never_index` marker was tried and did **not** stop indexing (historical); the `.noindex` suffix is what Spotlight honours. Do not rename it back.
- Sparkle is copied into `Contents/Frameworks` and `@executable_path/../Frameworks` is added to the rpath. Sign **inside out** (nested XPC / updater first).
- Ad-hoc signature is **not** distribution signing. It stops macOS calling the bundle damaged when moved. Gatekeeper still warns on first open until Developer ID + notarisation.

## Disk image (`Scripts/dmg.sh`)

The image is the install guide: Pulse is not notarised, and on macOS 15+ Control-click → Open is gone. Instructions are printed on the window (README-only instructions are not read by people downloading an app).

Finder window layout is a committed `Scripts/dmg-DS_Store` (AppleScript cannot run on CI). Recapture with `./Scripts/dmg.sh --relayout` after changing the backdrop or icon positions. Finder `bounds` **include the title bar** (~28pt taller than a 660×420 backdrop). Backdrop: `Scripts/dmg-background.tiff` (1x and 2x).

Sparkle updates from the **zip**, not the DMG. The image is for people.

## Sparkle

`AppUpdate.swift`. Safe without Apple Developer ID because of the **EdDSA** key: Sparkle refuses any archive not signed by the private half whose public half is in `Info.plist`. Apple signing is recommended by Sparkle, not required. Notarisation would only help Gatekeeper on **first** launch, which no updater can fix.

- `SUFeedURL` is only present in a bundle. `AppUpdate` starts nothing on `swift run`.
- Sparkle’s delegate cannot be main-actor-isolated; `UpdaterRelay` sits between it and the `@Observable` model.
- `didAbortWithError` also fires for the user closing the window; only a genuine feed failure is reported.
- Notes live in the feed `<description>`, **not** `sparkle:releaseNotesLink` (that loads the whole GitHub page in a WebView). If both are present, the link wins — the link must be absent.
- Description: spacing only, no colours or fonts. Sparkle injects `ReleaseNotesColorStyle.css`.
- Public key: `Scripts/sparkle-public-key.txt` (committed). Private key: `SPARKLE_PRIVATE_KEY` only.
- `Scripts/appcast.py` signs the zip and appends to `appcast.xml`. The workflow commits the feed **after** publishing (the feed points at the release asset).

`Scripts/changelog.py` converts one CHANGELOG section to HTML. Grammar: bullets, `**bold**`, `` `code` ``, links.
