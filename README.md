<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>A lightweight, elegant screen-edge monitor for your AI coding allowances.</b><br>
  Real-time remaining quotas and rate limits for Claude Code, Codex, Cursor, GitHub Copilot, Antigravity, Grok, and more.
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?color=black" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-333333?logo=apple" alt="macOS 14+">
  <a href="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml"><img src="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml/badge.svg" alt="CI Build"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue" alt="License"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?color=black" alt="GitHub Stars"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?color=black" alt="Downloads"></a>
  <a href="https://github.com/qunqin24/Pulse/issues"><img src="https://img.shields.io/github/issues/qunqin24/Pulse?color=black" alt="Open Issues"></a>
  <a href="https://github.com/qunqin24/Pulse/commits/main"><img src="https://img.shields.io/github/last-commit/qunqin24/Pulse?color=black" alt="Last Commit"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma or newer</b> · Apple Silicon & Intel Universal · <b>English</b> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <a href="README.ja.md"><b>日本語</b></a> · <a href="README.ko.md"><b>한국어</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="340" alt="Pulse floating rail docked against the screen edge">
</p>

Pulse is an unobtrusive floating monitor that docks neatly along the edge of your screen. It shows remaining allowance from the figures each service reports — using that product's own client routes, not a Pulse server — signed in as you already are, with nothing reported back. Every percentage on screen is a figure the service itself reported.

**New in 1.2.0:** an optional animated mark in place of a provider's logo — a small bot that reacts to what that account is doing, with its own personality, shape and colour. [Release notes](https://github.com/qunqin24/Pulse/releases/tag/v1.2.0).

<p align="center">
  <img src="Docs/bot-mark.gif" width="340" alt="Pulse animated marks: a bot in each ring reacting to what that account is doing">
</p>

---

## Key Features

### At-a-Glance Status Rings
- **Usage-Aware Colors**: Dynamic color gradients shift from green to amber, red, and deep red when exhausted — or set custom accent colors per account.
- **Active Turn Indicator**: A subtle revolving dot indicates whether an agent is actively generating responses in real-time (Claude Code & Codex).
- **Elapsed Window Arc**: An optional secondary outer arc visualizes how much time in the current rate-limit window has elapsed.
- **Countdown Mode**: Toggle between showing spent quota (`75% used`) or remaining balance (`25% left`).

### Hover Details & Smart Forecasting
- **Complete Limit Breakdown**: Hover over any ring to reveal a detailed card showing every reported quota pool, reset countdowns, and current window status.
- **Burn-Rate Forecast (Optional)**: When you turn it on, projects whether your current pace will outlast the quota window and shows an estimated time-to-exhaustion (ETA) when risk is detected. Off by default.
- **Pin Primary Window**: Pin whichever limit matters most to the ring, or let Pulse automatically track the one closest to exhaustion.

### Native, Fluid & Non-Intrusive
- **Flexible Edge Docking**: Dock to the left, right, or top of your screen (above the menu bar), or float freely anywhere.
- **Multi-Monitor Native**: Drag Pulse to any secondary display; it remembers screen placement and gracefully returns if disconnected. Turn on **Follow the active display** and the single rail moves itself to whichever screen your pointer is on.
- **Auto-Collapse**: Automatically folds into a razor-thin sliver when idle to eliminate distraction, glowing red only when quota runs critically low.
- **Opt-In Notifications**: You choose which ones to switch on. Get told when a limit passes 75/80/90/95%, when the provider says it is spent, when a window you were warned about comes back, and when several checks in a row fail so the panel is quietly showing older figures, and — for the services that sell prepaid credit — when the balance falls under a figure you set. Each thing is said once: a limit already past the line when you switch this on is mentioned straight away, and again when it resets or gets worse.
- **Spaces-Friendly**: Keeps to the Space you are working in, leaving full-screen apps to themselves.
- **macOS Aesthetic**: Classic solid obsidian surface or native **Liquid Glass** on macOS 26+.
- **Animated Marks (Optional)**: Replace a provider's logo with a small bot that reacts to what that account is doing — working, fetching, spent, or quiet. Off by default and switched on per account, with eight personalities, eighteen body shapes and a colour of your own if you want one.
- **Rail Menu & Shortcuts**: Right-click the floating rail — or the collapsed sliver; Control-click works too — for a menu with Settings and Quit. In **Settings › General › Shortcuts** you can optionally assign global shortcuts to **Open settings** and **Show or hide the panel**; both are unset until you set one.
- **Five Interface Languages**: English, Simplified Chinese, Traditional Chinese, Japanese and Korean, with language-aware large-number units: K/M/B, 万/亿, 萬/億, 万/億 and 만/억 respectively.

