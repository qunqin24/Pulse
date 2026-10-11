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
- **Icon: `AppIcon/AppIcon.icon`**, an Icon Composer document, compiled by `actool` into `Assets.car` plus a flattened `AppIcon.icns`; `CFBundleIconName` points at it. One layer (`mark.svg`, white stem and lime bowl), so the glass treats the P as one shape — as two layers the colour break drew a line in the clear and tinted modes. Outlines only, no strokes: Icon Composer reads an open stroked path as enclosing the area its chord closes, and the shadow drew that chord across the empty counter. Open it in Icon Composer to edit. `pulse-icon-1024.png` (README) and the Raycast icon are exported from it with `ictool`, `--rendition Default`; re-export them when it changes. `pulse-mark.svg` is the mark alone, one colour.
- `CFBundleURLTypes` registers `pulse` for settings/account navigation. The developer kit is copied to `Contents/Resources/Integrations` from an explicit file list: scripts, Raycast source, manifest, lockfile, icon and tests; no `node_modules` or generated extension output. This copy needs no Node.js build on release CI. [integrations.md](integrations.md)
- Universal: `--arch arm64 --arch x86_64`. Zip with **`ditto`**, not `zip` (plain zip flattens bundle symlinks).
- **The SDK stamp is checked, not assumed.** macOS draws an app's controls to the SDK version in its `LC_BUILD_VERSION`, and below 26 it uses the previous design. `Package.swift` stamps 26.0 in `linkerSettings` — the manifest, not this script, so that a build run from Xcode matches a release — and this script reads it back off **every slice** after linking and refuses to package anything lower. The flag alone is not enough: when SwiftPM last got this wrong there was no error and no failing test, only an app drawn the old way. [decisions/sdk-stamp-and-appearance.md](decisions/sdk-stamp-and-appearance.md)
- **Output is `build.noindex/`.** Spotlight indexes any `.app`; a project-folder build appears beside the installed copy, and whichever is opened claims the login item and rewrites Claude Code’s status-line path to itself. A `.metadata_never_index` marker was tried and did **not** stop indexing (historical); the `.noindex` suffix is what Spotlight honours. Do not rename it back.
- Sparkle is copied into `Contents/Frameworks` and `@executable_path/../Frameworks` is added to the rpath. Sign **inside out** (nested XPC / updater first).
- Ad-hoc signature is **not** distribution signing. It stops macOS calling the bundle damaged when moved. Gatekeeper still warns on first open until Developer ID + notarisation.
- **And every update re-asks for the keychain.** Ad-hoc means no stable identity, so the designated requirement is the binary's own cdhash — `codesign -d -r-` prints `cdhash H"…"`, and `TeamIdentifier=not set`. A keychain item's "always allow" list matches on that requirement, so a rebuilt Pulse is a program the list has never seen and macOS prompts again. It bites because Pulse reads other apps' `Safe Storage` keys to decrypt browser cookies ([providers/README.md](providers/README.md)) — one prompt per browser, on every update. Nothing in the app can suppress it; the ACL is the user's, and the mismatch is real. A Developer ID certificate is the only fix, because it makes the requirement team-based and therefore stable across versions. A self-signed certificate would also be stable, but releases are built in CI, so the private key would have to live there as a secret — the same work for none of the notarisation.

## Disk image (`Scripts/dmg.sh`)

The image is the install guide: Pulse is not notarised, and on macOS 15+ Control-click → Open is gone. Instructions are printed on the window (README-only instructions are not read by people downloading an app).

Finder window layout is a committed `Scripts/dmg-DS_Store` (AppleScript cannot run on CI). Recapture with `./Scripts/dmg.sh --relayout` after changing the backdrop or icon positions. Finder `bounds` **include the title bar** (~28pt taller than a 660×420 backdrop). Backdrop: `Scripts/dmg-background.tiff` (1x and 2x).

Sparkle updates from the **zip**, not the DMG. The image is for people.

## Sparkle

`AppUpdate.swift`. Safe without Apple Developer ID because of the **EdDSA** key: Sparkle refuses any archive not signed by the private half whose public half is in `Info.plist`. Apple signing is recommended by Sparkle, not required. Notarisation would only help Gatekeeper on **first** launch, which no updater can fix.

