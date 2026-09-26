# Providers

Pulse tracks **seventy-seven** built-in providers: twenty-five written case by case, and fifty-two described by a `ProviderProfile` (see [Adding a provider](#adding-a-provider) and [Profiled providers](#profiled-providers)). There is no Pulse backend and no Pulse account. Each provider reports its own usage by whatever route that product actually offers — often an undocumented account endpoint the product itself calls, sometimes a documented usage path, sometimes a local helper that only exists while an editor is open.

This directory is the home for routes, credentials, cookies, extra logins, and the failure lessons that belong to those. Current service code is authoritative. Historical measurements and “do not repeat” notes are labelled as such. Nothing here claims a runtime test of a live account.

This page is about **quota providers** — the seventy-seven cases Pulse can draw a ring for. Extensions — programs a user adds, each reporting one account — are carried by one more case, `.pulseExtension`, which `Provider.builtIn` leaves out; they have no route, credential or setup page here. Their contract is [`../extensions.md`](../extensions.md). Token spend readers are a different, overlapping catalogue of agents that left records on this Mac, most of which Pulse draws no ring for; they and their stores are documented in [`../token-spend.md`](../token-spend.md) and [`../token-spend-sources.md`](../token-spend-sources.md), not here. Do not add a spend reader to this directory.

Shared types: [`../../Sources/Pulse/Usage/UsageProvider.swift`](../../Sources/Pulse/Usage/UsageProvider.swift), [`../../Sources/Pulse/Usage/MonitoredAccount.swift`](../../Sources/Pulse/Usage/MonitoredAccount.swift), [`../../Sources/Pulse/Usage/ProviderUsage.swift`](../../Sources/Pulse/Usage/ProviderUsage.swift), [`../../Sources/Pulse/Usage/UsageSource.swift`](../../Sources/Pulse/Usage/UsageSource.swift). Sign-in machinery: [authentication.md](authentication.md).

Ollama setup (how to read the session, what the page parser accepts) stays in [`../ollama-cloud.md`](../ollama-cloud.md). Do not duplicate it here.

## Current matrix

Accounts the stored rail does not mention are appended **in name order**, not in declaration order — see `AppSettings.orderedAccounts`. Declaration order below is just how this table is written.

| `Provider` | Ring name | Icon | Credential | Extra accounts | Route choice | Local transcripts | First-run evidence |
|---|---|---|---|---|---|---|---|
| `.claudeCode` | Claude Code | `claude` | Borrow CLI login; Pulse OAuth for extras | yes | endpoint / desktop / status line | yes | `~/.claude`, Claude support directory, or `Claude.app` exists |
| `.codex` | Codex | `openai` | Borrow `~/.codex/auth.json`; Pulse OAuth for extras | yes | endpoint / app-server | yes | `~/.codex` exists |
| `.kiro` | Kiro | `kiro` | Borrow Kiro CLI login through ACP | no | native ACP | no | Kiro CLI data or app exists |
| `.antigravity` | Antigravity | `antigravity` | Loopback language server while the app is open | no | one, named | no | `Antigravity.app` |
| `.cursor` | Cursor | `cursor` | Cookie built from the editor’s stored token | no (deliberate) | one, named | no | Cursor `state.vscdb` exists |
| `.openCodeGo` | OpenCode Go | `opencode` | Pasted key, else OpenCode’s `auth.json` | no | pasted / found key | no | OpenCode `auth.json` exists |
| `.kimiCode` | Kimi Code | `kimi` | Pasted key | no | pasted key | no | none — stays off until switched on |
| `.ollamaCloud` | Ollama Cloud | `ollama` | Browser session cookie (not an API key) | no | session | no | none |
| `.zai` | z.ai | `zai` | Pasted key | no | pasted key | no | none |
| `.glmCoding` | Zhipu | `zai` | Pasted key, else mainland files | no | pasted / found key | no | mainland key file |
| `.minimax` | MiniMax | `minimax` | Pasted key | no | pasted key | no | none |
| `.minimaxCN` | MiniMax CN | `minimax` | Pasted key | no | pasted key | no | none |
| `.copilot` | GitHub Copilot | `github` | GitHub device login; token in `keys.dat` | no | sign-in | no | none |
| `.grok` | Grok | `grok` | Borrow `~/.grok/auth.json`; Pulse OAuth for extras | yes | one, named (primary) | no | `~/.grok` exists |
| `.grokBot` | Grok Bot | `xai` | Cursor cookie; Cursor web login for extras | yes | one, named (primary) | no | **standalone** `Grok Bot.app` only |
| `.volcengine` | Volcengine | `volcengine` | `arkcli`'s own login, else a pasted `AK:SK` pair | no | arkcli / signed endpoint | no | none — stays off until switched on |
| `.commandCode` | Command Code | `commandcode` | Pasted key, else `~/.commandcode/auth.json` | no | pasted / found key | no | `~/.commandcode/auth.json` exists |
| `.deepSeek` | DeepSeek | `deepseek` | Pasted key | no | one, documented | no | none |
| `.devin` | Devin | `devin` | Browser `localStorage` (no keychain); optional pasted `token org` | no | saved plan / endpoint | no | the app's `state.vscdb` exists |
| `.xiaomiMiMo` | Xiaomi Coding Plan | `xiaomimimo` | Browser session for `platform.xiaomimimo.com`, or a pasted `Cookie:` header | no | one, named | no | none |
| `.sub2api` | sub2api | `sub2api` | Pasted group key, **plus an address the reader types** | no | one, documented | no | none — stays off until switched on |
| `.newAPI` | New API | `newapi` | Pasted relay key, **plus an address the reader types** | no | one, documented | no | none — stays off until switched on |
| `.v2ex` | V2EX | `v2ex` | Pasted Personal Access Token | no | one, documented | no | none — stays off until switched on |
| `.qoder` | Qoder | `qoder` | Browser session for the chosen site (`qoder.com` / `qoder.com.cn`), or a pasted `Cookie:` header | no | one, the account page's own | no | `Application Support/Qoder` or `QoderCN`, or `Qoder.app` |
| `.stepFun` | StepFun | `stepfun` | Browser session for the chosen site (`platform.stepfun.com` / `platform.stepfun.ai`), or a pasted `Cookie:` header | no | one, the console's own | no | `~/.stepcode` (Step Code CLI) |

Per-provider pages: [claude-code.md](claude-code.md), [codex.md](codex.md), [kiro.md](kiro.md), [antigravity.md](antigravity.md), [cursor.md](cursor.md), [opencode-go.md](opencode-go.md), [kimi-code.md](kimi-code.md), [ollama-cloud.md](ollama-cloud.md), [zai.md](zai.md), [minimax.md](minimax.md), [copilot.md](copilot.md), [grok.md](grok.md), [grok-bot.md](grok-bot.md), [volcengine.md](volcengine.md), [command-code.md](command-code.md), [deepseek.md](deepseek.md), [devin.md](devin.md), [xiaomi-coding-plan.md](xiaomi-coding-plan.md), [sub2api.md](sub2api.md), [newapi.md](newapi.md), [v2ex.md](v2ex.md), [qoder.md](qoder.md), [stepfun.md](stepfun.md).

Ollama Cloud, Xiaomi Coding Plan, Qoder and StepFun are the four read from a **browser session** rather than a key or another tool's files; they share [`BrowserCookies.swift`](../../Sources/Pulse/Auth/BrowserCookies.swift) and nothing else, because what counts as a session differs per site and a shared filter would forward whichever cookie any one of them adds next. Qoder's filter is the one deny list among them, because its session cookie has no published name ([qoder.md](qoder.md)).

Z.ai and GLM Coding Plan share [`ZaiUsageService.swift`](../../Sources/Pulse/Providers/ZaiUsageService.swift). MiniMax and MiniMax CN share [`MiniMaxUsageService.swift`](../../Sources/Pulse/Providers/MiniMaxUsageService.swift). Two rings, two accounts, two keys — not a region switch inside one provider.

## Subscriptions and API accounts

`Provider.billing` sorts every provider into one of two kinds, which Settings and the chooser list apart: a **subscription** sells a plan with limits that turn over on a clock, and its figure is a percentage the provider states; an **API** account is money put in and drawn down by the call, with a balance or a spend and no allowance. A provider with both is filed under the one its buyers mostly pay for. Built-in cases answer in `Provider.billing` (DeepSeek, sub2api and New API are API); profiled ones set `billing` in their profile.

**Every API account's ring follows DeepSeek's three modes**, and so does an extension that reports a balance ([../extensions.md](../extensions.md#a-balance)) ([deepseek.md](deepseek.md#there-is-no-allowance-so-the-ring-has-no-denominator)): since top-up (a peak Pulse watched), a budget the reader typed, or the balance alone. `BalanceRing.applying` gives a live reading that is money and nothing else its one `.balance` window in the store, per account (`AppSettings.balanceBasis(for:)` / `balanceBudget(for:)`), with the watched peaks in `balance-baseline.json`, one per account and currency. A reading that already has limits of its own is left alone — those are the provider's figures — and its pane shows no basis rows, which would change nothing. **A balance ring never says spent:** a zero or negative balance is arithmetic, not the provider's word (Moonshot runs negative and keeps working; xAI's posted ledger can read zero with credit left), so it fills to 99% for alerts and no further. DeepSeek still makes its own ring in its service and keeps its own settings and file, from before the rule was everyone's; its settings pane rows (**Ring measures**, **Full tank**) are now every such account's.

## Profiled providers

Each is one file under `Sources/Pulse/Providers/Profiled/`, with its reply shape, what it leaves out and why in its own notes page, and a user setup page under the same slug in [`../setup/`](../setup/). **Every one of these shapes is second-hand**, read from CodexBar's providers and tests (MIT) and not from a live account; each page says so, and a captured reply replaces the fixture when someone with an account can produce one.

| `Provider` | Ring name | Credential | Money balance | Notes |
|---|---|---|---|---|
| `.clinePass` | ClinePass | pasted key |  | [clinepass.md](clinepass.md) |
| `.alibabaCodingPlan` | Alibaba Coding Plan | pasted key |  | [alibaba-coding-plan.md](alibaba-coding-plan.md) |
| `.alibabaTokenPlan` | Alibaba Token Plan | the tool's own login on this Mac |  | [alibaba-token-plan.md](alibaba-token-plan.md) |
| `.qwenCloud` | Qwen Cloud | browser session |  | [qwen-cloud.md](qwen-cloud.md) |
| `.factory` | Factory | pasted key |  | [factory.md](factory.md) |
| `.gemini` | Gemini | the tool's own login on this Mac |  | [gemini.md](gemini.md) |
| `.kiloCode` | Kilo Code | pasted key or the tool's own login | yes | [kilo-code.md](kilo-code.md) |
| `.augment` | Augment Code | browser session |  | [augment.md](augment.md) |
| `.jetBrainsAI` | JetBrains AI | the tool's own login on this Mac |  | [jetbrains-ai.md](jetbrains-ai.md) |
| `.t3Chat` | T3 Chat | browser session |  | [t3-chat.md](t3-chat.md) |
| `.synthetic` | Synthetic | pasted key |  | [synthetic.md](synthetic.md) |
| `.elevenLabs` | ElevenLabs | pasted key |  | [elevenlabs.md](elevenlabs.md) |
| `.warp` | Warp | pasted key |  | [warp.md](warp.md) |
| `.windsurf` | Windsurf | browser storage (Chromium) |  | [windsurf.md](windsurf.md) |
| `.bifrost` | Bifrost | key + your server address |  | [bifrost.md](bifrost.md) |
| `.chutes` | Chutes | pasted key |  | [chutes.md](chutes.md) |
| `.longCat` | LongCat | browser session |  | [longcat.md](longcat.md) |
| `.zoomMate` | ZoomMate | browser session |  | [zoommate.md](zoommate.md) |
| `.notionAI` | Notion AI | browser session |  | [notion-ai.md](notion-ai.md) |
| `.ibmBob` | IBM Bob | pasted key |  | [ibm-bob.md](ibm-bob.md) |
| `.nousPortal` | Nous Portal | the tool's own login on this Mac | yes | [nous-portal.md](nous-portal.md) |
| `.raycastAI` | Raycast AI | browser session |  | [raycast-ai.md](raycast-ai.md) |
| `.gitKraken` | GitKraken AI | pasted key |  | [gitkraken.md](gitkraken.md) |
| `.xKiro` | xKiro | pasted key | yes | [xkiro.md](xkiro.md) |
| `.abacus` | Abacus AI | browser session |  | [abacus.md](abacus.md) |
| `.moonshot` | Moonshot | pasted key | yes | [moonshot.md](moonshot.md) |
| `.hyper` | Hyper | pasted key |  | [hyper.md](hyper.md) |
| `.atlasCloud` | Atlas Cloud | pasted key | yes | [atlas-cloud.md](atlas-cloud.md) |
| `.poe` | Poe | pasted key |  | [poe.md](poe.md) |
| `.venice` | Venice | pasted key | yes | [venice.md](venice.md) |
| `.openAIPlatform` | OpenAI API | pasted key | yes | [openai-api.md](openai-api.md) |
| `.amp` | Amp | pasted key | yes | [amp.md](amp.md) |
| `.zed` | Zed | browser session |  | [zed.md](zed.md) |
| `.sakana` | Sakana AI | browser session | yes | [sakana.md](sakana.md) |
| `.mistral` | Mistral | browser session | yes | [mistral.md](mistral.md) |
| `.codebuff` | Codebuff | pasted key or the tool's own login |  | [codebuff.md](codebuff.md) |
| `.llmProxy` | LLM API Key Proxy | key + your server address |  | [llm-proxy.md](llm-proxy.md) |
| `.liteLLM` | LiteLLM | key + your server address |  | [litellm.md](litellm.md) |
| `.aixy` | Aixy | pasted key |  | [aixy.md](aixy.md) |
| `.neuralwatt` | Neuralwatt | pasted key | yes | [neuralwatt.md](neuralwatt.md) |
| `.clawRouter` | ClawRouter | pasted key |  | [clawrouter.md](clawrouter.md) |
| `.zenMux` | ZenMux | pasted key | yes | [zenmux.md](zenmux.md) |
| `.v0` | v0 | pasted key |  | [v0.md](v0.md) |
| `.devPass` | DevPass | pasted key |  | [devpass.md](devpass.md) |
| `.perplexity` | Perplexity | browser session | yes | [perplexity.md](perplexity.md) |
| `.manus` | Manus | browser session |  | [manus.md](manus.md) |
| `.huggingFace` | Hugging Face | pasted key or the tool's own login |  | [hugging-face.md](hugging-face.md) |
| `.deepInfra` | DeepInfra | pasted key | yes | [deepinfra.md](deepinfra.md) |
| `.xaiAPI` | xAI API | pasted key | yes | [xai-api.md](xai-api.md) |
| `.replicate` | Replicate | browser session | yes | [replicate.md](replicate.md) |
| `.typeSafe` | TypeSafe | browser session | yes | [typesafe.md](typesafe.md) |
| `.vercelAIGateway` | Vercel AI Gateway | pasted key | yes | [vercel-ai-gateway.md](vercel-ai-gateway.md) |

Left out, and why: Doubao, Kimi, MiMo, Ollama, z.ai and OpenCode are already here under other names; Azure OpenAI and AWS Bedrock cost money on every refresh (a real inference call; $0.01 per Cost Explorer call), and Muse mints an inference key to read its quota; Deepgram, CodeRabbit, Wayfinder and llmman report counts or health rather than an allowance or a balance; Pi and Vertex AI would be cost estimates from local logs; Fireworks, Groq and ai& report only spend, which Pulse has no place for yet; Helmcode needs a session cookie nobody has named and a site picker.

## Shared contracts

Refresh loop, cache algorithm, ledger, and forecast: [`../refresh-and-data.md`](../refresh-and-data.md). First-run / offer-once / empty rail: [`../architecture.md`](../architecture.md). This page keeps **provider-specific** differences.

### Pulse does not invent a percentage

If a provider does not report a figure, the UI says so. Do not derive a percentage from that provider’s local token counts. Labelled exceptions only, each withheld when its inputs cannot carry it: the money estimate ([`../refresh-and-data.md`](../refresh-and-data.md)), Command Code's monthly plan grant ([command-code.md](command-code.md)), and DeepSeek's ring ([deepseek.md](deepseek.md)) — which is the sharpest case, because DeepSeek reports a balance and no allowance whatsoever, so the denominator is either one Pulse watched, one the reader typed, or none at all.

The two self-hosted gateways are the same shape and are **not** exceptions: they report money with no ceiling behind it, so they draw no fraction at all and the rail shows the balance. sub2api's wallet groups report no allowance ([sub2api.md](sub2api.md)); New API reports one figure that *could* be divided by and whose meaning changes with a server setting the reply does not carry, so it is not ([newapi.md](newapi.md)). Generalising DeepSeek's three-way picker to them is the obvious next step if anyone asks for it, and has deliberately not been taken yet.

### Spent comes from the provider

A window’s `isExhausted` is the provider’s judgement (`severity` / `locked_reason`, `limit_reached`, a status other than `ok`, and so on), not “percentage ≥ 100”. A spend limit can run past 100%. An unrecognised severity is treated as spent — erring toward “you are blocked” is the safer mistake. Codex flags a whole *group*; the fullest window in that group is marked, not every sibling.

### Remaining vs spent

Downstream UI talks about what is **gone**. Services that receive “what is left” invert at the boundary: Antigravity, MiniMax, Copilot, and some Kimi `limits[].detail` fields. Grok Bot’s `usagePercent` is already spent, and so are Command Code’s spend limits and window limits — only its **credit balance** is what is left, and that is turned into a pool rather than inverted. Do not invert twice.

### `windowSeconds` is not evidence of a reported length

Some windows carry a length only so the row sorts: Kimi’s rolling week, Cursor’s 28–31 day billing cycle stored as 30, Copilot’s calendar month stored as 30, Grok Bot’s seven days when no reset is stated, sub2api’s quota and subscription periods, Qoder’s credits and team pool, StepFun’s Token Plan credits, V2EX’s top-up pack, and **V2EX’s five-hour window while it has not started** — that last one is the sharpest case, because the five hours are real and simply are not running yet ([v2ex.md](v2ex.md)). `UsageWindow.reportsLength` is the flag. The window-clock arc and the forecast divide only when the provider stated a length. Displaying a sort key as “7 days” on the card was a real bug (`UsageDetailCard.resetText` used to fall back to `lengthText` whenever `resetsAt` was nil).

### Four providers read a browser, from two different files

`usesSessionCookie` is Ollama, Xiaomi Coding Plan, Qoder and StepFun: a **cookie**, in SQLite, with its value encrypted under a key in the login keychain — so reading it raises a permission prompt, and Firefox and Safari are offered alongside the Chromium browsers. `readsBrowserStorage` also covers Devin: a **`localStorage`** entry, in a LevelDB, not encrypted — no prompt, and only Chromium browsers can be offered because nobody else keeps one ([devin.md](devin.md)). The reader is [`ChromiumLocalStorage`](../../Sources/Pulse/Auth/ChromiumLocalStorage.swift); it is the only place in Pulse that parses somebody else's binary format.

### Shared unavailability copy names no provider

`ProviderUsage.Unavailability` messages are reused. They originally all said “Codex”, so Claude Code reported “Codex is rate limiting these checks.” Shared cases (`.apiKeyMissing`, `.apiKeyRefused`, `.signedOut`, `.unreachable`, …) stay generic. Provider-specific cases exist where the *remedy* names a tool (`claudeLoginExpired`, `cursorSignInRequired`, `grokBotNotIncluded`, …). A Grok Bot primary that needs Cursor signed in is allowed to name Cursor: that is where the credential comes from.

There is no `.openCodeKeyRefused`. OpenCode Go uses `.apiKeyRefused` like the other key providers.

### Disabled providers are not fetched

A switched-off provider is not on the refresh pass. Its Settings pane does not preload credentials or history on appearance. After the initial choice, a deliberate refresh can still ask it by name while it is off. Shared loop: [`../refresh-and-data.md`](../refresh-and-data.md).

### First-run evidence (per provider)

Chooser, legacy restoration, offer-once and empty-rail rules: [`../architecture.md`](../architecture.md#provider-choice-before-monitoring).

`ProviderDiscovery.swift` checks only whether named files, directories or app bundles exist. It does not open a database, parse a key file, read browser storage or query Keychain. OpenCode Go, mainland GLM and Command Code therefore count as **detected even if their files are empty or unreadable**. Detection is a hint, not evidence of a valid account or a paid plan, and never enables a ring. Every provider appears in the initial chooser with its checkbox off.

`ProviderAccess.swift` supplies the descriptions shown before selection, also used above a disabled provider's Settings controls. Claude describes both CLI Keychain/file access and the desktop cookie-store grant; Codex names its auth file and helper; Kiro names its native ACP helper and states that credentials remain inside Kiro; Cursor and Grok Bot name Cursor's local database; Grok names its own auth file; Devin names Chromium web storage and the saved desktop plan, with no Keychain prompt. Ollama, Xiaomi and Qoder explain that browser sessions are imported from Settings and that importing can ask for browser Keychain access. The key-only providers describe the entered key, OpenCode/Zhipu/Command Code name their local fallbacks, Copilot names its Settings login, Volcengine names arkcli/access keys, and Antigravity names the local server and connection token.

### Seeded state is not “Loading…”

`UsageStore.initialState` does not seed every account as `.loading`. Providers that keep a credential start with a setup reason, without checking the credential store. The first selected fetch determines whether a saved login works. `loadAPIKeys` reads only enabled providers and rewrites placeholders, never readings already taken. The removed `canReportWithoutSetup` probe must not return here: seeding slots for unselected providers is not permission to read their keys.

### Cache (provider differences)

Shared drop/age/24h/cold-start rules: [`../refresh-and-data.md`](../refresh-and-data.md).

Do not paper over `.apiKeyMissing`, `.ollamaSessionMissing`, `.signedOut`, `.claudeDesktopNotSignedIn`, or `.claudeDesktopKeyRefused`. Claude Code’s status-line capture is marked `.live` for ten minutes (`freshFor`) even when an endpoint reading taken later exists — reconciliation is by `observedAt`, not by which route called itself live. See [claude-code.md](claude-code.md).

### Keys and logins Pulse keeps

Not the same question as “does Settings draw a paste field”.

- `usesAPIKey` — Settings paste UI: OpenCode Go, Kimi Code, Ollama Cloud, Z.ai, GLM Coding Plan, MiniMax, MiniMax CN, Volcengine, Command Code, DeepSeek, Devin, Xiaomi Coding Plan, sub2api, New API, V2EX, Qoder, StepFun. Volcengine’s, Command Code’s and Devin’s are **optional** — each has a route that needs nothing pasted. Devin’s field holds a token *and* an organization, whitespace-separated, and is only for a reader whose browser is not a Chromium ([devin.md](devin.md)). Ollama’s, Xiaomi’s and Qoder’s value is a **session cookie** (`usesSessionCookie`); calling it an API key in Settings would send people looking for one that does not exist.
- `keepsOwnCredential` — Pulse stores something in `keys.dat`: the paste providers **plus Copilot**. Reading `usesAPIKey` where *storage* was meant left a signed-in Copilot account reporting “sign in again”: the token was saved and then never loaded for the fetch.
- Extra-account OAuth / Cursor web logins live in `accounts.dat`, not `keys.dat`. See [authentication.md](authentication.md).

OpenCode Go’s file comment still says it is the only provider Pulse holds a key for. That is **stale**. Current `usesAPIKey` / `keepsOwnCredential` in `UsageProvider` win.

Keys are read once per launch rather than once per refresh (`UsageStore.loadAPIKeys`).

### Source choice

Claude Code, Codex, Volcengine and Devin have `hasSourceChoice`. The picker applies only to primary accounts; added accounts use their own endpoint credential. `.automatic` is the default; each service owns its fallback policy, including Volcengine's preference for configured keys ([volcengine.md](volcengine.md)). Pinning means a failure is *reported* rather than quietly answered from elsewhere.

`.desktopApp` is offered only on the **primary** Claude Code account. An added account’s picker must not offer a route `fetchAdded` would ignore.

`Provider.soleRoute` is an exhaustive switch. It used to be a ternary in Settings (Cursor’s wording, else Antigravity’s), so Grok’s pane read “Antigravity’s language server”. The row is not drawn when the answer is nil. For Grok Bot it names **Cursor’s** login, because that is whose bill it is.

An added Grok account is not shown the CLI-login row: `fetchAdded` never touches `~/.grok/auth.json`.

### Diagnostic route checks and repair

`UsageRoute` identifies actual origins separately from `UsageSource` preferences. Claude Code, Codex and Volcengine record their chosen branches and preceding failures. A route check includes credential eligibility and local-helper setup, so it does **not** claim that an HTTP request was sent. The single-route providers use `UsageRoute.soleRoute(for:)`. Added accounts are always endpoint-backed, including credential renewal failures before the HTTP call.

Claude's automatic route retains an endpoint failure when a status-line capture answers. `ClaudeDesktopSession.attemptIfAlreadyPermitted` returns a failed result for diagnostics, or a reading with an identity-compatibility flag; only a compatible live answer interrupts fallback. A desktop account mismatch is recorded as a discarded attempt without exposing its identity. An unavailable or unpermitted desktop route is skipped without inventing a failed request. Incompatible desktop figures never enter the cache. A missing status-line capture is recorded as not connected / awaiting response even when the final unavailable message explains a CLI login problem.

`ConnectionRemedy` maps typed reasons to actions: added-account login failures reopen that slot's sign-in; Copilot uses its existing GitHub flow; key failures focus the credential field; Ollama rereads the selected browser; an unconnected status line offers installation; desktop/editor failures open the relevant app; CLI login failures copy a command; transient failures offer Retry; unsupported response shapes and missing plans/tools open the provider's setup page. Opening an app does not silently restart it. Browser and sign-in operations retain their normal permissions and cancellation. Shared failure text remains provider-neutral.

### Extra accounts

`supportsMultipleAccounts` is **Claude Code, Codex, Grok, and Grok Bot** — not “the two CLIs”. Cursor itself is not on the list: the same web sign-in would work, but Cursor’s usage summary is read from the editor’s stored login and a second account has no editor behind it. Grok Bot needs nothing but the token. See [authentication.md](authentication.md) and [`MonitoredAccount.swift`](../../Sources/Pulse/Usage/MonitoredAccount.swift).

A provider’s first account id is the provider’s raw value. That is the migration: stored preferences and cache files keep matching. Making an upgrade look like a fresh install has already cost a release.

### Transcripts, ledger, forecast

Counting, cache filename, burn-rate, and estimate rules: [`../refresh-and-data.md`](../refresh-and-data.md).

Only Claude Code and Codex set `keepsLocalTranscripts`, which gates the labelled money estimate. The “working right now” mark is separately gated by `supportsLocalActivity`: Kiro Desktop/CLI/ACP session records and ZCode's Desktop/native/ACP turn telemetry can prove lifecycle state without supplying spend-ledger token buckets. ZCode activity is attributed only when its configured endpoint identifies Zhipu or z.ai. **History is the wider `providesHistory`**: Z.ai and Zhipu answer it from the account's own statistics instead ([zai.md](zai.md)). Unsupported values are left out rather than shown as zeroes. OpenCode *does* keep sessions (`opencode stats`); they live in OpenCode’s own store, not the JSONL the ledger reads, so the flag is false today.

Claude vs Codex token fields (exclude vs include cache; running total vs per-turn): [claude-code.md](claude-code.md), [codex.md](codex.md). Sort-key lengths (Kimi rolling week, Cursor/Copilot ~30-day stand-in, Grok Bot’s seven days without a stated reset) must keep `reportsLength: false` so they never feed the window clock or forecast.

## Adding a provider

**New providers are profiled.** Write the provider as a `ProviderProfile` in its own file, `Sources/Pulse/Providers/Profiled/<Name>UsageService.swift`. That profile carries the provider's name, icon, credential kind, access sentence, key subtitle, route, balance and pacing flags, colour, setup slug, discovery hints and fetch. Then add the case to `Provider` and one line to `Provider.profile` in `Profiled/ProfiledProviders.swift` — nothing else. Every switch that used to need a case-by-case answer for a profiled provider instead switches over `Provider.HandWrittenProvider`, reached through `provider.handWritten` (nil for a profiled provider, in which case the switch's `guard`/`else` answers for the profile instead); a profiled case is named in none of them, so there is no arm to add and no exhaustive switch to touch. `UsageStore` asks profiled providers side by side in one task group. [`Profiled/ClinePassUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ClinePassUsageService.swift) is the reference.

- **Credential kinds** are the ones the app already draws and guards: `.apiKey(optional:)`, `.sessionCookie(host:cookies:)` (read on request, kept to the named cookies), `.keyAndAddress` (self-hosted; the key goes only to that address), `.localLogin` (a login the provider's own tool saved, read-only). A kind that is not on this list is a shared change, not a profile field.
- **Failures** come from `ProfileHTTP`, so a 401/403, 429 and 5xx mean the same thing for every provider. Use the shared reasons that name no provider: `sessionMissing`, `sessionExpired`, `localLoginMissing`, `localLoginExpired`, `localAppMissing` and `noPlan`, alongside the key, network and reply reasons.
- **Figures** follow the same rule as everywhere else: stated by the service, or a used amount over a limit the service states. Money left is `creditBalance` + `creditRemaining`. Spend with no limit and no balance has no place on screen yet, so it is left out.

The twenty-five providers written before profiles, plus `.pulseExtension`, are `Provider.HandWrittenProvider` and answer every switch themselves. The rest of this section describes them. A non-profiled case needs: `Provider` answers (`displayName`, `iconResource`, `keepsLocalTranscripts`, `supportsLocalActivity`, `providesHistory`, `hasSourceChoice` / `soleRoute`, `usesAPIKey` / `usesSessionCookie` / `keepsOwnCredential`, presence-only discovery, localized `monitoringAccessDescription`, `supportsMultipleAccounts`), a case added to `Provider.HandWrittenProvider` itself (`UsageProvider.swift`), an SVG in `Sources/Pulse/Resources/`, a service returning `ProviderUsage`, branches in `UsageStore` refresh and `fetchAdded` if relevant, this directory updated in the same patch, and a user setup page in [`../setup/`](../setup/) under the slug `ConnectionRemedy.helpURL` gives it — the in-app **Setup help** link opens that page, not this directory. `AgentActivity` and `UsageLedger` already return optional roots, so an agent with no transcripts opts out there.

Do not document how to obtain someone else’s auth tokens in issues or the repo. Do not paste session cookies, keys, or page HTML into pull requests.
