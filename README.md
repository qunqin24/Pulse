<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>Know how much Claude Code, Codex and Cursor you have left — without opening a single usage page.</b><br>
  A free, open-source macOS monitor that sits on the edge of your screen and shows every AI coding limit at a glance.
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/badge/Download-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download Pulse for macOS"></a>
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?color=black" alt="Latest release"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?color=black" alt="Downloads"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?color=black" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue" alt="Apache 2.0 license"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma or newer</b> · Apple Silicon & Intel · <b>English</b> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <a href="README.ja.md"><b>日本語</b></a> · <a href="README.ko.md"><b>한국어</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" height="400" alt="Pulse floating rail docked against the screen edge">
  &nbsp;&nbsp;
  <img src="Docs/panel.webp" height="400" alt="Hovering a ring opens a card with every limit and its reset">
</p>

- **Seventy-seven services at a glance** — Claude Code, Codex, Cursor, GitHub Copilot, Antigravity, Kiro, Grok, DeepSeek, Kimi Code and many more, each as its own ring.
- **No Pulse account, no Pulse server** — it uses the logins you already have, and nothing is sent back.
- **Real numbers only** — every usage percentage is the one the service itself reported. The few estimates are marked as such, and where a service reports nothing, Pulse says so instead of guessing.
- **Native and quiet** — Swift and SwiftUI, Liquid Glass on macOS 26. Dock it left, right or along the top, let it fold to a sliver when idle, or keep it in the menu bar.

