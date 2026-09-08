<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>A lightweight, elegant screen-edge monitor for your AI coding allowances.</b><br>
  Real-time remaining quotas and rate limits for Claude Code, Codex, Cursor, GitHub Copilot, Antigravity, Grok, and more.
</p>

<p align="center">
  <a href="https://github.com/harrisliangsu/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/harrisliangsu/Pulse?color=black" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-333333?logo=apple" alt="macOS 14+">
  <a href="https://github.com/harrisliangsu/Pulse/actions/workflows/ci.yml"><img src="https://github.com/harrisliangsu/Pulse/actions/workflows/ci.yml/badge.svg" alt="CI Build"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue" alt="License"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma or newer</b> · Apple Silicon & Intel Universal · <a href="README.zh-CN.md"><b>简体中文</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="340" alt="Pulse floating rail docked against the screen edge">
</p>

Pulse is an unobtrusive floating monitor that docks neatly along the edge of your screen. It shows remaining allowance from the figures each service reports — using that product's own client routes, not a Pulse server — with no Pulse account and no telemetry. Pulse does not invent usage percentages.

---

## Key Features

### At-a-Glance Status Rings
- **Usage-Aware Colors**: Dynamic color gradients shift from green to amber, red, and deep red when exhausted — or set custom accent colors per account.
- **Active Turn Indicator**: A subtle revolving dot indicates whether an agent is actively generating responses in real-time (Claude Code & Codex).
- **Elapsed Window Arc**: An optional secondary outer arc visualizes how much time in the current rate-limit window has elapsed.
- **Countdown Mode**: Toggle between showing spent quota (`75% used`) or remaining balance (`25% left`).

### Hover Details & Smart Forecasting
- **Complete Limit Breakdown**: Hover over any ring to reveal a detailed card showing every reported quota pool, reset countdowns, and current window status.
- **Burn-Rate Forecast**: Automatically projects whether your current pace will outlast the quota window and displays an estimated time-to-exhaustion (ETA) when risk is detected.
- **Pin Primary Window**: Pin whichever limit matters most to the ring, or let Pulse automatically track the one closest to exhaustion.

### Native, Fluid & Non-Intrusive
- **Flexible Edge Docking**: Dock to the left, right, or top of your screen (above the menu bar), or float freely anywhere.
- **Multi-Monitor Native**: Drag Pulse to any secondary display; it remembers screen placement and gracefully returns if disconnected.
- **Auto-Collapse**: Automatically folds into a razor-thin sliver when idle to eliminate distraction, glowing red only when quota runs critically low.
- **Opt-In Notifications**: Off until you turn them on. Get told when a limit passes 75/80/90/95%, when the provider says it is spent, when a window you were warned about comes back, and when several checks in a row fail so the panel is quietly showing older figures. Each thing is said once: a limit already past the line when you switch this on is mentioned straight away, then never again until it resets or gets worse.
- **Reset ribbons**: A full-screen overlay named for the provider, when a limit turns over. Off until you turn it on in Settings › General. Not a notification, and not tied to being warned on the way up.
- **Spaces-Friendly**: By default, stays out of your full-screen application Spaces.
- **macOS Aesthetic**: Dark, light, or native **Liquid Glass** on macOS 26+ — one Appearance control, not two stacked switches. Size from tiny to large.

### Multi-Account & Local Ledger
- **Multi-Account Support**: Monitor multiple subscriptions for the same provider (Claude Code, Codex, Grok, Grok Bot, Kimi Code) side-by-side with custom labels.
- **On-Device Spending History**: Reconstructs your historical token expenditures from local CLI session transcripts, calculated against published API prices.
- **Sixteen Providers**: Claude Code, Codex, Antigravity, Cursor, GitHub Copilot, Grok, Grok Bot, OpenCode Go, Kimi Code, Ollama Cloud, Qoder, Z.ai, GLM Coding Plan, MiniMax (intl. and mainland), and Volcengine.
- **Scriptable**: `Pulse --json` prints the last readings — plan, every limit, reset times, and how old the figures are — for tmux, sketchybar, Raycast, or a shell prompt. It reads the cache and never fetches, so polling it costs nothing.
- **Privacy First**: No Pulse servers, no Pulse account, and no telemetry. Requests go to the providers you already use (and follow macOS system proxy settings).

<p align="center">
  <img src="Docs/panel.png" height="300" alt="Detailed usage card beside rail">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="Docs/settings.png" height="300" alt="Pulse Settings">
</p>

---

## Supported Providers & Data Routes

