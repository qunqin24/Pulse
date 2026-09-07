# Volcengine

Service: [`VolcengineUsageService.swift`](../../Sources/Pulse/VolcengineUsageService.swift). Signing: [`VolcengineSigner.swift`](../../Sources/Pulse/VolcengineSigner.swift).

The Ark Coding Plan, sold on Volcengine (火山引擎). Named for the platform rather than the model: Volcengine is the account, Ark (方舟) the model service on it, Doubao the model — and the account, the keys and the CLI are all Volcengine's. Naming the ring "Doubao" would name the one part of that chain it is not about.

## Not verified against a live account

**Nobody on this side holds an Ark coding plan.** Every shape below is second-hand — read out of CodexBar's parser and its tests (MIT) — rather than captured from a real reply. That is weaker evidence than any other provider in Pulse has behind it, and it is why:

- the parsing is pinned by fixtures (`Tests/PulseTests/Fixtures/volcengine-*.json`), so a schema change is a failing test rather than a wrong number;
- the signing is cross-checked against a second implementation of the scheme written in another language, because a wrong signature comes back as a bare 403 with nothing in it to debug;
- the failure copy names the exact command to run, since the first person to hit a problem will be someone Pulse cannot ask questions of.

**Replace the fixtures with a real capture** the first time somebody with an account can produce one, and delete this section when they have.

## Two routes

`hasSourceChoice` is true, so Settings offers a picker. (That property used to be `keepsLocalTranscripts`; the two happened to agree while only the CLIs had a choice. This provider is the reason they are separate.)

| Route | `UsageSource` | Credential |
|---|---|---|
| `arkcli` | `.tooling` | The login `arkcli auth login` already stored — nothing to paste |
| Volcengine Top OpenAPI | `.endpoint` | An access key pair, pasted |

**`.automatic` prefers the pasted keys over the CLI**, which is backwards from every other automatic in Pulse and deliberate. The reason is account identity, not reliability: `arkcli` carries an ambient SSO session that can be signed in to a *different* account than the keys, and quietly reporting the wrong account's limits is worse than either answer on its own. If you pasted keys, you meant those. A key that is refused says so rather than falling through — only an unreachable network drops to the CLI. (Rule and reasoning: CodexBar.)

### `arkcli`

`arkcli usage plan --format json`. Located by `ARKCLI_PATH`, then `PATH`, then `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` — a GUI app inherits almost no `PATH`, the same problem `CodexAppServer.locateCodex` solves.

Run with stdin at `/dev/null` so a CLI that decides to prompt gets EOF instead of blocking the refresh pass behind it — and with three guarantees that are enforced rather than merely commented, because a pass that never finishes never calls `scheduleNext` and the rail then freezes for **all fifteen** providers, not just this one:

- **Both pipes are drained at once.** Reading stdout to EOF and only then reading stderr deadlocks the moment the child writes more than a 64 KiB pipe buffer to stderr before closing stdout — a panic, a debug build, a TLS dump. The child blocks writing, Pulse blocks reading, neither returns.
- **Reading never stops early.** Past the 512 KiB ceiling the bytes are dropped but the pipe is still drained; a reader that walks away is the same deadlock wearing a different hat.
- **Every wait is bounded, and the kill escalates.** `Process.waitUntilExit()` has no timeout, so bounding only the readers moved the hang rather than removing it — a child that ignores SIGTERM, or one that closes its pipes and keeps running, sailed past the deadline and parked the call for ever. Exit is awaited through `terminationHandler` with a deadline; `terminate()` is a *request*, so SIGKILL follows if it is not honoured.
- **Reading is a `readabilityHandler`, not a blocking loop.** A loop parks a thread per pipe, and a grandchild inheriting the write end keeps it parked after the call has given up — a leak that repeats until libdispatch's per-QoS thread cap starves everything else. A handler holds no thread.
- **The whole thing on a global queue** rather than the cooperative pool: blocking work parked on a cooperative thread takes one of a core-width pool with it.

`VolcengineProcessTests` produces each failure for real: a child that floods stderr with 1 MiB, one that ignores SIGTERM, one that closes its pipes and keeps running, and one that leaves a grandchild holding the write ends.

```
{ "items": [ { "product": "coding-plan" | "agent-plan"
                        | "coding-plan-team" | "agent-plan-team",
               "subscribed": true,
               "updated_at": <epoch s or ms>,
               "periods": [ {"label": …, "percent": <used>, "reset_at": <ISO or epoch>} ],
               "error": "…" } ] }
```

