# Providers

Pulse tracks **seventy-seven** built-in quota providers: twenty-four written case by case and fifty-three described by a `ProviderProfile` ([Adding a provider](#adding-a-provider), [Profiled providers](#profiled-providers)). There is no Pulse backend or account; each provider is read by whatever route its product offers — often an undocumented account endpoint the product itself calls, sometimes a documented usage path, sometimes a local helper that exists only while an editor is open.

This directory owns routes, credentials, cookies, extra logins and their failure lessons. Service code is authoritative; historical measurements are labelled; live-account checks are claimed only where the provider page explicitly records them. Not here: extensions (one more case, `.pulseExtension`, left out of `Provider.builtIn` — [`../extensions.md`](../extensions.md)); token spend readers ([`../token-spend.md`](../token-spend.md), [`../token-spend-sources.md`](../token-spend-sources.md)) — do not add one to this directory; Ollama's setup and page parser ([`../ollama-cloud.md`](../ollama-cloud.md)).

Shared types: [`UsageProvider.swift`](../../Sources/Pulse/Usage/UsageProvider.swift), [`MonitoredAccount.swift`](../../Sources/Pulse/Usage/MonitoredAccount.swift), [`ProviderUsage.swift`](../../Sources/Pulse/Usage/ProviderUsage.swift), [`UsageSource.swift`](../../Sources/Pulse/Usage/UsageSource.swift). Sign-in machinery: [authentication.md](authentication.md).

## Current matrix

Accounts the stored rail does not mention are appended **in name order** (`AppSettings.orderedAccounts`), not in the declaration order used below.

| `Provider` | Ring name (page) | Icon | Credential | Extra accounts | Route choice | Local transcripts | First-run evidence |
|---|---|---|---|---|---|---|---|
| `.claudeCode` | [Claude Code](claude-code.md) | `claude` | Borrow CLI login; Pulse OAuth for extras | yes | endpoint / desktop / status line | yes | `~/.claude`, Claude support directory, or `Claude.app` exists |
| `.codex` | [Codex](codex.md) | `openai` | Borrow `~/.codex/auth.json`; Pulse OAuth for extras | yes | endpoint / app-server | yes | `~/.codex` exists |
| `.kiro` | [Kiro](kiro.md) | `kiro` | Borrow Kiro CLI login through ACP | no | native ACP | no | Kiro CLI data or app exists |
| `.antigravity` | [Antigravity](antigravity.md) | `antigravity` | Loopback language server while the app is open, else the `agy` CLI’s own login | no | automatic / CLI / desktop app | no | `Antigravity.app` |
| `.cursor` | [Cursor](cursor.md) | `cursor` | Cookie built from the editor’s stored token | no (deliberate) | one, named | no | Cursor `state.vscdb` exists |
| `.openCodeGo` | [OpenCode Go](opencode-go.md) | `opencode` | Pasted key, else OpenCode’s `auth.json`; the console's browser session as a second credential (limits without a key, and the request log) | no | pasted / found key | no | OpenCode `auth.json` exists |
| `.kimiCode` | [Kimi Code](kimi-code.md) | `kimi` | Pasted key | no | pasted key | no | none — stays off until switched on |
| `.ollamaCloud` | [Ollama Cloud](ollama-cloud.md) | `ollama` | Browser session cookie (not an API key) | no | session | no | none |
| `.zai` | [z.ai](zai.md) | `zai` | Pasted key | no | pasted key | no | none |
| `.glmCoding` | [Zhipu](zai.md) | `zai` | Pasted key, else mainland files | no | pasted / found key | no | mainland key file |
| `.minimax` | [MiniMax](minimax.md) | `minimax` | Pasted key, one per site (`minimax.io` / `minimaxi.com`) | no | pasted key | no | none |
| `.copilot` | [GitHub Copilot](copilot.md) | `github` | GitHub device login; token in `keys.dat` | no | sign-in | no | none |
| `.grok` | [Grok](grok.md) | `grok` | Borrow `~/.grok/auth.json`; Pulse OAuth for extras | yes | one, named (primary) | no | `~/.grok` exists |
| `.grokBot` | [Grok Bot](grok-bot.md) | `xai` | Cursor cookie; Cursor web login for extras | yes | one, named (primary) | no | **standalone** `Grok Bot.app` only |
| `.volcengine` | [Volcengine](volcengine.md) | `volcengine` | A pasted `AK:SK` pair, else `arkcli`'s own login (also the fallback when the keys' request is unreachable) | no | arkcli / signed endpoint | no | none — stays off until switched on |
| `.commandCode` | [Command Code](command-code.md) | `commandcode` | Pasted key, else `~/.commandcode/auth.json` | no | pasted / found key | no | `~/.commandcode/auth.json` exists |
| `.deepSeek` | [DeepSeek](deepseek.md) | `deepseek` | Pasted key; the console's sign-in from a Chromium browser's `localStorage` as a second credential (balance without a key, and the daily usage) | no | one, documented | no | none |
| `.devin` | [Devin](devin.md) | `devin` | Browser `localStorage` (no keychain); optional pasted `token org` | no | saved plan / endpoint | no | the app's `state.vscdb` exists |
| `.xiaomiMiMo` | [Xiaomi Coding Plan](xiaomi-coding-plan.md) | `xiaomimimo` | Browser session for `platform.xiaomimimo.com`, or a pasted `Cookie:` header | no | one, named | no | none |
| `.sub2api` | [sub2api](sub2api.md) | `sub2api` | Pasted group key, **plus an address the reader types** | no | one, documented | no | none — stays off until switched on |
| `.newAPI` | [New API](newapi.md) | `newapi` | Pasted relay key, **plus an address the reader types** | no | one, documented | no | none — stays off until switched on |
| `.v2ex` | [V2EX](v2ex.md) | `v2ex` | Pasted Personal Access Token | no | one, documented | no | none — stays off until switched on |
| `.qoder` | [Qoder](qoder.md) | `qoder` | Browser session for the chosen site (`qoder.com` / `qoder.com.cn`), or a pasted `Cookie:` header | no | one, the account page's own | no | `Application Support/Qoder` or `QoderCN`, or `Qoder.app` |
| `.stepFun` | [StepFun](stepfun.md) | `stepfun` | Browser session for the chosen site (`platform.stepfun.com` / `platform.stepfun.ai`), or a pasted `Cookie:` header | no | one, the console's own | no | `~/.stepcode` (Step Code CLI) |

- **Browser-session providers.** Ollama Cloud, Xiaomi Coding Plan, Qoder and StepFun are the four hand-written providers read from a browser session (profiled ones: [their table](#profiled-providers)). They share [`BrowserCookies.swift`](../../Sources/Pulse/Auth/BrowserCookies.swift) and nothing else: what counts as a session differs per site, and a shared filter would forward whichever cookie any one of them adds next. Qoder's filter is the only deny list, because its session cookie has no published name ([qoder.md](qoder.md)).
- **Shared services, separate providers.** Z.ai and GLM Coding Plan share [`ZaiUsageService.swift`](../../Sources/Pulse/Providers/ZaiUsageService.swift); the pair is two rings, two accounts, two keys. MiniMax's two sites are one provider with a site setting, each keeping its own key ([minimax.md](minimax.md)).

## Subscriptions and API accounts

`Provider.billing` sorts every provider into one of two kinds, listed apart in Settings and the chooser: a **subscription** sells a plan whose limits turn over on a clock, and its figure is a percentage the provider states; an **API** account is money put in and drawn down by the call, with a balance or a spend and no allowance. A provider with both is filed under the one its buyers mostly pay for. Built-in cases answer in `Provider.billing` (DeepSeek, sub2api and New API are API); profiled ones set `billing` in their profile.

**Every API account's ring follows DeepSeek's three modes**, as does an extension that reports a balance ([../extensions.md](../extensions.md#a-balance), [deepseek.md](deepseek.md#there-is-no-allowance-so-the-ring-has-no-denominator)): since top-up (a peak Pulse watched), a budget the reader typed, or the balance alone.

- `BalanceRing.applying` gives a live reading that is money and nothing else its one `.balance` window, per account (`AppSettings.balanceBasis(for:)` / `balanceBudget(for:)`); watched peaks live in `balance-baseline.json`, one per account and currency.
- A reading with limits of its own is left alone — those are the provider's figures — and its pane shows no basis rows.
- **A balance ring never says spent.** A zero or negative balance is arithmetic, not the provider's word (Moonshot runs negative and keeps working; xAI's posted ledger can read zero with credit left), so the ring fills to 99% for alerts and no further.
- DeepSeek still makes its own ring in its service and keeps its own settings and file, predating the general rule; its pane rows (**Ring measures**, **Full tank**) are now every such account's.

## Profiled providers

Each is one file under `Sources/Pulse/Providers/Profiled/`, with a notes page here (reply shape, what it leaves out and why) and a user setup page under the same slug in [`../setup/`](../setup/). Except for DimAgent, these shapes are **second-hand**, read from CodexBar's providers and tests (MIT), not from a live account; each page says so. DimAgent's shape was observed from its own CLI; its tests use anonymized replacement figures.

| `Provider` | Ring name (notes page) | Credential | Money balance |
|---|---|---|---|
| `.dimAgent` | [DimAgent](dimagent.md) | the Dim CLI's own login (`dim usage --json`) | |
| `.clinePass` | [ClinePass](clinepass.md) | pasted key | |
| `.alibabaCodingPlan` | [Alibaba Coding Plan](alibaba-coding-plan.md) | pasted key | |
| `.alibabaTokenPlan` | [Alibaba Token Plan](alibaba-token-plan.md) | the tool's own login on this Mac | |
| `.qwenCloud` | [Qwen Cloud](qwen-cloud.md) | browser session | |
| `.factory` | [Factory](factory.md) | pasted key | |
| `.gemini` | [Gemini](gemini.md) | the tool's own login on this Mac | |
| `.kiloCode` | [Kilo Code](kilo-code.md) | pasted key or the tool's own login | yes |
| `.augment` | [Augment Code](augment.md) | browser session | |
| `.jetBrainsAI` | [JetBrains AI](jetbrains-ai.md) | the tool's own login on this Mac | |
| `.t3Chat` | [T3 Chat](t3-chat.md) | browser session | |
| `.synthetic` | [Synthetic](synthetic.md) | pasted key | |
| `.elevenLabs` | [ElevenLabs](elevenlabs.md) | pasted key | |
| `.warp` | [Warp](warp.md) | pasted key | |
| `.windsurf` | [Windsurf](windsurf.md) | browser storage (Chromium) | |
| `.bifrost` | [Bifrost](bifrost.md) | key + your server address | |
| `.chutes` | [Chutes](chutes.md) | pasted key | |
| `.longCat` | [LongCat](longcat.md) | browser session | |
| `.zoomMate` | [ZoomMate](zoommate.md) | browser session | |
| `.notionAI` | [Notion AI](notion-ai.md) | browser session | |
| `.ibmBob` | [IBM Bob](ibm-bob.md) | pasted key | |
| `.nousPortal` | [Nous Portal](nous-portal.md) | the tool's own login on this Mac | yes |
| `.raycastAI` | [Raycast AI](raycast-ai.md) | browser session | |
| `.gitKraken` | [GitKraken AI](gitkraken.md) | pasted key | |
| `.xKiro` | [xKiro](xkiro.md) | pasted key | yes |
| `.abacus` | [Abacus AI](abacus.md) | browser session | |
| `.moonshot` | [Moonshot](moonshot.md) | pasted key | yes |
| `.hyper` | [Hyper](hyper.md) | pasted key | |
| `.atlasCloud` | [Atlas Cloud](atlas-cloud.md) | pasted key | yes |
| `.poe` | [Poe](poe.md) | pasted key | |
| `.venice` | [Venice](venice.md) | pasted key | yes |
| `.openAIPlatform` | [OpenAI API](openai-api.md) | pasted key | yes |
| `.amp` | [Amp](amp.md) | pasted key | yes |
| `.zed` | [Zed](zed.md) | browser session | |
| `.sakana` | [Sakana AI](sakana.md) | browser session | yes |
| `.mistral` | [Mistral](mistral.md) | browser session | yes |
| `.codebuff` | [Codebuff](codebuff.md) | pasted key or the tool's own login | |
| `.llmProxy` | [LLM API Key Proxy](llm-proxy.md) | key + your server address | |
| `.liteLLM` | [LiteLLM](litellm.md) | key + your server address | |
| `.aixy` | [Aixy](aixy.md) | pasted key | |
| `.neuralwatt` | [Neuralwatt](neuralwatt.md) | pasted key | yes |
| `.clawRouter` | [ClawRouter](clawrouter.md) | pasted key | |
| `.zenMux` | [ZenMux](zenmux.md) | pasted key | yes |
| `.v0` | [v0](v0.md) | pasted key | |
| `.devPass` | [DevPass](devpass.md) | pasted key | |
| `.perplexity` | [Perplexity](perplexity.md) | browser session | yes |
| `.manus` | [Manus](manus.md) | browser session | |
| `.huggingFace` | [Hugging Face](hugging-face.md) | pasted key or the tool's own login | |
| `.deepInfra` | [DeepInfra](deepinfra.md) | pasted key | yes |
| `.xaiAPI` | [xAI API](xai-api.md) | pasted key | yes |
| `.replicate` | [Replicate](replicate.md) | browser session | yes |
| `.typeSafe` | [TypeSafe](typesafe.md) | browser session | yes |
| `.vercelAIGateway` | [Vercel AI Gateway](vercel-ai-gateway.md) | pasted key | yes |

Left out, and why:

- Already here under other names: Doubao, Kimi, MiMo, Ollama, z.ai, OpenCode.
- Cost money to read: Azure OpenAI and AWS Bedrock (a real inference call; $0.01 per Cost Explorer call); Muse mints an inference key to read its quota.
- Report counts or health, not an allowance or a balance: Deepgram, CodeRabbit, Wayfinder, llmman.
- Would be cost estimates from local logs: Pi, Vertex AI.
- Report only spend, which Pulse has no place for yet: Fireworks, Groq, ai&.
- Helmcode needs a session cookie nobody has named, and a site picker.

## Shared contracts

Refresh loop, cache, ledger and forecast: [`../refresh-and-data.md`](../refresh-and-data.md). First-run, offer-once and empty rail: [`../architecture.md`](../architecture.md). Only **provider-specific** differences are kept here.

### Pulse does not invent a percentage

If a provider does not report a figure, the UI says so; never derive a percentage from local token counts. Labelled exceptions, each withheld (nothing drawn, not a zero) when its inputs cannot carry it: the money estimate ([`../refresh-and-data.md`](../refresh-and-data.md)); Command Code's monthly plan grant ([command-code.md](command-code.md)); and the `BalanceRing` of every API account or extension that reports money and no allowance ([above](#subscriptions-and-api-accounts)), DeepSeek's first ([deepseek.md](deepseek.md)) — its denominator is one Pulse watched, one the reader typed, or none. The self-hosted gateways (sub2api, New API) also report money with no ceiling a reply can be divided by ([sub2api.md](sub2api.md), [newapi.md](newapi.md)), so they get the same labelled ring, never a denominator the gateway stated. Why: [`../decisions/reported-figures.md`](../decisions/reported-figures.md).

### Spent comes from the provider

`isExhausted` is the provider's judgement (`severity` / `locked_reason`, `limit_reached`, a status other than `ok`, …), not “percentage ≥ 100”; a spend limit can run past 100%. An unrecognised severity counts as spent (the safer mistake). Codex flags a whole *group*; only its fullest window is marked.

### Remaining vs spent

Downstream UI talks about what is **gone**. Antigravity, MiniMax, Copilot and some Kimi `limits[].detail` fields report what is left and are inverted at the boundary. Grok Bot's `usagePercent` and Command Code's spend and window limits are already spent; Command Code's **credit balance** becomes a pool, not an inversion. Do not invert twice.

### `windowSeconds` is not evidence of a reported length

Some windows carry a length only so the row sorts: Kimi's rolling week, Cursor's 28–31 day cycle and Copilot's calendar month (both stored as 30), Grok Bot's seven days when no reset is stated, sub2api's quota and subscription periods, Qoder's credits and team pool, StepFun's Token Plan credits, V2EX's top-up pack, and V2EX's five-hour window before it starts ([v2ex.md](v2ex.md)). They keep `UsageWindow.reportsLength` false, and the window-clock arc and forecast divide only by a stated length. A sort key once showed as “7 days” (`UsageDetailCard.resetText` fell back to `lengthText` when `resetsAt` was nil).

### Providers that read a browser, from two different files

- **Cookie** (`usesSessionCookie`): Ollama, Xiaomi Coding Plan, Qoder, StepFun and every profiled `.sessionCookie`. SQLite, encrypted under a login-keychain key, so reading raises a permission prompt; Firefox and Safari are offered alongside Chromium.
- **`localStorage`** (`readsBrowserStorage`, which also covers the cookie providers): Devin and the profiled `.browserStorage` (Windsurf). LevelDB, unencrypted — no prompt, Chromium only ([devin.md](devin.md)). [`ChromiumLocalStorage`](../../Sources/Pulse/Auth/ChromiumLocalStorage.swift) is the only place Pulse parses somebody else's binary format.

### Shared unavailability copy names no provider

Shared `ProviderUsage.Unavailability` cases (`.apiKeyMissing`, `.apiKeyRefused`, `.signedOut`, `.unreachable`, …) stay generic; they once all said “Codex”, even for Claude Code. Provider-specific cases exist only where the *remedy* names a tool (`claudeLoginExpired`, `cursorSignInRequired`, `grokBotNotIncluded`, …); a Grok Bot primary may name Cursor, where its credential comes from. OpenCode Go uses `.apiKeyRefused`; there is no `.openCodeKeyRefused`.

### Disabled providers are not fetched

A switched-off provider is not on the refresh pass, and its Settings pane does not preload credentials or history. After the initial choice, a deliberate refresh can still ask it by name.

### First-run evidence (per provider)

Chooser, legacy restoration, offer-once and empty rail: [`../architecture.md`](../architecture.md#provider-choice-before-monitoring). `ProviderDiscovery.swift` only checks that named files, directories or app bundles exist — it opens no database, key file, browser storage or Keychain — so OpenCode Go, mainland GLM and Command Code count as **detected even with empty or unreadable files**. Detection is a hint, never enables a ring; every provider starts unchecked in the chooser.

`ProviderAccess.swift` writes the descriptions shown before selection and above a disabled provider's controls. Each names what will be read: Claude its CLI Keychain/file access and the desktop cookie-store grant; Codex its auth file and helper; Kiro its ACP helper (credentials stay in Kiro); Cursor and Grok Bot Cursor's local database; Grok its auth file; Devin Chromium web storage and the saved desktop plan (no Keychain prompt); Ollama, Xiaomi, Qoder and StepFun browser-session import, which can ask for browser Keychain access; key providers the entered key, plus local fallbacks for OpenCode, Zhipu and Command Code; Copilot its Settings login; Volcengine arkcli / access keys; Antigravity the local server, its connection token and the `agy` CLI.

### Seeded state is not “Loading…”

`UsageStore.initialState` does not seed accounts as `.loading`: providers that keep a credential start with a setup reason without touching the credential store, and the first selected fetch decides whether a saved login works. `loadAPIKeys` reads only enabled providers and replaces placeholders, never readings. Do not bring back the removed `canReportWithoutSetup` probe: a seeded slot is not permission to read a key.

### Cache (provider differences)

Shared rules: [`../refresh-and-data.md`](../refresh-and-data.md#cache). Never paper over `.apiKeyMissing`, `.ollamaSessionMissing`, `.signedOut`, `.claudeDesktopNotSignedIn` or `.claudeDesktopKeyRefused`. Claude Code's status-line capture stays `.live` for ten minutes (`freshFor`) even when a later endpoint reading exists; reconciliation goes by `observedAt` ([claude-code.md](claude-code.md)).

### Keys and logins Pulse keeps

- `usesAPIKey` — Settings draws a paste field. Profiled: any credential but `.localLogin`. Hand-written: OpenCode Go, Kimi Code, Ollama Cloud, Z.ai, GLM Coding Plan, MiniMax, Volcengine, Command Code, DeepSeek, Devin, Xiaomi Coding Plan, sub2api, New API, V2EX, Qoder, StepFun. Optional for Volcengine, Command Code and Devin (each has a route needing nothing pasted); Devin's holds `token org`, whitespace-separated, for readers without a Chromium browser ([devin.md](devin.md)). For Ollama, Xiaomi, Qoder and StepFun the value is a **session cookie** (`usesSessionCookie`), never labelled an API key.
- `keepsOwnCredential` — something is stored in `keys.dat`: the paste providers **plus Copilot**. Reading `usesAPIKey` here once left a signed-in Copilot asking to sign in again: the token was saved and never loaded.
- Extra-account OAuth and Cursor web logins live in `accounts.dat` ([authentication.md](authentication.md)).

Keys are read once per launch, not per refresh (`UsageStore.loadAPIKeys`).

### Source choice

Claude Code, Codex, Volcengine, Devin and Antigravity have `hasSourceChoice`, for primary accounts only (added accounts use their endpoint credential). `.automatic` is the default and each service owns its fallback, including Volcengine's preference for configured keys ([volcengine.md](volcengine.md)). A pinned route *reports* its failure instead of answering from elsewhere. **Every provider with more than one route offers the choice**, automatic by default. Antigravity's are *Automatic* (language server, then CLI), *CLI* (`.tooling`, the `agy` CLI) and *Desktop app* (`.desktopApp`, the editor's language server); it has no endpoint, so `.endpoint` is not offered (`UsageSource.options(for:)`, `title(for:)`).

- For Claude, `.desktopApp` is offered only on the **primary** Claude Code account; an added account must not be offered a route `fetchAdded` ignores. Likewise an added Grok account gets no CLI-login row: `fetchAdded` never touches `~/.grok/auth.json`.
- `Provider.soleRoute` is an exhaustive switch (as a ternary it once made Grok's pane read “Antigravity's language server”); nil draws no row. For Grok Bot it names **Cursor's** login, whose bill it is.

### Diagnostic route checks and repair

`UsageRoute` records the actual origin, separate from the `UsageSource` preference. Claude Code, Codex and Volcengine record chosen branches and preceding failures; single-route providers use `UsageRoute.soleRoute(for:)`; added accounts are always endpoint-backed, including renewal failures before the HTTP call. A route check covers credential eligibility and local-helper setup, so it does **not** claim a request was sent.

Claude's automatic route keeps an endpoint failure when a status-line capture answers. `ClaudeDesktopSession.attemptIfAlreadyPermitted` returns a failed result for diagnostics or a reading with an identity-compatibility flag; only a compatible live answer stops fallback. A desktop account mismatch is recorded as a discarded attempt without exposing the identity, and its figures never enter the cache. An unavailable or unpermitted desktop route is skipped without inventing a failed request. A missing status-line capture is recorded as not connected / awaiting response, even when the final message is about a CLI login.

`ConnectionRemedy` maps typed reasons to actions: added-account login failures reopen that slot's sign-in; Copilot uses its GitHub flow; key failures focus the credential field; Ollama rereads the selected browser; an unconnected status line offers installation; desktop/editor failures open the app (never silently restarting it); CLI login failures copy a command; transient failures offer Retry; unsupported replies and missing plans/tools open the setup page. Browser and sign-in operations keep their normal permissions and cancellation; shared text stays provider-neutral.

### Extra accounts

`supportsMultipleAccounts` is **Claude Code, Codex, Grok and Grok Bot**. Not Cursor: its usage is read from the editor's stored login, and a second account has no editor behind it (Grok Bot needs only the token). See [authentication.md](authentication.md), [`MonitoredAccount.swift`](../../Sources/Pulse/Usage/MonitoredAccount.swift).

A provider's first account id is its raw value, so stored preferences and cache files survive the upgrade; making an upgrade look like a fresh install has already cost a release.

### Transcripts, ledger, forecast

Shared counting, cache filename, burn rate and estimate: [`../refresh-and-data.md`](../refresh-and-data.md).

- `keepsLocalTranscripts` — Claude Code and Codex; gates the money estimate. OpenCode keeps sessions (`opencode stats`) in its own store, not the JSONL the ledger reads, so it is false.
- `supportsLocalActivity` — gates the activity mark. Also Kiro (Desktop/CLI/ACP session records) and ZCode (Desktop/native/ACP turn telemetry, attributed only when its endpoint identifies Zhipu or z.ai): lifecycle state without ledger token buckets.
- `providesHistory` — wider, and exactly `cardHistory != nil`: Z.ai and Zhipu from account statistics ([zai.md](zai.md)); OpenCode Go and DeepSeek from their consoles once a console sign-in is kept ([opencode-go.md](opencode-go.md), [deepseek.md](deepseek.md#the-console-usage-history-and-a-balance-without-a-key)); every provider whose mark a Token spend agent borrows (MiniMax Code for MiniMax, the Kimi CLI for Kimi Code, OpenCode's store before its console sign-in, and the rest listed in [../ui/panel-geometry.md](../ui/panel-geometry.md#detailed-card)), read only with Token spend on. Unsupported values are omitted, not zeroed.

Token-field differences (cache excluded vs included; per-turn vs running total): [claude-code.md](claude-code.md), [codex.md](codex.md).

## Service status

A provider with a status page Pulse can read gets a **Service status** group in its pane (`ServiceStatusGroup`) and, with **When a service is down** on, outage notifications ([../notifications.md](../notifications.md#a-service-outage-is-the-providers-word-about-its-service)). The catalogue is `StatusPage.of(_:minimaxSite:)` (`Providers/Status/StatusPage.swift`); one reader per platform beside it (`ServiceStatus+Statuspage`, `+IncidentIO`, `+Flashcat`, `+BetterStack`, `+Monitors`, `+Companies`).

- **A page is a feed and two rules.** The feed (`StatusFeed`) is the company's and is read once per check for every provider on it — Cursor and Grok Bot, Kimi Code and Moonshot, Codex and the OpenAI Platform. `shows` picks the provider's rows: by id where the page has stable ids, by group where rows come and go (Kimi Code's, a row per model), never other companies' rows a page mirrors (Factory's Models, Kilo's Service Provider, Amp's suppliers, JetBrains' AI Providers, Windsurf's Netlify). `notifies` narrows that to what the account runs on — the API or the agent, not the marketing site.
- **Bars only where the page publishes days.** Statuspage's uptime showcase, incident.io's impacts, Flashcat's payload, Better Stack's history, UptimeRobot's ratios and Google Cloud's incidents give days; OpenCode's are its page's: the last seven days in 56 three-hour slots aligned to UTC, at its proportions (seven wide, two apart) and in its colours, the feed's two and a half days of history filling the newest, labelled "7 days ago" to "Now" (`Day.hours`); Instatus, Upptime, Gatus, DeepInfra and IBM publish none Pulse can read, so those rows are the state now and no bars — never ninety green days nobody recorded. Zoom's page draws no bars for any row, and Cloudflare's answers the showcase with a 404. The uptime figure is the page's own, and left out where the page leaves it out (incident.io's `chart_only`).
- **Refresh, and why it failed.** The pane reads on opening, every five minutes while open, and on **Refresh** (beside **Open**; the rows shown stay until the answer comes). A read that fails says why under "Couldn't read the status page.": the HTTP status or the network error of the request that failed, or that the page answered without anything Pulse reads for the provider (`ResponseLog.capturing`, `ResponseLog.failure`).
- **Found, not guessed** (2026-10-15): every address is the provider's own or the one its `status.` address redirects to, and every page was read with the request Pulse makes. A row that disappears makes the pane say it couldn't read the page rather than show nothing.

| Provider | Page | Platform | Notified about |
|---|---|---|---|
| Claude Code | status.claude.com | Statuspage | Claude Code, Claude API |
| Cursor | status.cursor.com | Statuspage | IDE, CLI, Cloud Agents (Grok Bot's row is Grok Bot's) |
| Grok Bot | status.cursor.com | Statuspage | its row |
| Copilot | githubstatus.com | Statuspage | Copilot, Copilot AI Model Providers (shown alone) |
| Devin | devinstatus.com | Statuspage | Cloud Agent, Cloud Web Client |
| Windsurf | status.windsurf.com | Statuspage | Cascade, Windsurf Tab |
| Augment | status.augmentcode.com | Statuspage | API |
| Factory | status.factory.ai | Statuspage | api.factory.ai, CLI, Desktop |
| Kilo Code | status.kilo.ai | Statuspage | Kilo AI Gateway, Kilo Cloud Platform |
| MiniMax | status.minimax.io / status.minimaxi.com, by site | Statuspage | the LLM row |
| Kimi Code | status.moonshot.cn | Statuspage | the Kimi Code group |
| Moonshot | status.moonshot.cn | Statuspage | Open API, Open Platform Portal |
| Warp | status.warp.dev | Statuspage | agent harness, cloud agents, account services |
| Manus | status.manus.im | Statuspage | all |
| Venice | veniceai-status.com | Statuspage | Venice API |
| ZoomMate | zoomstatus.com | Statuspage, state only | its row |
| Replicate | cloudflarestatus.com | Statuspage, state only | its row |
| Codex | status.openai.com | incident.io | the Codex group |
| OpenAI Platform | status.openai.com | incident.io | the APIs group |
| JetBrains AI | status.jetbrains.cloud | incident.io | JetBrains AI |
| Amp | ampcodestatus.com | incident.io | Amp Agent, ampcode.com |
| AIXY | status.aixy-gateway.com | incident.io | API |
| ElevenLabs | status.elevenlabs.io | incident.io | the ElevenAPI group |
| Notion AI | notion-status.com | incident.io | the Notion AI group |
| Perplexity | status.perplexity.com | incident.io | API |
| Poe | status.poe.com | incident.io | all |
| v0 | v0-status.com | incident.io | Platform API, Website |
| DeepSeek | status.deepseek.com | Flashcat | rows named "API" |
| Hugging Face | status.huggingface.co | Better Stack | Hub, Spaces Proxy |
| Chutes | status.chutes.ai | Better Stack | API Heartbeat |
| Synthetic | status.synthetic.new | Better Stack (30 days) | the hosted models' section |
| DevPass | status.llmgateway.io | Better Stack | Gateway |
| Raycast AI | status.raycast.com | Better Stack | Raycast AI |
| TypeSafe | status.typesafe.ai | Better Stack | api.typesafe.ai |
| Zed | status.zed.dev | Instatus, state only | Agent, Edit Prediction |
| GitKraken | cloud.gitkrakenstatus.com | Instatus, state only | API Services, Identity Services |
| Atlas Cloud | atlascloud.instatus.com | Instatus, state only | all |
| Command Code | status.commandcode.ai | Upptime, state only | all |
| Cline Pass | status.cline.bot | Gatus, state only | all |
| Hyper | status.charm.sh | UptimeRobot | Hyper Prod (shown alone) |
| OpenCode Go | status.opencode.ai | its own, three-hour bars | Go |
| DeepInfra | status.deepinfra.com | its own, state only | API |
| IBM Bob | status.bob.ibm.com | its own, state only | Chat/Code Completion, Login/SSO |
| Gemini | status.cloud.google.com | Google Cloud incidents | Gemini Code Assist |

**Not here, and why:** xAI's (status.x.ai, for Grok and the xAI API) and Mistral's answer anything but a browser with a bot check; Volcengine's and xKiro's publish their state only inside the page's HTML; Alibaba Cloud's dashboard (Bailian, Qoder CN) marks a day with an event but not how bad it was; Kiro's is AWS's whole health dashboard; Antigravity and Qwen Cloud have no page of their own. Z.ai, GLM Coding, Ollama Cloud, Xiaomi MiMo, LongCat, Sakana, Codebuff, Neuralwatt, ZenMux, StepFun, Abacus, Nous Portal and T3 Chat have none; the self-hosted gateways (Sub2API, New API, LiteLLM and the rest) have nobody's.

## Adding a provider

**New providers are profiled.** Write a `ProviderProfile` in its own file, `Sources/Pulse/Providers/Profiled/<Name>UsageService.swift`, carrying name, icon, credential kind, access sentence, key subtitle, route, balance and pacing flags, colour, setup slug, discovery hints and fetch. Add the case to `Provider` and one line to `Provider.profile` in `Profiled/ProfiledProviders.swift` — nothing else. Every case-by-case switch switches over `Provider.HandWrittenProvider` via `provider.handWritten` (nil for a profiled provider, whose answer then comes from the switch's `guard`/`else`), so a profiled case has no arm to add. `UsageStore` asks every primary account, profiled or not, side by side in one task group. Reference: [`Profiled/ClinePassUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ClinePassUsageService.swift).

- **Credential kinds** are those the app already draws and guards: `.apiKey(optional:)`, `.sessionCookie(host:cookies:)` (read on request, kept to the named cookies), `.browserStorage(origin:keys:)` (a Chromium `localStorage` sign-in, kept to the named keys), `.keyAndAddress` (self-hosted; the key goes only to that address), `.localLogin` (a login the provider's own tool saved, read-only). Another kind is a shared change, not a profile field.
- **Failures** come from `ProfileHTTP`, so 401/403, 429 and 5xx mean the same for every provider. Use the provider-neutral reasons `sessionMissing`, `sessionExpired`, `localLoginMissing`, `localLoginExpired`, `localAppMissing` and `noPlan`, alongside the key, network and reply reasons.
- **Usage page.** If the provider has a page where a person views their own usage or billing, add one line to the table in `Providers/UsagePages.swift`; the menu bar's account tab links to it. A page only — not an API endpoint or a `Referer` — and none rather than a guess.
- **Lengths** a reply states go through `UsageWindow.length(_:unitSeconds:)`, never a bare multiplication: a count near `Int.max` decodes fine and an unchecked `*` traps, ending the app (Kimi, Z.ai, LiteLLM and JetBrains did; `DurationOverflowTests`). An unstated length — a month, a weekly limit with only a reset — is `reportsLength: false`.
- **Whole-bucket expiry**: opt into `expiresWholeBuckets` only when a full-remainder `nextExpiry` with no grouped `lots` gives the whole window's invalidation time. The shared cache then drops it at that time. Leave it off for pooled balances whose expiry describes only the earliest batch; see [cache rules](../refresh-and-data.md#cache).
- **Figures**: stated by the service, or a used amount over a limit the service states. Money left is `creditBalance` + `creditRemaining`. Spend with no limit and no balance has no place on screen yet, so it is left out.

**Hand-written providers** — the twenty-four written before profiles, plus `.pulseExtension` — are `Provider.HandWrittenProvider` and answer every switch themselves. A new one needs:

- `Provider` answers: `displayName`, `iconResource`, `keepsLocalTranscripts`, `supportsLocalActivity`, `providesHistory`, `hasSourceChoice` / `soleRoute`, `usesAPIKey` / `usesSessionCookie` / `keepsOwnCredential`, presence-only discovery, localized `monitoringAccessDescription`, `supportsMultipleAccounts`.
- A case in `Provider.HandWrittenProvider` itself (`UsageProvider.swift`).
- An SVG in `Sources/Pulse/Resources/`, and a service returning `ProviderUsage`.
- Branches in `UsageStore` refresh and `fetchAdded` if relevant. `AgentActivity` and `UsageLedger` return optional roots, so an agent with no transcripts opts out there.
- This directory updated in the same patch, and a user setup page in [`../setup/`](../setup/) under the slug `ConnectionRemedy.helpURL` gives it — the in-app **Setup help** link opens that page.

Do not document how to obtain someone else's auth tokens in issues or the repo. Do not paste session cookies, keys or page HTML into pull requests.
