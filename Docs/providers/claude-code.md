# Claude Code

Primary service: [`ClaudeCodeUsageService.swift`](../../Sources/Pulse/ClaudeCodeUsageService.swift). Desktop route: [`ClaudeDesktopSession.swift`](../../Sources/Pulse/ClaudeDesktopSession.swift). Status line: [`StatusLineHook.swift`](../../Sources/Pulse/StatusLineHook.swift). Identity compare: [`ClaudeAccountIdentity.swift`](../../Sources/Pulse/ClaudeAccountIdentity.swift). Extra accounts: [authentication.md](authentication.md). Compact fallback diagram: [`../plan.md`](../plan.md).

`keepsLocalTranscripts` is true. Extra accounts are supported. Source choice applies to the **primary** account only.

## Routes (primary)

Default `.automatic`, in this order:

1. **Usage endpoint** — `GET https://api.anthropic.com/api/oauth/usage` with the OAuth access token Claude Code already stored (Keychain service `Claude Code-credentials`, falling back to `~/.claude/.credentials.json`).
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

The usage endpoint is **not** a public documented usage API. It is what Claude Code itself calls and can change without notice. Parse the response’s `limits` array rather than the top-level `five_hour` / `seven_day` fields — only the array carries per-model `weekly_scoped` windows. `kind` maps the window (`session` is the 5-hour one); `scope.model.display_name` names the model.

The saved CLI token expires in hours and **nothing here renews it**. An unusable token (401/403) or a missing one falls through as above. Added accounts never use these fallbacks.

## Plan name

`GET /api/oauth/profile` — the usage reply does not carry a plan, which is why this provider once showed no plan while every other one did. Prefer `subscription_type`; otherwise `organization.rate_limit_tier`, where the **multiplier** lives (`default_claude_max_5x` → “Max 5x”). Unfamiliar values are tidied and passed through, not blanked.

Only plan-shaped fields are read. The same reply carries name, email, organisation identifiers — the user’s, no use to Pulse. Cached for six hours; a failure is cached too so the plan can never cost the usage reading a retry every pass. The same reply seeds `ClaudeAccountIdentity` with a fingerprint of whoever this token belongs to, because by the time the desktop route needs that question the CLI token has usually expired.

## Status line

Documented at Claude Code’s status-line docs. Claude Code pipes a blob carrying `rate_limits.five_hour` / `.seven_day` to the registered command. It is a **push, not a pull**: figures only refresh while a session runs. A capture older than ten minutes (`freshFor`) reads `.stale` with an “as of” line. It carries no per-model windows.

**A window whose reset time has passed is dropped here too, not aged.** This route is a push. A Mac that has not run Claude Code since yesterday is still holding yesterday’s blob; any five-hour window in it reset long ago. Shown with “as of” it still reads as a limit you are inside. Once every window has gone, `capturedUsage` returns nil and the caller says it is waiting on Claude Code. `UsageCache` had this rule from the start; this is the *other* place an old reading can come from and it went without — a reset 28 hours in the past reached the card. Found because the window-clock arc drew a full circle: 9% used looked plausible, a spent clock on a five-hour window did not.

The hook edits `~/.claude/settings.json`. It backs the file up to `settings.json.pulse-backup` on first touch, remembers any status-line command that was already there so it can chain and restore, and rewrites its own path on launch (`repairPathIfNeeded`) because rebuilding moves the executable.

## Desktop app route

The desktop app runs the same `claude` binary but hands it a token through its own environment and renews that token itself. It never writes the Keychain item the endpoint route reads, and there is no terminal to push a status line.

**Historical evidence (one Mac, one day, driven entirely through the desktop app):** the Keychain item and the status-line blob were both frozen at the same minute — the last time `claude` had been run in a terminal — while transcripts went on being written every few minutes. Both other routes were quietly answering with yesterday’s figures, and the cache made that look like a refresh button doing nothing.

What it borrows: the Electron app’s Chromium cookie store and `Safe Storage` key. Only `claude.ai`’s `sessionKey` / `sessionKeyV3` are read. Organisation is `lastActiveOrg`, not the first org the account belongs to — one account can sit in more than one organisation with different limits.

Web client paths (not public API): `/api/bootstrap` and `/api/organizations/{id}/usage`.

**Only a live reading interrupts the automatic chain.** A signed-out session or a refusal leaves the older routes their turn — between a live nothing and a dated something, the dated something is what the panel is for.

**The two apps can be signed in as different people.** `ClaudeAccountIdentity` compares this session’s account/organisation/email against whatever the CLI token last said (captured in passing by the profile call). A comparison with nothing on one side is **not** a mismatch: someone who has only ever used the desktop app may never have had a working CLI token, and refusing the route until one appeared would withhold it from exactly the person it exists for. A pinned `.desktopApp` skips the comparison.

At launch, if Claude Code is enabled and its source is Automatic or Desktop App, Pulse may request `Claude Safe Storage` once when a desktop cookie store exists. Automatic refreshes do not raise a new unsolicited Keychain prompt each pass.

## Added accounts

`fetch(account:token:)` goes straight over HTTP with the token Pulse holds. Status-line capture and the desktop session belong to whichever account the CLI or desktop app is signed in to, which for an added account is not this one. `UsageSource.options(for:)` leaves `.desktopApp` off an added account’s picker.

OAuth scopes and loopback behaviour: [authentication.md](authentication.md).

## Spent

Claude Code reports `severity` and `locked_reason` per limit. Unrecognised severity is treated as spent.

## First run

Presence of `~/.claude`, never its contents.