Pulse shows the figures each service reports. It never guesses percentages from local token counts. Routes differ by product (documented client APIs, editor logins, local language servers, pasted keys) — not one official public quota API for every row. Contributor detail: [Docs/providers/README.md](Docs/providers/README.md).

| Provider | Data Route & Auth Method | Notes |
|---|---|---|
| **Claude Code** | Account OAuth usage endpoint; automatic fallbacks to Claude Desktop session & Status Line | Reads existing CLI/Desktop session; auto-falls back seamlessly |
| **Codex** | Client usage endpoint; fallback to `codex app-server` | Reads local Codex credentials directly |
| **Antigravity** | Local Language Server (LSP) | Active while the Antigravity editor is running |
| **Cursor** | Cursor account usage summary API | Shows fast and slow request pools from existing editor login |
| **Grok** | Grok Build CLI proxy (`cli-chat-proxy.grok.com`) | Single unified weekly pool shared across all Grok products |
| **Grok Bot** | Cursor dashboard API | The xAI quota included with Cursor subscriptions |
| **GitHub Copilot** | GitHub Device Code authentication | Requests minimal `read:user` scope; never accesses repositories |
| **OpenCode Go** | API key or existing OpenCode CLI credentials | Fully configurable in Settings |
| **Kimi Code** | Kimi Code device-code sign-in, or a pasted API key | Subscription login from Settings; console key still works |
| **Z.ai** | Direct API key | International storefront (`api.z.ai`) |
| **GLM Coding Plan** | Direct API key or saved GLM tooling credentials | Mainland storefront (`open.bigmodel.cn`) |
| **MiniMax / MiniMax CN** | Direct API key | Supports international (`minimax.io`) & mainland (`minimaxi.com`) |
| **Ollama Cloud** | Browser session cookie | Read locally from browser. See [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |
| **Qoder** | Browser session cookie | Plan Credits from the signed-in dashboard. See [Docs/providers/qoder.md](Docs/providers/qoder.md) |

---

## Installation

1. Download the latest **`Pulse-x.y.z.dmg`** from [Releases](https://github.com/harrisliangsu/Pulse/releases/latest).
2. Open the disk image and drag **Pulse** into your `Applications` folder.

> [!NOTE]
> **macOS Gatekeeper First Launch**:  
> Pulse is an open-source project without an Apple Developer certificate. On first launch, macOS may block the app:
> - **Option 1 (GUI)**: Launch Pulse, dismiss the alert, open **System Settings → Privacy & Security**, and click **Open Anyway**.
> - **Option 2 (Terminal)**:
>   ```bash
>   xattr -cr /Applications/Pulse.app
>   ```
> *(Subsequent updates via built-in Sparkle update smoothly without repeated prompts).*

---

## Privacy & Security

Pulse is designed with strict local-first security principles:
- **No Pulse backend**: There is no Pulse server, account, or telemetry. The app talks to the providers you already use; it does not insert its own proxy. macOS system proxy settings still apply.
- **Local Credentials**: Reads credentials already stored locally by your development tools (`~/.claude`, `~/.codex`, Cursor storage, etc.) where that is how the product works; some providers need a key or sign-in you enter in Settings.
- **Encrypted Local Storage**: Manually entered API keys and session tokens are encrypted and saved strictly in Pulse's local application directory with owner-only permissions.
- **Code & Chat Privacy**: Pulse never reads your source code, terminal history, prompts, or LLM conversations.

---

## Build from Source

Pulse is built using native Swift and SwiftUI without heavy external dependencies.

```bash
# Clone the repository
git clone https://github.com/harrisliangsu/Pulse.git
cd Pulse

# Build and run directly
swift run Pulse

# Or package into a native macOS app bundle
./Scripts/bundle.sh
```

See [Docs/build-from-source.md](Docs/build-from-source.md) for toolchain setup. Shipping a release: [Docs/releasing.md](Docs/releasing.md).

---

## Contributing

How the repo is documented, what must not regress, and how to update the right page: [CONTRIBUTING.md](CONTRIBUTING.md). Map of topic docs: [Docs/README.md](Docs/README.md).

---

## Design Attribution

Pulse was inspired by a UI concept shared by [**Vinz** (@hivinz_)](https://x.com/hivinz_/status/2092996055248126353) on X in August 2026. Pulse is an independent implementation with its own interactions, functionality, animations, and visual details. Vinz is not affiliated with or responsible for Pulse.

---

## License

Licensed under [Apache 2.0](LICENSE). Bundled third-party assets retain their respective licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
