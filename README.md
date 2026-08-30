# Pulse

**Know how much Claude Code, Codex or Antigravity you have left, without leaving what you're doing.**

Pulse is a tiny floating usage monitor that lives on the edge of your macOS
screen. No more tabbing over to a dashboard, or finding out you're rate
limited mid-task — a glance at the ring tells you where you stand, and it
gets out of the way the second you look away.

<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="128" alt="Pulse app icon">
</p>

## Why Pulse

- **Always visible, never in the way.** A slim rail sits flush against the
  screen edge, collapses to a barely-there sliver when you're not near it,
  and expands the moment you need it.
- **One glance instead of a dashboard.** Each provider is a ring; the colour
  — green, amber, red — tells you how close you are before you read a single
  number.
- **Real numbers, not guesses.** Usage comes straight from each provider's
  own limits, not a local estimate of how many tokens you've burned.
- **Knows when you're actually working.** The ring spins while a CLI is
  mid-turn, so you can tell "still thinking" from "stalled" at a glance.
- **Built to stay out of your way.** It skips other apps' full-screen Spaces
  by default, drags to either screen edge or floats free, and remembers
  where you left it.

## Features

- A real borderless, transparent floating panel that docks to either screen
  edge — drag it by the rail to reposition it or float it anywhere, and it
  remembers where you left it.
- Auto-hides to a slim sliver against the screen edge when you're not near
  it, so it stays out of the way without disappearing — the sliver still
  turns warning colours if a limit is close.
- Stays out of other apps' full-screen Spaces by default, with an opt-out in
  Settings.
- A collapsed dock of per-provider usage rings that expands into a detail
  card (current session + all-models progress) when a provider is selected.
- A live spinner on a provider's ring while its CLI is actively working on a
  turn.
- An optional Liquid Glass appearance on macOS 26+ (off by default — a solid
  panel stays legible over anything).
- A menu bar item with a settings window for showing/hiding the panel,
  choosing its screen edge and size, launching at login, and picking which
  providers appear.
- English and Simplified Chinese, following the system language or set
  explicitly in Settings (applies immediately).
- An adaptive refresh interval (2–30 minutes) that backs off when nothing's
  changing, instead of polling on a fixed schedule around the clock.
- **Real usage, not estimates.** Codex is read live from the endpoint its
  own CLI polls; Claude Code reports its official 5-hour and weekly limits
  through the status line hook Pulse registers (connect it in
  Settings → Claude Code); Antigravity's limits come from the language
  server it runs while it's open, so its figures need the app running. A
  cached reading is shown, marked as of its last fetch, if a check fails.
- A spending history in Settings for the two CLIs, reconstructed from their
  own local session logs and priced at each provider's published rates — including a
  clearly labelled estimate of what a usage window is worth, since the
  providers themselves never report a dollar figure.

## Privacy

Pulse has no backend of its own. It talks only to the provider endpoints
your CLIs already use, reading credentials they already stored on your Mac.
Spending history is computed entirely on-device, from log files already on
disk — nothing is uploaded anywhere.

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

## Requirements

- macOS 14 or newer
- [Claude Code](https://claude.com/claude-code), [Codex](https://openai.com/codex) and/or [Antigravity](https://antigravity.google) installed and signed in, for whichever provider(s) you want to monitor

The package uses Swift tools 6.0 and can be opened directly in Xcode through `Package.swift`.

## Building an app

```bash
./Scripts/bundle.sh          # → build/Pulse.app
./Scripts/bundle.sh --zip    # → and build/Pulse-<version>.zip
./Scripts/dmg.sh             # → build/Pulse-<version>.dmg, ready to hand out
```

A universal build for Apple Silicon and Intel. The disk image carries the app,
a shortcut to Applications, and the first-launch instructions below printed on
the window — so they reach the person installing it, not just whoever reads
this file.

## Installing a downloaded copy

Pulse isn't signed with an Apple Developer ID yet, so macOS blocks it the first
time. On macOS 15 and later the old right-click → **Open** trick no longer
works; Apple removed it. Once:

1. Drag **Pulse** to your Applications folder.
2. Open it. macOS refuses — dismiss the dialog.
3. **System Settings → Privacy & Security**, scroll to **Security**, and click
   **Open Anyway** next to Pulse.
4. Open it again and confirm.

After that it launches normally, and it will start at login unless you turn
that off in Settings.

## Releasing

Pushing a tag publishes the release. Nothing else is needed, and there are no
secrets to configure.

```bash
# 1. bump the version and commit it — the tag is checked against this file
echo 1.0.1 > VERSION && git commit -am "Pulse 1.0.1"

# 2. tag and push
git tag v1.0.1 && git push && git push origin v1.0.1
```

[`.github/workflows/release.yml`](.github/workflows/release.yml) then builds a
universal app on a macOS 26 runner, packages the `.dmg` and `.zip`, writes
release notes (the install steps above, plus what changed since the last tag)
and publishes the release. A tag that doesn't match `VERSION` fails the run
rather than shipping a build that tells every installed copy it is out of date
forever.

A tag with a suffix — `v1.1.0-beta.1` — is published as a pre-release, which
GitHub's "latest release" excludes, and so does Pulse's update check.

Every push and pull request also runs
[`.github/workflows/ci.yml`](.github/workflows/ci.yml): the Swift 6 strict
build with warnings treated as failures, the localization key check, and an
assembly of `Pulse.app` to prove the thing that ships still builds.

Pulse checks `releases/latest` once a day and offers a link when there is a
newer tag than the version it is running. It never installs anything itself.

## Project layout

All source lives in `Sources/Pulse`, one SwiftUI view per file, with provider icon assets under `Sources/Pulse/Resources`. See [CLAUDE.md](CLAUDE.md) for a deeper architecture walkthrough (the AppKit panel/SwiftUI split, the data model seam, etc.).

## License

Pulse is licensed under the [Apache License 2.0](LICENSE). Bundled third-party
assets retain their original licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
