# Providers

Pulse tracks **seventeen** `Provider` cases. There is no Pulse backend and no Pulse account. Each provider reports its own usage by whatever route that product actually offers — often an undocumented account endpoint the product itself calls, sometimes a documented usage path, sometimes a local helper that only exists while an editor is open.

This directory is the home for routes, credentials, cookies, extra logins, and the failure lessons that belong to those. Current service code is authoritative. Historical measurements and “do not repeat” notes are labelled as such. Nothing here claims a runtime test of a live account.

Shared types: [`../../Sources/Pulse/Usage/UsageProvider.swift`](../../Sources/Pulse/Usage/UsageProvider.swift), [`../../Sources/Pulse/Usage/MonitoredAccount.swift`](../../Sources/Pulse/Usage/MonitoredAccount.swift), [`../../Sources/Pulse/Usage/ProviderUsage.swift`](../../Sources/Pulse/Usage/ProviderUsage.swift), [`../../Sources/Pulse/Usage/UsageSource.swift`](../../Sources/Pulse/Usage/UsageSource.swift). Sign-in machinery: [authentication.md](authentication.md).

Ollama setup (how to read the session, what the page parser accepts) stays in [`../ollama-cloud.md`](../ollama-cloud.md). Do not duplicate it here.

## Current matrix

Accounts the stored rail does not mention are appended **in name order**, not in declaration order — see `AppSettings.orderedAccounts`. Declaration order below is just how this table is written.

| `Provider` | Ring name | Icon | Credential | Extra accounts | Route choice | Local transcripts | First-run evidence |
|---|---|---|---|---|---|---|---|
| `.claudeCode` | Claude Code | `claude` | Borrow CLI login; Pulse OAuth for extras | yes | endpoint / desktop / status line | yes | `~/.claude` exists |
| `.codex` | Codex | `openai` | Borrow `~/.codex/auth.json`; Pulse OAuth for extras | yes | endpoint / app-server | yes | `~/.codex` exists |
| `.antigravity` | Antigravity | `antigravity` | Loopback language server while the app is open | no | one, named | no | `Antigravity.app` |
| `.cursor` | Cursor | `cursor` | Cookie built from the editor’s stored token | no (deliberate) | one, named | no | Cursor `state.vscdb` login |
| `.openCodeGo` | OpenCode Go | `opencode` | Pasted key, else OpenCode’s `auth.json` | no | pasted / found key | no | OpenCode stored key |
| `.kimiCode` | Kimi Code | `kimi` | Pasted key | no | pasted key | no | none — stays off until switched on |
| `.ollamaCloud` | Ollama Cloud | `ollama` | Browser session cookie (not an API key) | no | session | no | none |
| `.zai` | z.ai | `zai` | Pasted key | no | pasted key | no | none |
| `.glmCoding` | Zhipu | `qingyan` | Pasted key, else mainland files | no | pasted / found key | no | mainland key file |
| `.minimax` | MiniMax | `minimax` | Pasted key | no | pasted key | no | none |
| `.minimaxCN` | MiniMax CN | `minimax` | Pasted key | no | pasted key | no | none |
| `.copilot` | GitHub Copilot | `github` | GitHub device login; token in `keys.dat` | no | sign-in | no | none |
| `.grok` | Grok | `grok` | Borrow `~/.grok/auth.json`; Pulse OAuth for extras | yes | one, named (primary) | no | `~/.grok` exists |
| `.grokBot` | Grok Bot | `xai` | Cursor cookie; Cursor web login for extras | yes | one, named (primary) | no | **standalone** `Grok Bot.app` only |
| `.volcengine` | Volcengine | `volcengine` | `arkcli`'s own login, else a pasted `AK:SK` pair | no | arkcli / signed endpoint | no | none — stays off until switched on |
| `.commandCode` | Command Code | `commandcode` | Pasted key, else `~/.commandcode/auth.json` | no | pasted / found key | no | the CLI's stored key, **not** `~/.commandcode` |
| `.deepSeek` | DeepSeek | `deepseek` | Pasted key | no | one, documented | no | none — stays off until a key is entered |

