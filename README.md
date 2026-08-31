<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>Know how much Claude Code, Codex or Antigravity you have left,<br>without leaving what you're doing.</b>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma or newer</b> · Apple Silicon and Intel · <a href="README.zh-CN.md">简体中文</a></sub>
</p>

<p align="center">
  <img src="Docs/panel.png" width="440" alt="The Pulse rail docked to the right of the screen, with a provider's limits open beside it">
</p>

Pulse is a small floating monitor that lives against the edge of your screen.
A glance at the ring tells you where you stand; it collapses to a sliver when
you're not near it, and comes back when you are. No dashboard to tab over to,
and no finding out you're rate limited halfway through a task.

## Install

Download the latest **`Pulse-x.y.z.dmg`** from
[Releases](https://github.com/qunqin24/Pulse/releases/latest), open it, and drag
Pulse into Applications.

Pulse isn't signed with an Apple Developer ID yet, so macOS blocks the first
launch — and on macOS 15 and later the old right-click → **Open** trick is gone.
Once:

1. Open Pulse. macOS refuses — dismiss the dialog.
2. **System Settings → Privacy & Security**, scroll to **Security**, and click
   **Open Anyway**.
3. Open it again and confirm.

After that it launches normally, and later versions install themselves.

## What it does

<img src="Docs/rail.png" width="150" align="right" alt="The rail, three rings">

**Three agents, one rail.** Claude Code, Codex and Antigravity, each a ring.
The colour says how close you are — green, amber, red — before you read a
number. Click a ring to refresh just that one.

**Real limits, not guesses.** Every figure comes from the provider's own
account. Pulse never works a percentage out from local token counts, and when
a provider won't answer it says so rather than showing something plausible.

**It knows when you're working.** A mark turns inside a ring while that CLI is
mid-turn — read from the transcript's actual turn boundaries, not from "wrote
to a file recently", so a slow tool call doesn't look like a finished turn.

**Out of the way.** Docks to either screen edge or floats anywhere on the
desktop, hides down to a 6pt sliver when you're not near it, and stays out of
other apps' full-screen Spaces. The sliver still turns red when a limit is
nearly gone — a monitor that hides itself has to keep one way of saying *look
at me*.

**What it costs.** Settings reconstructs a spending history from the CLIs' own
session logs, priced at each provider's published API rates — plus a clearly
labelled estimate of what a rate-limit window is worth, since no provider
reports one.

**Adaptive refresh.** Between 2 and 30 minutes, backing off when nothing is
moving instead of polling on a fixed schedule around the clock.

English and Simplified Chinese, switchable without a relaunch. Three sizes. An
optional Liquid Glass surface on macOS 26.

<p align="center">
  <img src="Docs/settings.png" width="620" alt="Pulse settings, showing the General pane">
</p>

## Where the numbers come from

Each agent is read by whatever route it actually offers, and all three differ:

| | Route | Caveat |
|---|---|---|
| **Claude Code** | The account's usage endpoint, using the login Claude Code already stored — falling back to the status line, which Pulse can register for itself | The saved token expires in hours and nothing here renews it, hence the fallback |
| **Codex** | The same endpoint Codex's own client uses, falling back to `codex app-server` | Not public API; it can change without notice |
| **Antigravity** | The language server the editor runs on the loopback interface | Reports only while Antigravity is open — the figures live in that process |

A reading that fails falls back to the last good one, shown with the time it
was taken rather than passed off as current.

## Ollama Cloud (experimental)

Ollama Cloud can show session (5-hour) and weekly quota usage and reset times.
Enable **Ollama Cloud** in Settings and supply a **session Cookie header**, not an
API key. The cookie is saved separately in macOS Keychain. Pulse does not import
browser cookies or call model-generation endpoints.

This reads the signed-in `https://ollama.com/settings` HTML, **not a documented
quota API**. Login expiry or page changes can stop it working. Both quota windows
must be readable; missing data is never shown as zero. Unlike the other providers,
Ollama readings are not cached or reused after a failed refresh, avoiding quota
from a previous login being attributed to another account. Purely local Ollama
models, extra-usage balances, plan names and model-level spending are not covered.

See [setup, limitations and validation](Docs/ollama-cloud.md). This adapter has
fixture coverage but still needs live-account and settings-UI acceptance testing.

## Privacy

Pulse has no backend. For Ollama, a user-supplied session cookie is sent only to
Ollama’s settings page; its HTML is not saved. Other providers use the routes above.
It talks only to the endpoints your own CLIs already
use, with credentials they already stored on this Mac, and works out the
spending history entirely on-device from log files already on disk. Nothing is
uploaded anywhere.

## Build from source

```bash
swift run Pulse              # build and run
swift build                  # type-check everything, previews included
./Scripts/bundle.sh          # → build.noindex/Pulse.app
./Scripts/dmg.sh             # → build.noindex/Pulse-<version>.dmg
```

`xcode-select` has to point at Xcode rather than CommandLineTools — the
`#Preview` macro is expanded by a plugin that ships with Xcode. If a build
fails with `PreviewsMacros plugin not found`:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Swift tools 6.0; the package opens directly in Xcode through `Package.swift`.
There is no test target and no linter.

## Layout

All source is in `Sources/Pulse`, one SwiftUI view per file, with the provider
marks under `Sources/Pulse/Resources`. [CLAUDE.md](CLAUDE.md) is the deeper
walkthrough — the AppKit panel and SwiftUI split, why the window owns dragging,
what each provider's route actually costs.

## Design

Thank you, [**Vinz** (@hivinz_)](https://x.com/hivinz_/status/2092996055248126353).

Pulse exists because of a concept he posted on X in August 2026 — a Figma
design for people tired of checking their Claude and Codex limits by hand. It
stopped me the moment I saw it: a rail of rings held against the edge of the
screen, everything worth knowing in one glance and nothing else. That idea is
his, and most of the work here has been trying not to spoil it.

This is an independent implementation. He didn't build it and isn't
responsible for it.

## License

[Apache 2.0](LICENSE). Bundled third-party assets keep their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
