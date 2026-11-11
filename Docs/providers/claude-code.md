# Claude Code

Primary service: [`ClaudeCodeUsageService.swift`](../../Sources/Pulse/Providers/ClaudeCodeUsageService.swift). Desktop route: [`ClaudeDesktopSession.swift`](../../Sources/Pulse/Providers/ClaudeDesktopSession.swift). Status line: [`StatusLineHook.swift`](../../Sources/Pulse/App/StatusLineHook.swift). Identity compare: [`ClaudeAccountIdentity.swift`](../../Sources/Pulse/Providers/ClaudeAccountIdentity.swift). Extra accounts: [authentication.md](authentication.md).

`keepsLocalTranscripts` is true. Extra accounts are supported. Source choice applies to the **primary** account only.

## Routes (primary)

Default `.automatic`, in this order:

1. **Usage endpoint** — `GET https://api.anthropic.com/api/oauth/usage` with the OAuth access token Claude Code already stored (Keychain service `Claude Code-credentials`, falling back to `~/.claude/.credentials.json`). The Keychain read is `security find-generic-password` through `BoundedProcess`, ended after 60 seconds (`keychainDeadline`): an access prompt nobody answers falls through to the file and the status line instead of holding every provider's pass behind it, and the Keychain is then left alone for 30 minutes (`keychainPause`) so the unanswered prompt is not put up again at every pass.
2. **Desktop session** — only if the Keychain grant for `Claude Safe Storage` has already happened, the session returns a **live** reading, and account identity is compatible (or there is nothing to compare). See [authentication.md](authentication.md).
3. **Status line capture** — Claude Code’s documented status-line hook. Pulse registers as `Pulse --statusline`, banks the blob, prints a status line back.
4. **Cache**, then an actionable unavailable reason.

Shorthand:

```text
OAuth -> permitted live Desktop session -> Status Line -> valid cache -> error
```

**OAuth network, rate-limit, or server failure currently skips Desktop** and goes to Status Line, then cache:

```text
OAuth network failure -> Status Line -> valid cache -> error
```

Reasoning: a network stumble should not hide a perfectly good captured reading. The error is kept in reserve for when nothing was captured either.

Pinned `.endpoint` / `.tooling` / `.desktopApp` disable the normal cross-source fallback. Cache reconciliation still runs afterwards where its rules allow.