Three things in that shape are traps, all of them recorded by CodexBar before this was written:

- **`updated_at` ships as both seconds and milliseconds** across versions. Told apart by magnitude at 1e11 — 1e11 seconds is the year 5138 and 1e11 milliseconds is 1973, so nothing real is near the boundary. `reset_at` gets the same treatment and may also be an ISO string.
- **A product bucket can fail on its own**, arriving with an `error` and no `periods`. It is skipped, not fatal: rejecting the reply would lose the plans that *did* answer.
- **`percent` is what is used**, not what is left. No inversion here, unlike [antigravity.md](antigravity.md).

A non-zero exit is classified from **stderr only, on whole phrases**. Matching `"auth"` as a substring reads `arkcli`'s own help text — where `auth` is a subcommand — as "not signed in", so a CLI too old or too new for `usage plan --format json` was answered with a remedy that succeeds and changes nothing, for ever.

### The signed API

Two independent actions, because an account can hold both plans:

- `GET https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01` → `Result.QuotaUsage[] {Level, Percent, ResetTimestamp}`
- `GET .../?Action=GetAFPUsage&Version=2024-01-01` → `Result {AFPFiveHour, AFPWeekly, AFPMonthly}`, each `{Quota, Used, ResetTime}`

They are asked concurrently and a refusal on **one** is not a refusal: an account without an Agent Plan must not lose its Coding Plan figures. Only both failing is reported. A reclaimed plan answers with a `Status` and no `QuotaUsage` at all — that is "nothing to report", not a malformed reply.

`AFPDaily` exists and is deliberately not mapped: there is no ring slot for it, and the arkcli path does not expose it either, so showing it on one route and not the other would make the picker change the answer.

A `Quota` of zero is a window the plan **has not got**, not a full one. Dividing by it reports 100% used of nothing.

### Signing

Volcengine's scheme is AWS SigV4 with two differences that each cost an afternoon:

- the credential scope terminator is `request`, not `aws4_request`, and the service is `ark`;
- the signed-header list is lower-cased and **sorted**, and the canonical request must list them in the same order — the server re-sorts and recomputes, so anything else is a 403 that says nothing.

`VolcengineSigner` returns headers rather than mutating a request, which is what lets it be tested on its own against a fixed clock and key. Percent-encoding is the signature's rules, not the URL's: everything outside the unreserved set, and `~` is **not** escaped — `addingPercentEncoding` with a stock character set gets both wrong.

The region is a constant (`cn-beijing`), not a setting. A wrong region fails as a signature mismatch, which is the least helpful thing a settings field could produce.

## The route that was left out

Ark returns `x-ratelimit-remaining-requests` on a chat completion, and CodexBar reads it as a third fallback. **Pulse cannot.** Reading that header means *sending a completion*, so every refresh would spend a piece of the quota it is measuring — every 2 to 30 minutes, for ever. And a request-rate throttle is not the coding plan's quota; it would put a number under the ring that answers a different question.

## Credential

One field holding a pair, split on the **first** colon: `AccessKeyID:SecretAccessKey`. A secret containing colons survives; splitting on the last would not. One field rather than two because `APIKeyStore`, the settings row and the "is it set" test are all built around one string per provider — and because it is optional anyway, `arkcli` needing nothing pasted.

`Provider.usesKeyPair` is what makes the row read "Access keys" rather than "API key", and what puts the format in the subtitle. A pair entered the wrong way round fails as a signature mismatch, so the format has to be on screen.

## Mapping

| Label | Window | `reportsLength` |
|---|---|---|
| `5h`, `5-hour`, `five_hour`, `session` | `.fiveHour`, 5h | true |
| `weekly`, `week` | `.weekly`, 7d | true |
| `monthly`, `month` | `.monthly`, 30d | **false** |

A month is 28 to 31 days, so 30 is a sort key and not a measurement — the window clock and the forecast must not divide by it. The same rule as Cursor's billing cycle; see [README.md](README.md).

A label not in that table is **left out rather than guessed at**, and so is a product this version has no name for: with four plans possible on one account, a window that cannot say which one it is about is worse than no window.

Ark reports no "you are blocked" flag, so `isExhausted` is its own figure reaching its own ceiling. That is the provider's number, not Pulse's inference.

## First run

Not offered. `canReportWithoutSetup` is false without a pasted key, so it waits in Settings like every other key provider — and `arkcli` being installed is not taken as evidence either, since the plan is a separate purchase from the CLI.