- `SUFeedURL` is only present in a bundle. `AppUpdate` starts nothing on `swift run`. Each check reads GitHub when it answers and **update.qunqin.org** — a Cloudflare Worker that passes the feed and downloads through — when it does not, and a failed check is tried again at once on the other. [update-mirror.md](update-mirror.md)
- **Checked every two hours** (`SUScheduledCheckInterval` 7200), against Sparkle's own default of a day. A day suits an app that ships every few months; this one ships fixes for things it is doing wrong now, and somebody burning a core on a bug fixed yesterday should not wait out the rest of the day to be told. Sparkle clamps anything under an hour (`SPUUpdaterSettings.minimumUpdateCheckInterval`) and measures from the **last check** rather than from launch (`SPUUpdater.m`, `intervalSinceCheck < updateCheckInterval`), so relaunching does not re-check and this is at most twelve requests a day.
- **Checking is not installing.** `SUEnableAutomaticChecks` is true and `SUAutomaticallyUpdate` is false: an update is offered, never applied behind the user. Checks start without Sparkle's permission prompt because this is an `.accessory` app whose panel never becomes key — that prompt opens behind everything and goes unanswered. The toggle lives in Settings instead.
- Sparkle’s delegate cannot be main-actor-isolated; `UpdaterRelay` sits between it and the `@Observable` model.
- `didAbortWithError` also fires for the user closing the window; only a genuine feed failure is reported.
- Notes live in the feed `<description>`, **not** `sparkle:releaseNotesLink` (that loads the whole GitHub page in a WebView). If both are present, the link wins — the link must be absent.
- **One language in the update window.** Each item carries one `<description xml:lang="…">` per language of the changelog entry — the Chinese section as `zh-Hans` **and** `zh-Hant` (no Traditional section is written, and macOS would give a Traditional reader the English otherwise), the English as `en` — and Sparkle shows the one the **system's** preferred languages pick (`SUAppcast bestNodeInNodes`, `NSBundle preferredLocalizationsFromArray:`); Japanese, Korean and Russian get English. Sparkle cannot see Pulse's own language setting, so `appcast.py` also writes `appcast-zh.xml` and `appcast-en.xml` — the same items, each with only that language's notes — and a Pulse set to a language reads its copy (`AppUpdate.feedURL(for:base:)`, through `feedURLStringForUpdater:`); one following the system reads `appcast.xml`. The workflow commits all three. `Scripts/appcast.py --notes <version>` rewrites one served item's notes and nothing else (enclosure, signature and date stay), which is how 1.8.0's were split after it shipped.
- Description: spacing only, no colours or fonts. Sparkle injects `ReleaseNotesColorStyle.css`.
- Public key: `Scripts/sparkle-public-key.txt` (committed). Private key: `SPARKLE_PRIVATE_KEY` only.
- `Scripts/appcast.py` signs the zip and appends to `appcast.xml`. The workflow commits the feed **after** publishing (the feed points at the release asset).

`Scripts/changelog.py` reads one CHANGELOG section and emits it three ways: as markdown, `--html` for the feed, and `--release-notes` for the GitHub page. Grammar: bullets, `**bold**`, `` `code` ``, links.

**The release page is assembled by the script, not by the workflow.** It used to be the entry, one hard-coded English install block and GitHub's generated commit list stapled together in `release.yml` — which is not the shape the pages before it had, so each release was reformatted by hand afterwards or left looking unlike its neighbours. `--release-notes` now produces the whole thing: the language nav, an anchored `<h2>` per language, the "already running x.y.z?" line, the install block **in each language**, and the compare link. The commit list is left out on purpose — direct commits mean dozens of lines of "Update README" under an entry that already says what changed.

That format reads the entry's own `**中文**` / `**English**` markers to find the sections, so an entry must carry both. The workflow checks for both anchors **before it builds**: an entry missing one still passes the "has an entry" check and would otherwise publish a page whose language nav points at an anchor that is not there. An entry with neither marker — the pre-1.0.2 ones — falls back to a single English section rather than inventing a nav bar.