The usage endpoint is **not** a public documented usage API. It is what Claude Code itself calls and can change without notice. Parse the response’s `limits` array rather than the top-level `five_hour` / `seven_day` fields — only the array carries per-model `weekly_scoped` windows. `kind` maps the window (`session` is the 5-hour one); `scope.model.display_name` names the model. The same reply's `seven_day_breakdown.rows` (this week's split by product) draws no ring; for the CLI's own login it is kept for Token spend's all-products estimate ([token-spend.md](../token-spend.md#every-claude-product-estimated)).

The saved CLI token expires in hours and **nothing here renews it**. An unusable token (401/403) or a missing one falls through as above. Added accounts never use these fallbacks.

## Plan name

`GET /api/oauth/profile` — the usage reply does not carry a plan, which is why this provider once showed no plan while every other one did. Prefer `subscription_type`; otherwise `organization.rate_limit_tier`, where the **multiplier** lives (`default_claude_max_5x` → “Max 5x”). Unfamiliar values are tidied and passed through, not blanked.

Only plan-shaped fields are read. The same reply carries name, email, organisation identifiers — the user’s, no use to Pulse. Cached for six hours; a failure is cached too so the plan can never cost the usage reading a retry every pass. The same reply seeds `ClaudeAccountIdentity` with a fingerprint of whoever this token belongs to, because by the time the desktop route needs that question the CLI token has usually expired.

## Status line

Documented at Claude Code’s status-line docs. Claude Code pipes a blob carrying `rate_limits.five_hour` / `.seven_day` to the registered command. It is a **push, not a pull**: figures only refresh while a session runs. A capture older than ten minutes (`freshFor`) reads `.stale` with an “as of” line. It carries no per-model windows.

**A window whose reset time has passed is dropped here too, not aged.** This route is a push. A Mac that has not run Claude Code since yesterday is still holding yesterday’s blob; any five-hour window in it reset long ago. Shown with “as of” it still reads as a limit you are inside. Once every window has gone, `capturedUsage` returns nil and the caller says it is waiting on Claude Code. `UsageCache` had this rule from the start; this is the *other* place an old reading can come from and it went without — a reset 28 hours in the past reached the card. Found because the window-clock arc drew a full circle: 9% used looked plausible, a spent clock on a five-hour window did not.

The hook edits `~/.claude/settings.json`. It backs the file up to `settings.json.pulse-backup` on first touch, remembers any status-line command that was already there so it can chain and restore, and rewrites its own path (`repairPathIfNeeded`) because rebuilding moves the executable. Both automatic path repair and the one-time connection offer wait until the primary Claude Code account is enabled.

## Desktop app route

The desktop app runs the same `claude` binary but hands it a token through its own environment and renews that token itself. It never writes the Keychain item the endpoint route reads, and there is no terminal to push a status line.

**Historical evidence (one Mac, one day, driven entirely through the desktop app):** the Keychain item and the status-line blob were both frozen at the same minute — the last time `claude` had been run in a terminal — while transcripts went on being written every few minutes. Both other routes were quietly answering with yesterday’s figures, and the cache made that look like a refresh button doing nothing.

What it borrows: the Electron app’s Chromium cookie store and `Safe Storage` key. Only `claude.ai`’s `sessionKey` / `sessionKeyV3` are read. Organisation is `lastActiveOrg`, not the first org the account belongs to — one account can sit in more than one organisation with different limits.

Web client paths (not public API): `/api/bootstrap` and `/api/organizations/{id}/usage`.

**Only a live reading interrupts the automatic chain.** A signed-out session or a refusal leaves the older routes their turn — between a live nothing and a dated something, the dated something is what the panel is for.

**The two apps can be signed in as different people.** `ClaudeAccountIdentity` compares this session’s account/organisation/email against whatever the CLI token last said (captured in passing by the profile call). A comparison with nothing on one side is **not** a mismatch: someone who has only ever used the desktop app may never have had a working CLI token, and refusing the route until one appeared would withhold it from exactly the person it exists for. A pinned `.desktopApp` skips the comparison.

After provider selection (or at launch for an existing enabled choice), if Claude Code's source is Automatic or Desktop App, Pulse may request `Claude Safe Storage` once when a desktop cookie store exists. Enabling Claude later in Settings also reaches this path. The chooser describes that grant before it is requested. Automatic refreshes do not raise a new unsolicited Keychain prompt each pass.

## Added accounts

`fetch(account:token:)` goes straight over HTTP with the token Pulse holds. Status-line capture and the desktop session belong to whichever account the CLI or desktop app is signed in to, which for an added account is not this one. `UsageSource.options(for:)` leaves `.desktopApp` off an added account’s picker.

OAuth scopes and loopback behaviour: [authentication.md](authentication.md).

Route-check diagnostics preserve fallback outcomes without changing which account may answer; the shared diagnostic and repair contract is in [README.md](README.md#diagnostic-route-checks-and-repair).

## Spent

Claude Code reports `severity` and `locked_reason` per limit. A `locked_reason` is spent; so is any severity Pulse does not recognise. `normal`/`ok`/`none`/`healthy` and **`warning`/`warn`** are not — Claude Code raises a limit to `warning` while it still has room (seen at 76% used on a scoped weekly limit), and treating that as spent drew a full exhausted-red ring and a red figure for a limit with a quarter left. Spent is what the provider actually reports, not what it is worried about.

## Service status

Settings › Claude Code › **Service status** (`ServiceStatus`, `ServiceStatusGroup`, `StatusPage.of(.claudeCode)`): **every component status.claude.com shows** — claude.ai, Claude Console, Claude API, Claude Code, Claude Cowork, Claude for Government as of 2026-10-04 — each with the state now, a bar a day for 90 days and the page's 90-day uptime, then a row that opens the page. Requested 2026-10-04 with a screenshot of that page; the layout copies it. It first showed only Claude Code and the API; the request was for all of them. Codex's twin, and the rules both share (read on opening and every five minutes while open; no reading is not all clear): [codex.md](codex.md#service-status).

**Components as the page shows them.** `/api/v2/summary.json` → `components[]`, in `position` order, a group's own row (`group: true`) left out and one marked `only_show_if_degraded` left out while operational. The outage notification is narrower: Claude Code and Claude API only, by id (`yyzkbfz2thpt`, `k8w3r06qmzrp`) — [../notifications.md](../notifications.md).

**History: `/uptime_showcase?components=<ids>`**, the request the page makes to fill its bars lazily (found in its script, 2026-10-04), asked after the summary because it says which ids there are; the page batches up to 60. Per component: `timelines[id].days[]` (`date` as `yyyy-MM-dd` in the page's time zone, `outages.p` / `outages.m` in seconds of partial and major outage), `timelines[id].component.startDate`, `values[]` (`ninety` is the figure the page prints — 99.44 and 99.52 that day, matching it), and `components[id]`, the SVG of the bars. **Each bar takes the colour the page drew** (`fill` of each `uptime-day` rect), because the page grades a day green → yellow → red by how long it was out, which no state carries; only when there is a colour for every day, otherwise the state's colour. The state of a day is `m > 0` full outage, `p > 0` partial, else operational; before `startDate` none. On the captured days, green fell exactly on the days with no outage (`ServiceStatusTests`).

**Colours are the page's theme**: operational `#76AD2A`, degraded `#FAA72A`, partial `#E86235`, major `#E04343`, maintenance `#2C84DB`; square bars.

## First run

Presence of `~/.claude`, the Claude Application Support directory, or `Claude.app` in `/Applications` or `~/Applications`, never their contents. These only mark the chooser row as detected. CLI credential reads, the desktop Keychain request and the status-line offer all wait for selection.