Per-provider pages: [claude-code.md](claude-code.md), [codex.md](codex.md), [antigravity.md](antigravity.md), [cursor.md](cursor.md), [opencode-go.md](opencode-go.md), [kimi-code.md](kimi-code.md), [ollama-cloud.md](ollama-cloud.md), [zai.md](zai.md), [minimax.md](minimax.md), [copilot.md](copilot.md), [grok.md](grok.md), [grok-bot.md](grok-bot.md), [volcengine.md](volcengine.md), [command-code.md](command-code.md), [deepseek.md](deepseek.md).

Z.ai and GLM Coding Plan share [`ZaiUsageService.swift`](../../Sources/Pulse/Providers/ZaiUsageService.swift). MiniMax and MiniMax CN share [`MiniMaxUsageService.swift`](../../Sources/Pulse/Providers/MiniMaxUsageService.swift). Two rings, two accounts, two keys — not a region switch inside one provider.

## Shared contracts

Refresh loop, cache algorithm, ledger, and forecast: [`../refresh-and-data.md`](../refresh-and-data.md). First-run / offer-once / empty rail: [`../architecture.md`](../architecture.md). This page keeps **provider-specific** differences.

### Pulse does not invent a percentage

If a provider does not report a figure, the UI says so. Do not derive a percentage from that provider’s local token counts. Labelled exceptions only, each withheld when its inputs cannot carry it: the money estimate ([`../refresh-and-data.md`](../refresh-and-data.md)), Command Code's monthly plan grant ([command-code.md](command-code.md)), and DeepSeek's ring ([deepseek.md](deepseek.md)) — which is the sharpest case, because DeepSeek reports a balance and no allowance whatsoever, so the denominator is either one Pulse watched, one the reader typed, or none at all.

### Spent comes from the provider

A window’s `isExhausted` is the provider’s judgement (`severity` / `locked_reason`, `limit_reached`, a status other than `ok`, and so on), not “percentage ≥ 100”. A spend limit can run past 100%. An unrecognised severity is treated as spent — erring toward “you are blocked” is the safer mistake. Codex flags a whole *group*; the fullest window in that group is marked, not every sibling.

### Remaining vs spent

Downstream UI talks about what is **gone**. Services that receive “what is left” invert at the boundary: Antigravity, MiniMax, Copilot, and some Kimi `limits[].detail` fields. Grok Bot’s `usagePercent` is already spent, and so are Command Code’s spend limits and window limits — only its **credit balance** is what is left, and that is turned into a pool rather than inverted. Do not invert twice.

### `windowSeconds` is not evidence of a reported length

Some windows carry a length only so the row sorts: Kimi’s rolling week, Cursor’s 28–31 day billing cycle stored as 30, Copilot’s calendar month stored as 30, Grok Bot’s seven days when no reset is stated. `UsageWindow.reportsLength` is the flag. The window-clock arc and the forecast divide only when the provider stated a length. Displaying a sort key as “7 days” on the card was a real bug (`UsageDetailCard.resetText` used to fall back to `lengthText` whenever `resetsAt` was nil).

### Shared unavailability copy names no provider

`ProviderUsage.Unavailability` messages are reused. They originally all said “Codex”, so Claude Code reported “Codex is rate limiting these checks.” Shared cases (`.apiKeyMissing`, `.apiKeyRefused`, `.signedOut`, `.unreachable`, …) stay generic. Provider-specific cases exist where the *remedy* names a tool (`claudeLoginExpired`, `cursorSignInRequired`, `grokBotNotIncluded`, …). A Grok Bot primary that needs Cursor signed in is allowed to name Cursor: that is where the credential comes from.

There is no `.openCodeKeyRefused`. OpenCode Go uses `.apiKeyRefused` like the other key providers.

### Disabled providers are not fetched

A switched-off provider is not on the refresh pass. A provider’s own Settings pane can still refresh it by name while it is off. Shared loop: [`../refresh-and-data.md`](../refresh-and-data.md).

### First-run evidence (per provider)

Offer-once, `Key.hasRun` / `Key.offeredProviders`, empty-rail vs empty provider set: [`../architecture.md`](../architecture.md).