### Multi-Account & Local Ledger
- **Multi-Account Support**: Monitor multiple subscriptions for the same provider (Claude Code, Codex, Grok, Grok Bot) side-by-side with custom labels.
- **Token Spend (Settings-only)**: Off by default. Enable it on the page to scan local records; switching it off stops the scan. Reads local logs, databases and exports from a catalogue of **54 client sources**, including Gemini CLI, Cline, Roo Code, OpenClaw and GitHub Copilot. Cursor, Trae and other export sources need a prior export or capture. These are distinct from the rail's 20 quota providers; support and live-client validation vary by source. [Sources and coverage](Docs/token-spend-sources.md).
- **Clear Usage Estimates**: Opens on the last 7 days and remembers your chosen span. Costs use published API prices, not subscription charges. Unknown prices stay unavailable, incomplete counts and coarse timing are labelled, and a source that reports no token counters says so.
- **Model Details & Charts**: Open a model for input/output/cache counts and estimated costs, daily and hourly charts where the records support them, contributions by agent, and sortable, paged detail tables. Point at a chart to read the date or hour and its token count. Unavailable daily or hourly detail is shown as unavailable, not zero.
- **Twenty Providers**: Claude Code, Codex, Kiro, Antigravity, Cursor, GitHub Copilot, Grok, Grok Bot, OpenCode Go, Kimi Code, Ollama Cloud, z.ai, Zhipu, MiniMax (intl. and mainland), Volcengine, Command Code, DeepSeek, Devin, and Xiaomi Coding Plan.
- **Scriptable**: `Pulse --json` prints the last readings — plan, every limit, reset times, and how old the figures are — for tmux, sketchybar, Raycast, or a shell prompt. It reads the cache, so polling costs nothing.
- **Developer Integrations**: Export a Raycast extension and ready-to-configure tmux, sketchybar and shell scripts from Settings. Account links open the right pane directly. [Setup guide](Docs/integrations.md).
- **Connection Diagnostics**: See the actual reading source, cache use, latest check and fallback outcomes. Contextual actions help reconnect, sign in again or fix credentials; copy a diagnostic report without account details or secrets.
- **Privacy First**: Pulse runs on your Mac under your own provider logins. It makes three kinds of connection and they are all listed here: the providers you already use, [models.dev](https://models.dev) for public model prices in the token-spend pane, and GitHub/Sparkle for app updates. Provider requests, sign-in exchanges and models.dev use the proxy chosen under Settings › General › Network; supported helper processes receive the same manual proxy. Sparkle update checks always follow macOS system proxy settings.

<p align="center">
  <img src="Docs/panel.webp" height="300" alt="Detailed usage card beside rail">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="Docs/settings.webp" height="300" alt="Pulse Settings">
</p>

<p align="center">
  <img src="Docs/account-claude-code.webp" height="290" alt="An account pane: every reported limit, the estimated value of what was used, and the local history">
  &nbsp;&nbsp;
  <img src="Docs/account-codex.webp" height="290" alt="Another account pane, with the plan, credit balance and limit reset credits it reports">
</p>

<p align="center">
  <img src="Docs/spend.webp" height="290" alt="Token spend: total, tokens by kind, and the daily pattern">
  &nbsp;&nbsp;
  <img src="Docs/spend-history.webp" height="290" alt="Token spend day by day, by month and by agent">
</p>

<p align="center">
  <img src="Docs/spend-agent.webp" height="290" alt="One agent's spending on its own">
  &nbsp;&nbsp;
  <img src="Docs/spend-model.webp" height="290" alt="One model's spending, priced by token kind">
</p>

---

## Supported Providers & Data Routes

Pulse shows the figures each service reports, and every percentage comes from that reply itself. Routes differ by product (documented client APIs, editor logins, local language servers, pasted keys) — not one official public quota API for every row. Contributor detail: [Docs/providers/README.md](Docs/providers/README.md).

| Provider | Data Route & Auth Method | Notes |
|---|---|---|
| **Claude Code** | Account OAuth usage endpoint; automatic fallbacks to Claude Desktop session & Status Line | Reads existing CLI/Desktop session; auto-falls back seamlessly |
| **Codex** | Client usage endpoint; fallback to `codex app-server` | Reads local Codex credentials directly |
| **Kiro** | Native Kiro CLI ACP usage method | Uses Kiro's signed-in CLI session; Pulse never reads or stores Kiro credentials ([details](Docs/providers/kiro.md)) |
| **Antigravity** | Local Language Server (LSP) | Active while the Antigravity editor is running |
| **Cursor** | Cursor account usage summary API | Shows fast and slow request pools from existing editor login |
| **Grok** | Grok Build CLI proxy (`cli-chat-proxy.grok.com`) | Single unified weekly pool shared across all Grok products |
| **Grok Bot** | Cursor dashboard API | The xAI quota included with Cursor subscriptions |
| **GitHub Copilot** | GitHub Device Code authentication | Requests the `read:user` scope alone |
| **OpenCode Go** | API key or existing OpenCode CLI credentials | Fully configurable in Settings |
| **Kimi Code** | Direct API key | Configured via Settings |
| **z.ai** | Direct API key | International storefront (`api.z.ai`) |
| **Zhipu** | Direct API key or saved GLM tooling credentials | Mainland storefront (`open.bigmodel.cn`) |
| **MiniMax / MiniMax CN** | Direct API key | Supports international (`minimax.io`) & mainland (`minimaxi.com`) |
| **Ollama Cloud** | Browser session cookie | Read locally from browser. See [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |
| **Volcengine** | `arkcli` login, else a pasted access-key pair (signed Top OpenAPI) | Ark Coding & Agent plans; on automatic it prefers pasted keys over the CLI |
| **Command Code** | Pasted key, else the login `cmd auth login` already saved | Credit balance in dollars; monthly plan row marked **estimated** |
| **DeepSeek** | Pasted key; documented `GET /user/balance` | Prepaid balance only — no allowance; you pick what the ring measures against |
| **Devin** | Nothing to enter — reads your browser session, no keychain prompt | Daily and weekly quota reported by Devin. With no browser session or pasted credential, reads the app's dated saved plan. Endpoint failures use only matching endpoint cache, preserving account and organization boundaries ([Docs/providers/devin.md](Docs/providers/devin.md)) |
| **Xiaomi Coding Plan** | Nothing to enter — reads your signed-in browser session, or paste a `Cookie:` header | The monthly token allowance from Xiaomi's MiMo console, with the period's end where it reports one. The prepaid balance rides along on the card. An account with no plan says so rather than drawing 0% ([Docs/providers/xiaomi-coding-plan.md](Docs/providers/xiaomi-coding-plan.md)) |

---

## Installation

1. Download the latest **`Pulse-x.y.z.dmg`** from [Releases](https://github.com/qunqin24/Pulse/releases/latest).
2. Open the disk image and drag **Pulse** into your `Applications` folder.
3. On first launch, choose the services to monitor. All start unchecked; Pulse reads their credentials and checks usage only after you click **Done**. Closing the chooser leaves monitoring off; you can also enable a service in Settings. Upgrades keep your choices and ask once about newly supported services detected on your Mac.
4. Pulse lives in the menu bar. If your menu bar is crowded, right-click the floating rail — or the collapsed sliver — and choose **Settings…**; you can also assign a global shortcut for it under **Settings › General › Shortcuts**.

> [!NOTE]
> **macOS Gatekeeper First Launch**:<br>
> Pulse is an open-source project without an Apple Developer certificate. On first launch, macOS may block the app:
> - **Option 1 (GUI)**: Launch Pulse, dismiss the alert, open **System Settings → Privacy & Security**, and click **Open Anyway**.
> - **Option 2 (Terminal)**:
>   ```bash
>   xattr -cr /Applications/Pulse.app
>   ```
>   *Updates are offered in-app through Sparkle. macOS may request browser keychain access again after an update.*

---

## Privacy & Security

Pulse is designed with strict local-first security principles:
- **No Pulse backend**: Your Mac talks to the providers you already use, under your own logins. It also fetches public model prices from [models.dev](https://models.dev) for the token-spend pane and checks GitHub/Sparkle for app updates. Provider requests, sign-in exchanges and models.dev use the proxy chosen under Settings › General › Network; supported helper processes receive the same manual proxy. Sparkle update checks always follow macOS system proxy settings.
- **Local Credentials**: Reads credentials already stored locally by your development tools (`~/.claude`, `~/.codex`, Cursor storage, etc.) where that is how the product works; some providers need a key or sign-in you enter in Settings.
- **Encrypted Local Storage**: Manually entered API keys and session tokens are encrypted and saved strictly in Pulse's local application directory with owner-only permissions.
- **Local Usage Records**: Pulse reads transcripts, databases and exports to obtain token counts and session metadata such as titles and working directories. These records may contain conversation text; processing stays on your Mac and the records stay with it. Pulse reads those records and nothing else.

---

## Build from Source

Pulse is built with native Swift and SwiftUI. Building the current sources needs the full **Xcode** (not the Command Line Tools), including the **macOS 26 SDK**; the app runs on **macOS 14+**.

```bash
# Clone the repository
git clone https://github.com/qunqin24/Pulse.git
cd Pulse

# Build the app bundle
./Scripts/bundle.sh

# Launch it
open build.noindex/Pulse.app
```

`swift run Pulse` is a quick way to build and run without a bundle, but notifications and in-app updates only work from the bundled app. See [Docs/build-from-source.md](Docs/build-from-source.md) for toolchain setup. Shipping a release: [Docs/releasing.md](Docs/releasing.md).

---

## Contributing

How the repo is documented, what must not regress, and how to update the right page: [CONTRIBUTING.md](CONTRIBUTING.md). Map of topic docs: [Docs/README.md](Docs/README.md).

---

## Design Attribution

Pulse was inspired by a UI concept shared by [**Vinz** (@hivinz_)](https://x.com/hivinz_/status/2092996055248126353) on X in August 2026. Pulse is an independent implementation with its own interactions, functionality, animations, and visual details. Vinz is not affiliated with or responsible for Pulse.

---

## License

Licensed under [Apache 2.0](LICENSE). Bundled third-party assets retain their respective licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

## Star History

<a href="https://star-history.com/#qunqin24/Pulse&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
  </picture>
</a>
