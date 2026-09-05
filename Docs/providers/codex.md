# Codex

Service: [`CodexUsageService.swift`](../../Sources/Pulse/CodexUsageService.swift). App-server fallback: [`CodexAppServer.swift`](../../Sources/Pulse/CodexAppServer.swift). Extra accounts: [authentication.md](authentication.md).

`keepsLocalTranscripts` is true. Extra accounts are supported. Source choice: endpoint vs `codex app-server`.

## Routes (primary)

Default `.automatic`:

1. **HTTP usage endpoint** — read OAuth credentials Codex already stored in `~/.codex/auth.json`, then `GET https://chatgpt.com/backend-api/wham/usage` for account-wide windows plus any per-model limits. Nothing stays running. Works even when the `codex` command is not findable.
2. On missing or refused token (401/403): **`codex app-server`** — Codex’s own documented JSON-RPC protocol. It is signed in on its own terms so it renews credentials itself, and it pushes `account/rateLimits/updated`.
3. Cache, then an unavailable reason.

The HTTP endpoint is **not** a public documented usage API. It is what Codex’s own client calls and can change without notice. The stored token expires; Codex refreshes it while you use Codex, and nothing refreshes it for Pulse on the primary account.

Pinned `.endpoint` reports a dead token rather than falling through. Pinned `.tooling` never tries HTTP.

The two answers have **different field names** (`used_percent` / `limit_window_seconds` / `reset_at` versus `usedPercent` / `windowDurationMins` / `resetsAt`), hence two parsers.

## Windows

Never assume a fixed pair. `primary` / `secondary` are not tied to particular durations; which exist depends on the plan — ChatGPT Pro has no 5-hour limit at all, only the tiers below it do. A window’s kind is derived from its duration. The UI renders however many come back.

Codex reports `limit_reached` / `allowed` per group plus top-level `rate_limit_reached_type` and `spend_control.reached`. Those flags describe a whole group, which may hold both a 5-hour and a weekly window, so spent is pinned to the fullest window rather than smeared across both.

## Plan name

The plan comes back as an internal tier name, not the name on the plan — `prolite` is the 5× Pro tier. `CodexUsageService.planName` maps the ones we know and passes anything else through verbatim rather than blanking it.

## App-server / SIGPIPE / PATH

**SIGPIPE is ignored process-wide** (`AppDelegate`), and it has to be. Writing to a pipe whose far end has closed raises it; default is to kill the process. The helper exiting, being killed with the terminal it was started from, or the user quitting Codex took Pulse down with it (`Terminated due to signal 13`). Ignored, the write returns `EPIPE` and `CodexAppServer.write` drops the helper so the next call starts a fresh one.

**Historical evidence:** reproduced both ways against a process that had already exited — unguarded the probe was killed before it could print a line; guarded it reported “Broken pipe” and carried on.

Locating the executable cannot rely on `PATH`: a GUI app inherits almost none of it. `CodexAppServer.locateCodex` checks usual install locations, including versioned Node directories.

## Proxies

`URLSession` follows system proxy settings. On a machine behind a VPN that is what you want (the endpoint may only be reachable through it). A tunnel that stumbles surfaces as a Pulse error, typically `-1005 networkConnectionLost`; transient `URLError`s are retried a couple of times.

`URLSessionConfiguration.connectionProxyDictionary` is empty even when a proxy is in use — it means “use the system defaults”, not “no proxy”. Do not read an empty dictionary as evidence of a direct connection.

## Added accounts

`fetch(account:credentials:)` uses Pulse’s stored tokens. Extra-account sign-in is **device code**, not redirect. Full published scopes, including connector scopes that looked optional and were not. See [authentication.md](authentication.md).

Codex’s usage endpoint wants the account named in a header of its own; `AccountCredentials.accountID` is taken from the token.

Settings can also show the account’s real lifetime total from `account/usage/read`, which is **larger than anything on this Mac**. Without that row the local ledger total reads as simply wrong.

## Ledger

Codex’s `input_tokens` **includes** cached tokens; `cached_input_tokens` is the subset. Session usage is a **running total** — difference it, do not sum per-turn `last_token_usage` (measured 6% high on one long session). Shared ledger rules: [`../refresh-and-data.md`](../refresh-and-data.md).

## First run

Presence of `~/.codex`, never its contents.