**Recently added:** usage in the menu bar with a dashboard for each account, starting usage windows after a reset, and animated bot marks. [What's new](https://github.com/qunqin24/Pulse/releases/latest).

<p align="center">
  <img src="Docs/bot-mark.gif" width="300" alt="Pulse animated marks: a bot in each ring reacting to what that account is doing">
</p>

<p align="center">
  <sub>If Pulse has saved you from a surprise rate limit, a ⭐ helps other people find it.</sub>
</p>

---

## Key Features

### At-a-Glance Status Rings
- **Usage-Aware Colors**: Dynamic color gradients shift from green to amber, red, and deep red when exhausted — or set custom accent colors per account.
- **Active Turn Indicator**: A subtle revolving dot indicates whether an agent is actively generating responses in real-time (Claude Code & Codex).
- **Window Clock Arc**: An optional secondary outer arc can show how much of the current rate-limit window has elapsed or remains.
- **Countdown Mode**: Toggle between showing spent quota (`75% used`) or remaining balance (`25% left`).

### Hover Details & Smart Forecasting
- **Complete Limit Breakdown**: Hover over any ring to reveal a detailed card showing every reported quota pool, reset countdowns, and current window status.
- **Detailed Card (Optional, per account)**: Switch it on for the accounts you watch closely. The card adds the plan, when the figures were read, an estimate of what each limit is worth wherever this Mac's records can price it, and the account's recent usage — today, 7 days and 31 days of tokens, a 31-day chart, the model doing most of the work, the cache hit rate where the records sort every token by kind, and how long the prompt cache has left — for Claude Code from the tier each reply records, for Codex as the at-least-30-minutes OpenAI guarantees on GPT-5.6 and later: the card names the conversation about to lapse, and Settings lists every one — for every service Pulse has a history for: z.ai and Zhipu from their own account statistics, and Claude Code, Codex, Kimi Code, Grok, OpenCode, Cursor, Devin, Antigravity, Command Code and Copilot from this Mac's records with Token spend on.
- **Burn-Rate Forecast (Optional)**: When you turn it on, projects whether your current pace will outlast the quota window and shows an estimated time-to-exhaustion (ETA) when risk is detected. Off by default.
- **Pin Primary Window**: Pin whichever limit matters most to the ring, or let Pulse automatically track the one closest to exhaustion.

<p align="center">
  <img src="Docs/detailed-card.webp" width="620" alt="The same Codex card, compact and detailed">
</p>

### Native, Fluid & Non-Intrusive
- **Flexible Edge Docking**: Dock to the left, right, or top of your screen (above the menu bar), or float it anywhere, standing upright or lying across.
- **Multi-Monitor Native**: Drag Pulse to any secondary display; it remembers screen placement and gracefully returns if disconnected. Turn on **Follow the active display** and the single rail moves itself to whichever screen your pointer is on.
- **Auto-Collapse**: Automatically folds into a razor-thin sliver when idle to eliminate distraction, glowing red only when quota runs critically low.
- **Opt-In Notifications**: You choose which ones to switch on. Get told when a limit passes 75/80/90/95%, when the provider says it is spent, when a window you were warned about comes back, and when several checks in a row fail so the panel is quietly showing older figures, and — for the services that sell prepaid credit — when the balance falls under a figure you set. Each thing is said once: a limit already past the line when you switch this on is mentioned straight away, and again when it resets or gets worse.
- **Start Usage Windows After a Reset (Optional)**: Claude Code's and Codex's windows only start at your first message after a reset. Switch this on and Pulse sends a single "hi" through the provider's own command-line tool just after each reset, within the hours you choose, so the clock starts then rather than whenever you come back. Off by default, and it is not a feature of Anthropic or OpenAI: switching it on asks you to confirm that it may be treated as getting around usage limits.
- **Spaces-Friendly**: Keeps to the Space you are working in, leaving full-screen apps to themselves.
- **macOS Aesthetic**: Classic solid obsidian surface or native **Liquid Glass** on macOS 26+.
- **Animated Marks (Optional)**: Replace a provider's logo with a small bot that reacts to what that account is doing — working, fetching, spent, or quiet. Off by default and switched on per account, with eight personalities, eighteen body shapes and a colour of your own if you want one.
- **Rail Menu & Shortcuts**: Right-click the floating rail — or the collapsed sliver; Control-click works too — for a menu with Settings and Quit. In **Settings › General › Shortcuts** you can optionally assign global shortcuts to **Open settings** and **Show or hide the panel**; both are unset until you set one.
- **Menu Bar Usage (Optional)**: Show the fullest ring — or an account you pick — beside the menu bar icon as a figure, a small ring, or its five-hour and weekly limits side by side (`5h/9%  Wk/15%`), red past the warning line. Click it for a dashboard: an overview of every account, and a tab per account with each limit, its reset, credits, estimated spend (with Token spend on) and a link to the provider's own usage page. Turn the floating panel off from the same menu if you only want the menu bar.
- **Five Interface Languages**: English, Simplified Chinese, Traditional Chinese, Japanese and Korean, with language-aware large-number units: K/M/B, 万/亿, 萬/億, 万/億 and 만/억 respectively.

### Multi-Account & Local Ledger
- **Multi-Account Support**: Monitor multiple subscriptions for the same provider (Claude Code, Codex, Grok, Grok Bot) side-by-side with custom labels.
- **Token Spend (Settings-only)**: Off by default. Enable it on the page to scan local records; switching it off stops the scan. Reads local logs, databases and exports from a catalogue of **54 client sources**, including Gemini CLI, Cline, Roo Code, OpenClaw and GitHub Copilot. Cursor, Trae and other export sources need a prior export or capture. These are distinct from the rail's 77 quota providers; support and live-client validation vary by source. [Sources and coverage](Docs/token-spend-sources.md).
- **Clear Usage Estimates**: Opens on the last 7 days and remembers your chosen span. Costs use published API prices, not subscription charges. Unknown prices stay unavailable, incomplete counts and coarse timing are labelled, and a source that reports no token counters says so.
- **Model Details & Charts**: Open a model for input/output/cache counts and estimated costs, daily and hourly charts where the records support them, contributions by agent, and sortable, paged detail tables. Point at a chart to read the date or hour and its token count. Unavailable daily or hourly detail is shown as unavailable, not zero.
- **Seventy-seven Providers**: Claude Code, Codex, Kiro, Antigravity, Cursor, GitHub Copilot, Grok, Grok Bot, OpenCode Go, Kimi Code, Ollama Cloud, z.ai, Zhipu, MiniMax (intl. and mainland), Volcengine, Command Code, DeepSeek, Devin, Xiaomi Coding Plan, sub2api, New API, V2EX, Qoder, and StepFun. Also Abacus AI, Aixy, Alibaba Coding Plan, Alibaba Token Plan, Amp, Atlas Cloud, Augment Code, Bifrost, Chutes, ClawRouter, ClinePass, Codebuff, DeepInfra, DevPass, ElevenLabs, Factory, Gemini, GitKraken AI, Hugging Face, Hyper, IBM Bob, JetBrains AI, Kilo Code, LiteLLM, LLM API Key Proxy, LongCat, Manus, Mistral, Moonshot, Neuralwatt, Notion AI, Nous Portal, OpenAI API, Perplexity, Poe, Qwen Cloud, Raycast AI, Replicate, Sakana AI, Synthetic, T3 Chat, TypeSafe, v0, Venice, Vercel AI Gateway, Warp, Windsurf, xAI API, xKiro, Zed, ZenMux, ZoomMate.
- **Scriptable**: `Pulse --json` prints the last readings — plan, every limit, reset times, and how old the figures are — for tmux, sketchybar, Raycast, or a shell prompt. It reads the cache, so polling costs nothing.
- **Developer Integrations**: Export a Raycast extension and ready-to-configure tmux, sketchybar and shell scripts from Settings. Account links open the right pane directly. [Setup guide](Docs/integrations.md).
- **Extensions**: A small program of your own can report one account's usage — an internal quota endpoint, say — and Pulse draws it as a ring, with no fork to maintain. Nothing runs until you switch it on, and Pulse hands it no credentials. [How to write one](Docs/extensions.md).
- **Connection Diagnostics**: See the actual reading source, cache use, latest check and fallback outcomes. Contextual actions help reconnect, sign in again or fix credentials; copy a diagnostic report without account details or secrets.
- **Privacy First**: Pulse runs on your Mac under your own provider logins. It makes three kinds of connection and they are all listed here: the providers you already use, [models.dev](https://models.dev) for public model prices in the token-spend pane, and GitHub/Sparkle for app updates. Provider requests, sign-in exchanges and models.dev use the proxy chosen under Settings › Network and refresh; supported helper processes receive the same manual proxy. Sparkle update checks always follow macOS system proxy settings.

<p align="center">
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
| **sub2api** | Pasted group key; self-hosted gateway address you enter | A group's own accounting from a [sub2api](https://github.com/Wei-Shaw/sub2api) deployment — money, a quota, a subscription, or a rate-limit window, depending on how the group is set up ([Docs/providers/sub2api.md](Docs/providers/sub2api.md)) |
| **New API** | Pasted `sk-` key; self-hosted gateway address you enter | Balance from a [New API](https://github.com/QuantumNous/new-api) deployment, in whatever currency it reports; no percentage, since the reply's fraction can mean two different things ([Docs/providers/newapi.md](Docs/providers/newapi.md)) |
| **V2EX** | Pasted personal access token | AI Chat's rolling 5-hour token quota, plus a second ring for a bought top-up pack; a window that hasn't started yet shows no countdown ([Docs/providers/v2ex.md](Docs/providers/v2ex.md)) |
| **Qoder** | Nothing to enter — reads your signed-in browser session for qoder.com or qoder.com.cn, or paste a `Cookie:` header | Credit allowance (plan plus packs) with Qoder's reported reset; a team plan's shared credits show as a second ring, never summed; zero credits says so instead of drawing a ring ([Docs/providers/qoder.md](Docs/providers/qoder.md)) |
| **StepFun** | Nothing to enter — reads your signed-in browser session for platform.stepfun.com or platform.stepfun.ai, or paste a `Cookie:` header | Step Plan: a Token Plan's monthly Credits and any top-up packs as one ring, with the date the soonest of them lapse; a Coding Plan's 5-hour and weekly windows; no plan says so instead of drawing a ring ([Docs/providers/stepfun.md](Docs/providers/stepfun.md)) |

### More providers

Ported by reading [CodexBar](https://github.com/steipete/CodexBar)'s providers. **Not yet checked against a live account** — if one doesn't work for you, please [open an issue](https://github.com/qunqin24/Pulse/issues). Setup for each: [Docs/setup/](Docs/setup/). Maintainer notes: [Docs/providers/README.md](Docs/providers/README.md#profiled-providers).

| Provider | Data Route & Auth Method | Shows |
|---|---|---|
| **Abacus AI** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Compute points and the billing date |
| **Aixy** | Pasted API key | Gateway budgets by period |
| **Alibaba Coding Plan** | Pasted API key | 5-hour, weekly and monthly allowances; the international console first, then mainland |
| **Alibaba Token Plan** | Alibaba's `bl` CLI, with the login it saved | 5-hour, weekly and monthly shares used |
| **Amp** | Pasted API key | Free daily allowance, plan allowances and credits |
| **Atlas Cloud** | Pasted API key | Balance |
| **Augment Code** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Credits used this cycle |
| **Bifrost** | Pasted key; self-hosted gateway address you enter | Dollar budgets of the virtual key |
| **Chutes** | Pasted API key | Rolling window and monthly allowance |
| **ClawRouter** | Pasted API key | Monthly budget |
| **ClinePass** | Pasted API key | 5-hour, weekly and monthly limits |
| **Codebuff** | Pasted key, or the login its CLI already saved | Credits; the weekly limit with the CLI login |
| **DeepInfra** | Pasted API key | Balance; spend against the limit you set there |
| **DevPass** | Pasted API key | Weekly premium allowance and plan credits |
| **ElevenLabs** | Pasted API key | Character credits for the billing period |
| **Factory** | Pasted API key | 5-hour, weekly and monthly limits (Standard and Premium on older billing); extra-usage balance |
| **Gemini** | Gemini CLI's saved login, read only and never refreshed | Each model's quota. The login lasts about an hour, so it reads only while Gemini CLI is in use |
| **GitKraken AI** | Pasted token | Personal credits and the shared pool |
| **Hugging Face** | Pasted token, or the one `hf auth login` saved | ZeroGPU quota |
| **Hyper** | Pasted API key | Hypercredit balance |
| **IBM Bob** | Pasted API key | Bobcoins used against team budgets |
| **JetBrains AI** | The quota file your JetBrains IDE saves; nothing is sent anywhere | AI Assistant quota; updates while an IDE is running |
| **Kilo Code** | Pasted key, or the login its CLI already saved | Credit balance and Kilo Pass |
| **LiteLLM** | Pasted key; self-hosted gateway address you enter | Team and user budgets |
| **LLM API Key Proxy** | Pasted key; self-hosted gateway address you enter | Quota groups by upstream |
| **LongCat** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Token pack allowance and fuel packs |
| **Manus** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Daily and monthly credits |
| **Mistral** | Your signed-in browser session (Read), or a pasted `Cookie:` header | API and Vibe monthly allowances, and available credit |
| **Moonshot** | Pasted API key | Kimi Open Platform balance, USD or CNY |
| **Neuralwatt** | Pasted API key | kWh subscription, spending allowance and balance |
| **Notion AI** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Rolling and billing-period allowance (Business and Enterprise) |
| **Nous Portal** | Hermes Agent's saved login, read only | Monthly credit grant and balance |
| **OpenAI API** | Pasted API key | Prepaid credit balance, where the older billing route still answers |
| **Perplexity** | Your signed-in browser session (Read), or a pasted `Cookie:` header | API credit balance |
| **Poe** | Pasted API key | Point balance |
| **Qwen Cloud** | Your signed-in browser session (Read), or a pasted `Cookie:` header | 5-hour, weekly and monthly shares, and tier |
| **Raycast AI** | Your signed-in browser session (Read), or a pasted `Cookie:` header | AI credits and renewal date |
| **Replicate** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Prepaid credit balance |
| **Sakana AI** | Your signed-in browser session (Read), or a pasted `Cookie:` header | 5-hour and weekly limits |
| **Synthetic** | Pasted API key | 5-hour, weekly and search allowances |
| **T3 Chat** | Your signed-in browser session (Read), or a pasted `Cookie:` header | 4-hour window and monthly figure |
| **TypeSafe** | A pasted `Cookie:` header | Credit balance and plan |
| **v0** | Pasted API key | Billing allowance |
| **Venice** | Pasted API key | Balance, USD or DIEM |
| **Vercel AI Gateway** | Pasted API key | Balance |
| **Warp** | Pasted API key | Plan credits and add-on credits |
| **Windsurf** | windsurf.com's sign-in, read from a Chromium browser | Daily and weekly quota |
| **xAI API** | `TeamID:ManagementKey` pasted as one | A team's prepaid balance, as posted by xAI |
| **xKiro** | Pasted API key | 5-hour and weekly windows, daily free tokens and wallet |
| **Zed** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Edit predictions and the spending limit |
| **ZenMux** | Pasted management key | 5-hour and 7-day quotas, and balance |
| **ZoomMate** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Credits against the budget cap |

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
- **No Pulse backend**: Your Mac talks to the providers you already use, under your own logins. It also fetches public model prices from [models.dev](https://models.dev) for the token-spend pane and checks GitHub/Sparkle for app updates. Provider requests, sign-in exchanges and models.dev use the proxy chosen under Settings › Network and refresh; supported helper processes receive the same manual proxy. Sparkle update checks always follow macOS system proxy settings.
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