`canReportWithoutSetup` is not “needs no key”. Grok and Grok Bot borrow another tool’s login; with neither installed they would be switched on at the next update as grey rings saying “sign in to something you have never heard of”. Grok is gated on `~/.grok`; Grok Bot on the **standalone app**, not on a Cursor login (every Cursor user would otherwise get “your plan doesn’t include this”). OpenCode Go, mainland GLM and Command Code still count as ready when another tool already saved a key. Command Code’s test is that key, **not** `~/.commandcode`: the CLI creates that directory to unpack bundled skills into before anyone has signed in, so the directory says it ran here and nothing about whether there is an account behind it. The rest wait in Settings. They are still stamped as offered, so the decision is taken once.

### Seeded state is not “Loading…”

`UsageStore.initialState` does not seed every account as `.loading`. An account that needs a credential Pulse has not got never resolves while nothing is queued for it, and a Settings pane sat on “Reading…” indefinitely. It is seeded with the reason. `loadAPIKeys` rewrites that only over a placeholder, never over a reading actually taken.

### Cache (provider differences)

Shared drop/age/24h/cold-start rules: [`../refresh-and-data.md`](../refresh-and-data.md).

Do not paper over `.apiKeyMissing`, `.ollamaSessionMissing`, `.signedOut`, `.claudeDesktopNotSignedIn`, or `.claudeDesktopKeyRefused`. Claude Code’s status-line capture is marked `.live` for ten minutes (`freshFor`) even when an endpoint reading taken later exists — reconciliation is by `observedAt`, not by which route called itself live. See [claude-code.md](claude-code.md).

### Keys and logins Pulse keeps

Not the same question as “does Settings draw a paste field”.

- `usesAPIKey` — Settings paste UI: OpenCode Go, Kimi Code, Ollama Cloud, Z.ai, GLM Coding Plan, MiniMax, MiniMax CN, Volcengine, Command Code, DeepSeek. Ollama’s value is a **session cookie** (`usesSessionCookie`); calling it an API key in Settings would send people looking for one that does not exist.
- `keepsOwnCredential` — Pulse stores something in `keys.dat`: the paste providers **plus Copilot**. Reading `usesAPIKey` where *storage* was meant left a signed-in Copilot account reporting “sign in again”: the token was saved and then never loaded for the fetch.
- Extra-account OAuth / Cursor web logins live in `accounts.dat`, not `keys.dat`. See [authentication.md](authentication.md).

OpenCode Go’s file comment still says it is the only provider Pulse holds a key for. That is **stale**. Current `usesAPIKey` / `keepsOwnCredential` in `UsageProvider` win.

Keys are read once per launch rather than once per refresh (`UsageStore.loadAPIKeys`).

### Source choice

Claude Code, Codex and Volcengine have `hasSourceChoice`. The picker applies only to primary accounts; added accounts use their own endpoint credential. `.automatic` is the default; each service owns its fallback policy, including Volcengine's preference for configured keys ([volcengine.md](volcengine.md)). Pinning means a failure is *reported* rather than quietly answered from elsewhere.

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

Only Claude Code and Codex set `keepsLocalTranscripts`, which gates the labelled money estimate and the “working right now” mark. **History is the wider `providesHistory`**: Z.ai and Zhipu answer it from the account's own statistics instead ([zai.md](zai.md)). Both are left out for everyone else rather than shown as zeroes. OpenCode *does* keep sessions (`opencode stats`); they live in OpenCode’s own store, not the JSONL the ledger reads, so the flag is false today.

Claude vs Codex token fields (exclude vs include cache; running total vs per-turn): [claude-code.md](claude-code.md), [codex.md](codex.md). Sort-key lengths (Kimi rolling week, Cursor/Copilot ~30-day stand-in, Grok Bot’s seven days without a stated reset) must keep `reportsLength: false` so they never feed the window clock or forecast.

## Adding a provider

A new case needs: `Provider` answers (`displayName`, `iconResource`, `keepsLocalTranscripts`, `providesHistory`, `hasSourceChoice` / `soleRoute`, `usesAPIKey` / `usesSessionCookie` / `keepsOwnCredential`, `canReportWithoutSetup` / first-run evidence, `supportsMultipleAccounts`), an SVG in `Sources/Pulse/Resources/`, a service returning `ProviderUsage`, branches in `UsageStore` refresh and `fetchAdded` if relevant, and this directory updated in the same patch. `AgentActivity` and `UsageLedger` already return optional roots, so an agent with no transcripts opts out there.

Do not document how to obtain someone else’s auth tokens in issues or the repo. Do not paste session cookies, keys, or page HTML into pull requests.
