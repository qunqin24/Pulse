# Supported services

The services Pulse draws a ring for, how each one is read, and the local clients Token spend reads. The [README](../README.md) links here; contributor detail is in [providers/README.md](providers/README.md).

## Providers and how each is read

Pulse shows the figures each service reports, and every percentage comes from that reply itself. Routes differ by product (documented client APIs, editor logins, local language servers, pasted keys) — not one official public quota API for every row. Contributor detail: [Docs/providers/README.md](providers/README.md).

| Icon | Provider | Data Route & Auth Method | Notes |
|---|---|---|---|
| <img src="icons/claude.svg" width="24" height="24" alt=""> | **Claude Code** | Account OAuth usage endpoint; automatic fallbacks to Claude Desktop session & Status Line | Reads existing CLI/Desktop session; auto-falls back seamlessly |
| <img src="icons/openai.svg" width="24" height="24" alt=""> | **Codex** | Client usage endpoint; fallback to `codex app-server` | Reads local Codex credentials directly |
| <img src="icons/kiro.svg" width="24" height="24" alt=""> | **Kiro** | Native Kiro CLI ACP usage method | Uses Kiro's signed-in CLI session; Pulse never reads or stores Kiro credentials ([details](providers/kiro.md)) |
| <img src="icons/antigravity.svg" width="24" height="24" alt=""> | **Antigravity** | Local Language Server (LSP), or the `agy` CLI | The editor's language server while it runs, otherwise Google's `agy` CLI; Automatic, CLI or Desktop app in Settings |
| <img src="icons/cursor.svg" width="24" height="24" alt=""> | **Cursor** | Cursor account usage summary and dashboard API | Shows the Cursor Models and Other Models pools, or the weekly limit on a weekly plan, from the existing editor login |
| <img src="icons/grok.svg" width="24" height="24" alt=""> | **Grok** | Grok Build CLI proxy (`cli-chat-proxy.grok.com`) | Single unified weekly pool shared across all Grok products |
| <img src="icons/xai.svg" width="24" height="24" alt=""> | **Grok Bot** | Cursor dashboard API | The xAI quota included with Cursor subscriptions |
| <img src="icons/github.svg" width="24" height="24" alt=""> | **GitHub Copilot** | GitHub Device Code authentication | Requests the `read:user` scope alone |
| <img src="icons/opencode.svg" width="24" height="24" alt=""> | **OpenCode Go** | API key or existing OpenCode CLI credentials; or the console's signed-in browser session | The console session also brings the account's request log — every machine and app, with what each request cost — to the detailed card |
| <img src="icons/kimi.svg" width="24" height="24" alt=""> | **Kimi Code** | Direct API key | Configured via Settings |
| <img src="icons/zai.svg" width="24" height="24" alt=""> | **z.ai** | Direct API key | International storefront (`api.z.ai`) |
| <img src="icons/zai.svg" width="24" height="24" alt=""> | **Zhipu** | Direct API key or saved GLM tooling credentials | Mainland storefront (`open.bigmodel.cn`) |
| <img src="icons/minimax.svg" width="24" height="24" alt=""> | **MiniMax** | Direct API key | International (`minimax.io`) or mainland (`minimaxi.com`), chosen in Settings; each site keeps its own key |
| <img src="icons/ollama.svg" width="24" height="24" alt=""> | **Ollama Cloud** | Browser session cookie | Read locally from browser. See [Docs/ollama-cloud.md](ollama-cloud.md) |
| <img src="icons/volcengine.svg" width="24" height="24" alt=""> | **Volcengine** | `arkcli` login, else a pasted access-key pair (signed Top OpenAPI) | Ark Coding & Agent plans; on automatic it prefers pasted keys over the CLI |
| <img src="icons/commandcode.svg" width="24" height="24" alt=""> | **Command Code** | Pasted key, else the login `cmd login` already saved | Credit balance in dollars, with rolling 5-hour and weekly limits; monthly plan row marked **estimated** |
| <img src="icons/deepseek.svg" width="24" height="24" alt=""> | **DeepSeek** | Pasted key; documented `GET /user/balance` | Prepaid balance only — no allowance; you pick what the ring measures against |
| <img src="icons/devin.svg" width="24" height="24" alt=""> | **Devin** | Nothing to enter — reads your browser session, no keychain prompt | Daily and weekly quota reported by Devin. With no browser session or pasted credential, reads the app's dated saved plan. Endpoint failures use only matching endpoint cache, preserving account and organization boundaries ([Docs/providers/devin.md](providers/devin.md)) |
| <img src="icons/xiaomimimo.svg" width="24" height="24" alt=""> | **Xiaomi Coding Plan** | Nothing to enter — reads your signed-in browser session, or paste a `Cookie:` header | The monthly token allowance from Xiaomi's MiMo console, with the period's end where it reports one. The prepaid balance rides along on the card. An account with no plan says so rather than drawing 0% ([Docs/providers/xiaomi-coding-plan.md](providers/xiaomi-coding-plan.md)) |
| <img src="icons/sub2api.svg" width="24" height="24" alt=""> | **sub2api** | Pasted group key; self-hosted gateway address you enter | A group's own accounting from a [sub2api](https://github.com/Wei-Shaw/sub2api) deployment — money, a quota, a subscription, or a rate-limit window, depending on how the group is set up ([Docs/providers/sub2api.md](providers/sub2api.md)) |
| <img src="icons/newapi.svg" width="24" height="24" alt=""> | **New API** | Pasted `sk-` key; self-hosted gateway address you enter | Balance from a [New API](https://github.com/QuantumNous/new-api) deployment, in whatever currency it reports; no percentage, since the reply's fraction can mean two different things ([Docs/providers/newapi.md](providers/newapi.md)) |
| <img src="icons/v2ex.svg" width="24" height="24" alt=""> | **V2EX** | Pasted personal access token | AI Chat's rolling 5-hour token quota, plus a second ring for a bought top-up pack; a window that hasn't started yet shows no countdown ([Docs/providers/v2ex.md](providers/v2ex.md)) |
| <img src="icons/qoder.svg" width="24" height="24" alt=""> | **Qoder** | Nothing to enter — reads your signed-in browser session for qoder.com or qoder.com.cn, or paste a `Cookie:` header | Credit allowance (plan plus packs) with Qoder's reported reset; a team plan's shared credits show as a second ring, never summed; optionally, plan credits, the top-up pack and dedicated credits each on a row of their own; zero credits says so instead of drawing a ring ([Docs/providers/qoder.md](providers/qoder.md)) |
| <img src="icons/stepfun.svg" width="24" height="24" alt=""> | **StepFun** | Nothing to enter — reads your signed-in browser session for platform.stepfun.com or platform.stepfun.ai, or paste a `Cookie:` header | Step Plan: a Token Plan's monthly Credits and any top-up packs as one ring, with the date the soonest of them lapse; a Coding Plan's 5-hour and weekly windows; no plan says so instead of drawing a ring ([Docs/providers/stepfun.md](providers/stepfun.md)) |
| <img src="icons/dimagent.svg" width="24" height="24" alt=""> | **DimAgent** | `dim usage --json`, using the CLI's saved login | Subscription credits and web-search allowance, with separate add-on packs; no credential import ([details](providers/dimagent.md)) |

## More providers

Ported by reading [CodexBar](https://github.com/steipete/CodexBar)'s providers. **Not yet checked against a live account** — if one doesn't work for you, please [open an issue](https://github.com/qunqin24/Pulse/issues). Setup for each: [Docs/setup/](setup/). Maintainer notes: [Docs/providers/README.md](providers/README.md#profiled-providers).

| Icon | Provider | Data Route & Auth Method | Shows |
|---|---|---|---|
| | **Abacus AI** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Compute points and the billing date |
| | **Aixy** | Pasted API key | Gateway budgets by period |
| <img src="icons/alibabacloud.svg" width="24" height="24" alt=""> | **Alibaba Coding Plan** | Pasted API key | 5-hour, weekly and monthly allowances; the international console first, then mainland |
| <img src="icons/alibabacloud.svg" width="24" height="24" alt=""> | **Alibaba Token Plan** | Alibaba's `bl` CLI, with the login it saved | 5-hour, weekly and monthly shares used |
| <img src="icons/amp.svg" width="24" height="24" alt=""> | **Amp** | Pasted API key | Free daily allowance, plan allowances and credits |
| <img src="icons/atlascloud.svg" width="24" height="24" alt=""> | **Atlas Cloud** | Pasted API key | Balance |
| | **Augment Code** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Credits used this cycle |
| | **Bifrost** | Pasted key; self-hosted gateway address you enter | Dollar budgets of the virtual key |
| <img src="icons/chutes.svg" width="24" height="24" alt=""> | **Chutes** | Pasted API key | Rolling window and monthly allowance |
| <img src="icons/openclaw.svg" width="24" height="24" alt=""> | **ClawRouter** | Pasted API key | Monthly budget |
| <img src="icons/cline.svg" width="24" height="24" alt=""> | **ClinePass** | Pasted API key | 5-hour, weekly and monthly limits |
| | **Codebuff** | Pasted key, or the login its CLI already saved | Credits; the weekly limit with the CLI login |
| <img src="icons/deepinfra.svg" width="24" height="24" alt=""> | **DeepInfra** | Pasted API key | Balance; spend against the limit you set there |
| | **DevPass** | Pasted API key | Weekly premium allowance and plan credits |
| <img src="icons/elevenlabs.svg" width="24" height="24" alt=""> | **ElevenLabs** | Pasted API key | Character credits for the billing period |
| | **Factory** | Pasted API key | 5-hour, weekly and monthly limits (Standard and Premium on older billing); extra-usage balance |
| <img src="icons/geminicli.svg" width="24" height="24" alt=""> | **Gemini** | Gemini CLI's saved login, read only and never refreshed | Each model's quota. The login lasts about an hour, so it reads only while Gemini CLI is in use |
| | **GitKraken AI** | Pasted token | Personal credits and the shared pool |
| <img src="icons/huggingface.svg" width="24" height="24" alt=""> | **Hugging Face** | Pasted token, or the one `hf auth login` saved | ZeroGPU quota |
| | **Hyper** | Pasted API key | Hypercredit balance |
| <img src="icons/ibm.svg" width="24" height="24" alt=""> | **IBM Bob** | Pasted API key | Bobcoins used against team budgets |
| | **JetBrains AI** | The quota file your JetBrains IDE saves; nothing is sent anywhere | AI Assistant quota; updates while an IDE is running |
| <img src="icons/kilocode.svg" width="24" height="24" alt=""> | **Kilo Code** | Pasted key, or the login its CLI already saved | Credit balance and Kilo Pass |
| | **LiteLLM** | Pasted key; self-hosted gateway address you enter | Team and user budgets |
| | **LLM API Key Proxy** | Pasted key; self-hosted gateway address you enter | Quota groups by upstream |
| <img src="icons/longcat.svg" width="24" height="24" alt=""> | **LongCat** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Token pack allowance and fuel packs |
| <img src="icons/manus.svg" width="24" height="24" alt=""> | **Manus** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Daily and monthly credits |
| <img src="icons/mistral.svg" width="24" height="24" alt=""> | **Mistral** | Your signed-in browser session (Read), or a pasted `Cookie:` header | API and Vibe monthly allowances, and available credit |
| <img src="icons/moonshot.svg" width="24" height="24" alt=""> | **Moonshot** | Pasted API key | Kimi Open Platform balance, USD or CNY |
| | **Neuralwatt** | Pasted API key | kWh subscription, spending allowance and balance |
| <img src="icons/notion.svg" width="24" height="24" alt=""> | **Notion AI** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Rolling and billing-period allowance (Business and Enterprise) |
| <img src="icons/hermesagent.svg" width="24" height="24" alt=""> | **Nous Portal** | Hermes Agent's saved login, read only | Monthly credit grant and balance |
| <img src="icons/openai.svg" width="24" height="24" alt=""> | **OpenAI API** | Pasted API key | Prepaid credit balance, where the older billing route still answers |
| <img src="icons/perplexity.svg" width="24" height="24" alt=""> | **Perplexity** | Your signed-in browser session (Read), or a pasted `Cookie:` header | API credit balance |
| <img src="icons/poe.svg" width="24" height="24" alt=""> | **Poe** | Pasted API key | Point balance |
| <img src="icons/qwen.svg" width="24" height="24" alt=""> | **Qwen Cloud** | Your signed-in browser session (Read), or a pasted `Cookie:` header | 5-hour, weekly and monthly shares, and tier |
| | **Raycast AI** | Your signed-in browser session (Read), or a pasted `Cookie:` header | AI credits and renewal date |
| <img src="icons/replicate.svg" width="24" height="24" alt=""> | **Replicate** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Prepaid credit balance |
| <img src="icons/sakana.svg" width="24" height="24" alt=""> | **Sakana AI** | Your signed-in browser session (Read), or a pasted `Cookie:` header | 5-hour and weekly limits |
| | **Synthetic** | Pasted API key | 5-hour, weekly and search allowances |
| | **T3 Chat** | Your signed-in browser session (Read), or a pasted `Cookie:` header | 4-hour window and monthly figure |
| | **TypeSafe** | A pasted `Cookie:` header | Credit balance and plan |
| <img src="icons/v0.svg" width="24" height="24" alt=""> | **v0** | Pasted API key | Billing allowance |
| <img src="icons/venice.svg" width="24" height="24" alt=""> | **Venice** | Pasted API key | Balance, USD or DIEM |
| <img src="icons/vercel.svg" width="24" height="24" alt=""> | **Vercel AI Gateway** | Pasted API key | Balance |
| | **Warp** | Pasted API key | Plan credits and add-on credits |
| <img src="icons/windsurf.svg" width="24" height="24" alt=""> | **Windsurf** | windsurf.com's sign-in, read from a Chromium browser | Daily and weekly quota |
| <img src="icons/xai.svg" width="24" height="24" alt=""> | **xAI API** | `TeamID:ManagementKey` pasted as one | A team's prepaid balance, as posted by xAI |
| | **xKiro** | Pasted API key | 5-hour and weekly windows, daily free tokens and wallet |
| | **Zed** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Edit predictions and the spending limit |
| <img src="icons/zenmux.svg" width="24" height="24" alt=""> | **ZenMux** | Pasted management key | 5-hour and 7-day quotas, and balance |
| | **ZoomMate** | Your signed-in browser session (Read), or a pasted `Cookie:` header | Credits against the budget cap |

## Token spend sources

Token spend reads what each client leaves on this Mac — logs, databases and exports — once it is switched on in Settings; nothing here is sent anywhere. The paths are the macOS defaults; Linux-style and editor-variant locations are read too. Where Pulse also draws the same product's limits as a ring, the last column names that provider. Evidence and limits for each source: [Docs/token-spend-sources.md](token-spend-sources.md).

| Icon | Client | Read from | Ring in Pulse |
|---|---|---|---|
| <img src="icons/claude.svg" width="24" height="24" alt=""> | **Claude Code** | `~/.claude/projects/` | Claude Code |
| <img src="icons/openai.svg" width="24" height="24" alt=""> | **Codex** | `~/.codex/sessions/`, `~/.codex/archived_sessions/` | Codex |
| <img src="icons/opencode.svg" width="24" height="24" alt=""> | **OpenCode** | `~/.local/share/opencode/opencode.db` | OpenCode Go |
| <img src="icons/kilocode.svg" width="24" height="24" alt=""> | **Kilo CLI** | `~/.local/share/kilo/kilo.db` | Kilo Code |
| <img src="icons/grok.svg" width="24" height="24" alt=""> | **Grok Build** | `~/.grok/sessions/` | Grok |
| <img src="icons/kimi.svg" width="24" height="24" alt=""> | **Kimi CLI** | `~/.kimi/sessions/` | Kimi Code |
| <img src="icons/devin.svg" width="24" height="24" alt=""> | **Devin** | `~/.local/share/devin/cli/sessions.db` | Devin |
| <img src="icons/devin.svg" width="24" height="24" alt=""> | **Devin Desktop** | `~/Library/Application Support/Devin/User/acp-events/` | Devin |
| <img src="icons/cursor.svg" width="24" height="24" alt=""> | **Cursor** | `~/.config/tokscale/cursor-cache/` † | Cursor |
| <img src="icons/github.svg" width="24" height="24" alt=""> | **GitHub Copilot** | `~/.copilot/otel/`, `~/.copilot/data.db`, VS Code `workspaceStorage/*/chatSessions/` | GitHub Copilot |
| <img src="icons/kiro.svg" width="24" height="24" alt=""> | **Kiro** | `~/.kiro/sessions/cli/` | Kiro |
| <img src="icons/antigravity.svg" width="24" height="24" alt=""> | **Antigravity CLI** | `~/.gemini/antigravity-cli/conversations/` | Antigravity |
| <img src="icons/antigravity.svg" width="24" height="24" alt=""> | **Antigravity IDE** | `~/.gemini/antigravity/conversations/`, `~/.gemini/antigravity-ide/conversations/` | Antigravity |
| <img src="icons/antigravity.svg" width="24" height="24" alt=""> | **Antigravity (export)** | `~/.config/tokscale/antigravity-cache/sessions/` † | Antigravity |
| <img src="icons/gemini.svg" width="24" height="24" alt=""> | **Gemini CLI** | `~/.gemini/tmp/` | Gemini |
| <img src="icons/qwen.svg" width="24" height="24" alt=""> | **Qwen Code** | `~/.qwen/projects/` | — |
| <img src="icons/amp.svg" width="24" height="24" alt=""> | **Amp** | `~/.local/share/amp/threads/` | Amp |
| | **Droid** | `~/.factory/sessions/` | Factory |
| <img src="icons/cline.svg" width="24" height="24" alt=""> | **Cline** | VS Code `globalStorage/saoudrizwan.claude-dev/tasks/`, `~/.cline/data/sessions/` | ClinePass |
| <img src="icons/roocode.svg" width="24" height="24" alt=""> | **Roo Code** | VS Code `globalStorage/rooveterinaryinc.roo-cline/tasks/` | — |
| <img src="icons/kilocode.svg" width="24" height="24" alt=""> | **Kilo Code** | VS Code `globalStorage/kilocode.kilo-code/tasks/` | Kilo Code |
| <img src="icons/commandcode.svg" width="24" height="24" alt=""> | **Command Code** | `~/.commandcode/projects/` | Command Code |
| | **Codebuff** | `~/.config/manicode/` | Codebuff |
| | **Freebuff** | `~/.config/manicode/` | Codebuff |
| | **Augment** | `~/.augment/sessions/` | Augment Code |
| <img src="icons/junie.svg" width="24" height="24" alt=""> | **Junie** | `~/.junie/sessions/` | JetBrains AI |
| | **Zed** | `~/Library/Application Support/Zed/threads/threads.db` | Zed |
| | **Warp** | `~/.config/tokscale/warp-cache/` † | Warp |
| <img src="icons/minimax.svg" width="24" height="24" alt=""> | **MiniMax Code** | `~/.minimax/v2/sessions/` (or a capture in `~/.config/tokscale/headless/mcode/` †) | MiniMax |
| <img src="icons/openclaw.svg" width="24" height="24" alt=""> | **OpenClaw** | `~/.openclaw/agents/` | — |
| <img src="icons/hermesagent.svg" width="24" height="24" alt=""> | **Hermes** | `~/.hermes/state.db` | — |
| <img src="icons/goose.svg" width="24" height="24" alt=""> | **Goose** | `~/Library/Application Support/goose/sessions/sessions.db` | — |
| <img src="icons/tencent.svg" width="24" height="24" alt=""> | **CodeBuddy** | `~/.codebuddy/` | — |
| <img src="icons/tencent.svg" width="24" height="24" alt=""> | **WorkBuddy** | `~/.workbuddy/`, `~/.workbuddy-ai/` | — |
| <img src="icons/cherrystudio.svg" width="24" height="24" alt=""> | **Cherry Studio** | `~/Library/Application Support/CherryStudio/` | — |
| <img src="icons/trae.svg" width="24" height="24" alt=""> | **Trae** | `~/.config/tokscale/trae-cache/sessions/` † | — |
| <img src="icons/xiaomimimo.svg" width="24" height="24" alt=""> | **MiMo Code** | `~/.local/share/mimocode/` | — |
| <img src="icons/deepseek.svg" width="24" height="24" alt=""> | **DeepSeek Harness** | `~/.dsh/sessions/` | — |
| <img src="icons/lmstudio.svg" width="24" height="24" alt=""> | **LM Studio** | `~/.lmstudio/server-logs/` | — |
| <img src="icons/unsloth.svg" width="24" height="24" alt=""> | **Unsloth** | `~/.unsloth/studio/studio.db` | — |
| <img src="icons/pi.svg" width="24" height="24" alt=""> | **Pi** | `~/.pi/agent/sessions/` | — |
| | **Oh My Pi** | `~/.omp/agent/sessions/` | — |
| | **OmO Native** | `~/.senpi/agent/sessions/` | — |
| | **Gajae Code** | `~/.gjc/agent/sessions/` | — |
| | **Kimchi** | `~/.config/kimchi/harness/sessions/` | — |
| | **Prime Agent** | `~/.prime/agent/sessions/` | — |
| <img src="icons/opencode.svg" width="24" height="24" alt=""> | **OpenCodeReview** | `~/.opencodereview/sessions/` | — |
| | **ZCode** | `~/.zcode/projects/`, `~/.zcode/cli/db/db.sqlite` | — |
| | **Crush** | `~/.local/share/crush/projects.json` | — |
| | **Mux** | `~/.mux/sessions/` | — |
| | **JCode** | `~/.jcode/sessions/` | — |
| | **FX** | `~/.fx/sessions/` | — |
| | **Reasonix** | `~/.reasonix/stats/` | — |
| | **Hindsight** | `~/.hindsight/usage/` † | — |

† Needs an export or capture first, or a file in `~/Library/Application Support/Pulse/UsageImports/<client>/`.
