<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>How much Claude Code, Codex, Antigravity, Cursor, OpenCode Go, Kimi Code or Ollama Cloud you have left.</b>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma or newer</b> · Apple Silicon and Intel · <a href="README.zh-CN.md">简体中文</a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="330" alt="The Pulse rail against the left of the screen">
</p>

Pulse is a small floating monitor that sits on the edge of your screen and
tracks how much of your AI-coding allowance is left. It reads the limits
Claude Code, Codex, Antigravity, Cursor, OpenCode Go, Kimi Code and Ollama
Cloud actually report for your account, and shows them as a rail you can glance
at without switching away from your editor. There is no backend and no account
of its own; every figure comes from a route that agent itself offers.

## Install

Download the latest **`Pulse-x.y.z.dmg`** from
[Releases](https://github.com/qunqin24/Pulse/releases/latest), open it, and drag
Pulse into Applications.

Pulse isn't signed with an Apple Developer ID, so macOS blocks the first
launch — and on macOS 15 and later the old right-click → **Open** workaround is
gone. Once:

1. Open Pulse. macOS refuses — dismiss the dialog.
2. **System Settings → Privacy & Security**, scroll to **Security**, and click
   **Open Anyway**.
3. Open it again and confirm.

After that it launches normally. Later releases install themselves over it.

## What it does

The rail docks to either side of the screen or along the top, above the menu
bar, or floats anywhere on the desktop. Each agent is a ring. Away from it, the
rail folds to a 6pt sliver; when a limit is nearly gone the sliver turns red.
It stays out of other apps' full-screen Spaces by default.

Colour is the reading, not the identity: green below the warning threshold,
amber to it, red past it, and a deeper red once a limit is spent. Click a ring
to fetch just that agent's figures now. The rail opens with the last reading,
marked with when it was taken, rather than sitting blank until the slowest
provider answers.

Some agents are read with a login your own CLI or app already stored on this
Mac; two take an API key you paste into Settings; Ollama Cloud has no quota API
at all, so its session is read out of your browser. A provider-switched-off
agent isn't fetched, so its limit isn't spent on a figure nobody's looking at.

A ring also tells you whether that agent is working right now, read from the
transcript's actual boundaries rather than from "recently wrote a file" — so a
slow tool call doesn't look like a finished turn. Claude Code and Codex only;
the rest keep no transcript on disk.

Settings builds a spending history from Claude Code's and Codex's own session
logs, priced at each provider's published API rates, and adds one number Pulse
works out for itself: a clearly labelled estimate of what a rate-limit window
is worth. No provider reports that, and the other agents don't keep a local log
to build it from.

The rail is yours to arrange: put the rings in your own order, set the gap
between them, switch the percentages off on either rail, and pin a fixed colour
to an account if you'd rather than read usage by colour. The default is the
usage colour, since a fixed hue is a reading you've chosen to give up; a limit
the provider says is spent still shows the spent colour whatever you picked.
Monitored accounts are keyed by account, not by provider, so you can watch a
second Claude Code or Codex subscription side by side with the first.

Refresh is adaptive, between 2 and 30 minutes, so an idle machine stops asking.
Refresh interval, panel size, rail spacing, percentages and language are all
settings; English and Simplified Chinese switch without a relaunch.

## Where the numbers come from

Every figure is whatever that agent reports. Pulse never works a percentage out
from local token counts, and when a provider won't answer, it says so rather
than showing something plausible. The routes differ, and so do their costs:

| | Route | Caveat |
|---|---|---|
| **Claude Code** | The account's usage endpoint, using the login Claude Code already stored — falling back to the status line, which Pulse can register for itself | The saved token expires in hours and nothing here renews it, hence the fallback |
| **Codex** | The endpoint Codex's own client uses, falling back to `codex app-server` | Not public API; it can change without notice |
| **Antigravity** | The language server the editor runs on the loopback interface | Reports only while Antigravity is open — the figures live in that process |
| **Cursor** | The account's usage summary, authenticated with a cookie built from the login the editor already stored | Not public API. Reported as the two pools Cursor's own account page shows, not one combined figure |
| **OpenCode Go** | An API key you paste into Settings — or the login OpenCode's own CLI already stored, if you're signed in there | Not public API; it can change without notice. The one credential Pulse holds for itself |
| **Kimi Code** | An API key you paste into Settings | The one documented endpoint of the eleven — still no promise it won't change |
| **Z.ai** | An API key you paste into Settings | Not public API. The international storefront — a BigModel key is refused here |
| **GLM Coding Plan** | An API key you paste into Settings, or one the GLM tooling already saved on this Mac | Not public API. The mainland storefront (`open.bigmodel.cn`) |
| **MiniMax** / **MiniMax CN** | An API key you paste into Settings | Not public API. Two storefronts, `api.minimax.io` and `api.minimaxi.com` |
| **Ollama Cloud** | The signed-in settings page, with a session Pulse reads out of your browser | No quota API at all, so a page is the only source. See [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |

An added account signs in through Pulse, using the same public client its CLI
uses, and keeps its own refresh token — nothing the CLI owns is touched.

A reading that fails falls back to the last good one, shown with the time it
was taken. A window whose reset has passed is dropped rather than aged: it
hasn't gone stale, it has reset.

## Privacy

Pulse has no backend. Most providers are read with a login your own CLI or app
already stored on this Mac. The exceptions are OpenCode Go and Kimi Code, which
take an API key you paste in, and Ollama Cloud, whose session Pulse reads out of
your browser — a read scoped to `ollama.com` and to the cookie names that
authenticate, nothing else in the store. Those credentials are kept encrypted
in Pulse's own folder, owner-only, with the key derived from this Mac; nothing
goes into `UserDefaults`, a plist any process running as you can read.

An added account's login is stored the same way. Spending history is worked out
entirely on-device from logs already on disk. Nothing is uploaded anywhere.

## Build from source

See [Docs/build-from-source.md](Docs/build-from-source.md).

## Layout

All source is in `Sources/Pulse`, one SwiftUI view per file, with the provider
marks under `Sources/Pulse/Resources`. [CLAUDE.md](CLAUDE.md) is the deeper
walkthrough — the AppKit panel and SwiftUI split, why the window owns dragging,
what each provider's route actually costs. One provider has a page of its own:
[Docs/ollama-cloud.md](Docs/ollama-cloud.md), because reading a session out of a
browser deserves to be written down in full.

## Design

Thank you, [**Vinz** (@hivinz_)](https://x.com/hivinz_/status/2092996055248126353).

Pulse is built from a concept he posted on X in August 2026: a rail of rings
held against the edge of the screen, everything worth knowing in one glance and
nothing else. That idea is his; most of the work here has been trying not to
spoil it. He didn't build this and isn't responsible for it.

## License

[Apache 2.0](LICENSE). Bundled third-party assets keep their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
