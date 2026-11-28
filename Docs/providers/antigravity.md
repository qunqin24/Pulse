# Antigravity

Service: [`AntigravityUsageService.swift`](../../Sources/Pulse/Providers/AntigravityUsageService.swift), with the CLI route in [`AntigravityCLIUsage.swift`](../../Sources/Pulse/Providers/AntigravityCLIUsage.swift).

Two routes, chosen in Settings → *Read usage from*: **Automatic** (the default) tries the editor's **language server** while Antigravity is open, then the **`agy` CLI** when the server produced no figures; **CLI** asks only `agy`; **Desktop app** asks only the language server. The route that answered is recorded as `languageServer` or `antigravityCLI`.

The odd one out. Extra accounts are not supported, and cannot be without breaking Antigravity's terms (see [below](#the-oauth-route-is-off-limits)). `keepsLocalTranscripts` is false: it leaves no session files the history card can read, so history and the money estimate are left out rather than shown as zeroes. The activity mark is drawn from its conversation databases ([below](#activity-mark)).

## The language server

Antigravity starts a `language_server` of its own and talks to it over HTTPS on loopback. On this route **the figures exist only while something of Antigravity’s is running** — `.antigravityNotRunning` says that plainly rather than dressing it up as a failure. With Antigravity closed, the `agy` CLI is asked instead when it is installed (below).

Three things are discovered and **none may be assumed**:

1. The process — inside an app bundle, not on `PATH`, matched on the **bundle path** because `language_server` is Codeium’s binary and its other editors ship the same one.
2. The port — started with `--https_server_port 0` (“take any free one”), so it differs every launch.
3. A per-launch CSRF token, sent as `x-codeium-csrf-token`. Older builds pass it on the command line as `--csrf_token`. **Antigravity 2.34 passes it in the environment instead**, as `ANTIGRAVITY_SERVER_CSRF_TOKEN` (measured 2026-11-22 with Antigravity.app 2.34.0: no `--csrf_token` in argv, the variable present). When the flag is absent, the token is read from the process's `KERN_PROCARGS2` record (its arguments and environment, readable for the user's own processes); only that variable is taken. Without either, the process is skipped, which is what froze the ring at its last reading on 2.34 (#116).

RPC: `exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`, POST `{}`.

The server signs its own certificate. `LoopbackTrust` accepts it — **only for `127.0.0.1`**. Anything else is refused exactly as it would be anywhere else in the app.

### Two origins, several processes

`Origin` is the preference order: `Antigravity.app`, then `Antigravity IDE.app`. `/Antigravity.app/` does not match `/Antigravity IDE.app/` — the space separates them, which is why both fragments are written with their slashes. The IDE’s copy is named `language_server_macos_arm`; it still contains `/language_server`, so the name test holds for both.

**Every candidate is tried, and every port each listens on.** Taking the first match and giving up was a real fault: measured with only the IDE open, it runs *two* language servers and the one that answers was second — the other returns **401 to this RPC**, which is that process saying “not me”, not the account being refused. So `.refused` is worth no more than a closed port here and the search continues — and so is an undecodable 200, or the first odd body ends the search and the server that would have answered is never asked. An answer with no limits in it is held rather than returned, because that is also what a wrong server says; it is only reported as `.noLimitsReported` if nothing better turns up.

**What is reported when nothing answered matters too.** A server that refused is still Antigravity *running*. Reporting `.unreachable` there says the app is not there while it is — and the notification rules count `.unreachable` as a fault while `.antigravityNotRunning` is not, so the multi-origin search briefly turned "Antigravity is being unhelpful" into a banner about an app that was open. `fetch` tracks whether anything answered at all and picks between `.antigravityNotAnswering` and `.antigravityNotRunning`.

**The reason has to be one the classification actually spares.** The first attempt at this said `.unreadableReply`, which sits in `AlertMemory.isFailure` right beside `.unreachable` — so the banner it was written to stop went on firing. `.antigravityNotAnswering` exists because "Open Antigravity" is false advice when it is already open, and because a fault the user can only wait out is not one to be told about on a timer.

### What the IDE actually serves (measured 2026-09-06)

CodexBar’s notes say the IDE’s local endpoints expose only session/model quota data and not the weekly grouping. **Not what this Mac reports.** With `Antigravity.app` closed and only `Antigravity IDE.app` open, `RetrieveUserQuotaSummary` returned the full payload — both groups, weekly and five-hour buckets, real reset times:

| bucket | scope | window | remainingFraction |
|---|---|---|---|
| `gemini-5h` | Gemini Models | 5h | 1 |
| `gemini-weekly` | Gemini Models | weekly | 0.9949068 |
| `3p-5h` | Claude and GPT models | 5h | 1 |
| `3p-weekly` | Claude and GPT models | weekly | 1 |

That payload is committed as `Tests/PulseTests/Fixtures/antigravity-quota.json` and is what `AntigravityParsingTests` holds the parser against. `GetUserStatus` on the same port named the plan (`Pro`). Their note may be about an older IDE build; either way, do not drop the IDE origin on the strength of it without re-measuring.

## The `agy` CLI

Google's standalone CLI, `agy` (installed to `~/.local/bin/agy`; state under `~/.gemini/antigravity-cli`), is the second route. **Gemini.app carries the same CLI** and runs no language server of its own, so for someone using Antigravity inside Gemini.app this CLI is the only route there is (#106, measured with Gemini.app 1.138 on 2026-11-05). It ships inside the app as `Gemini.app/Contents/Helpers/agy`, and the app's updater installs a current copy to `~/.gemini/bin/agy` (with `agy.version.json` beside it) — but only once it has run, so a Mac with Gemini.app may have the bundled copy alone (#129; measured 2026-11-27 with Gemini.app 1.147: the bundled agy was 1.5.5, `~/.gemini/bin` held 1.5.10, both answered `/usage`). After the usual install locations, `locateCLI()` tries `~/.gemini/bin/agy`, then the bundled copy, finding the app by its bundle id `com.google.GeminiMacOS` and falling back to `/Applications/Gemini.app`. It works with no editor open, using the login the CLI saved. Pulse starts the program and reads its standard output; it never reads the CLI's credentials.

### What was measured (2026-10-14, `agy` 1.3.5)

**The language-server discovery does not apply to it.** The interactive `agy` runs its server inside its own process: `ps` shows a bare `agy` with no `--csrf_token` on the command line and no `language_server` child, while `lsof` shows it listening on two loopback ports. There is no token to find, so it is not one more `Origin`.

**It answers `/usage` itself in print mode.** `agy -p "/usage" --output-format json` prints a JSON envelope whose `command.data.groups[].buckets[]` holds the same data as `RetrieveUserQuotaSummary`: the same bucket ids (`gemini-5h`, `gemini-weekly`, `3p-5h`, `3p-weekly`), the same `5h` / `weekly` windows, `remaining_fraction` and `reset_time`, in snake case. Group names are under `name`, not `displayName`. `/quota` is an alias. The CLI's changelog says these print-mode answers start no agent turn, spend no quota and leave no conversation, and that held: no conversation, history entry or log appeared. The CLI's own `/help` lists no other command that names the plan, so `plan` stays nil on this route.

The envelope's tab-separated `response` text rounds the percentages (a fraction of 0.998 prints as `100%`), so only `remaining_fraction` is read. A run took about 8.5 seconds, most of it the CLI's own eligibility check over the network; the deadline is 30 seconds. A failed run exits 1 with `"status": "ERROR"` and an `error` message — measured with an unreachable proxy — which does not say reliably whether the cause is the network or the login.

### How it is asked

1. **Only when the language server produced no figures.** The server is local and fast, and it belongs to the account the open editor is using. Asking the CLI first would start a process and a network request on every refresh, and the CLI may be signed in to a different Google account.
2. **Only `agy` 1.1.11 or newer.** `agy --version` (about 40 ms) is read first. Before 1.1.11, a slash command in print mode fell through as literal prompt text, so `-p "/usage"` would be **sent to the model**, spend quota and leave a conversation behind — on every refresh. Pulse sends nothing on the user's behalf, so a version that cannot be read counts as too old and the CLI is not asked.
3. **With `--log-file /dev/null`.** Without it, every run writes a new log file under `~/.gemini/antigravity-cli/log/` and repoints `cli.log` at it, away from the log of the session the user is running.
4. **From the temporary directory**, because the CLI looks for project files around the folder it runs in.

Only `agy` is looked for (`CommandLocator`). `antigravity` is also the name of the editor's own shell command, a different program.

### When the CLI does not answer

**Automatically, the language server's reason stands.** A CLI that exits with an error, times out or prints something unreadable leaves `.antigravityNotRunning` or `.antigravityNotAnswering` in place, and the CLI's attempt is recorded for the diagnostics. Reporting the CLI's failure instead would raise a notification for someone who installed `agy`, never signed in to it and closed the editor. A CLI that answers with no limits reports `.noLimitsReported`, which is an answer, not a fault. **Pinned to *CLI*, every failure is its own** (`cliOnly`): `.antigravityCLIMissing` when `agy` is not installed, `.antigravityCLIOutdated` below 1.1.11 or with an unreadable version, and the run's own reason otherwise. Both new reasons are setup, not outages, so they raise no failure notification.

**`/credits` is not read.** It reports a separate balance of AI credits (`remaining_credits`) that can be bought, not the plan's quota, and a balance of 0 is what an account that never bought any reports.

## Mapping

**It reports what is left, not what is gone** — `remainingFraction: 1` means nothing used. Inversion happens here.

The reply nests `groups[].buckets[]`. Each bucket: `bucketId` (stable, so it can be pinned), `window` (`5h` / `weekly`), `remainingFraction`, a real `resetTime` timestamp. The group’s name becomes the window’s `scope` with a trailing “models” trimmed (“5-hour limit · Gemini”).

A bucket whose `window` cannot be read is **left out rather than guessed at**. A window with no length cannot be named or sorted.

## Plan name

Second call: `GetUserStatus`. Only `planName` is decoded. The same reply holds name and email — the user’s, no use to Pulse.

## What was checked rather than assumed

Of the 306 methods the language server exposes, not one has “usage” or “credit” in its name; `GetUserAnalyticsSummary` answers `{}`; `~/.antigravity` holds only binaries and extensions; the editor’s `state.vscdb` keeps conversation titles and two sentinel values under `modelCredits`, no token counts.

So history, money estimate, and activity cannot be built from the language server — they need per-model token counts it does not give. They come instead from the conversation stores under `~/.gemini`, read by Token spend ([../token-spend-sources.md](../token-spend-sources.md)).

`~/.gemini` was **not** on that list and should have been: it holds `antigravity/`, `antigravity-ide/` and a `jetski-standalone-oauth-token` of `{auth_method, token}`. That is the Google OAuth route CodexBar calls experimental, and its own notes say the OAuth payload can only prove model availability — an all-100% placeholder rather than real quota. Worth knowing before anyone spends a day on it. It carries no token counts either, so it changes nothing above.

### The OAuth route is off limits

Antigravity's terms (section 6, [antigravity.google/terms](https://antigravity.google/terms)) call using third-party software to access the service — their example is OpenClaw with Antigravity OAuth — a breach that may get the Antigravity and Gemini CLI accounts suspended or terminated. Since early 2026 Google's developer forum has carried many such suspensions (`403` "disabled … for violation of Terms of Service"), some of which also disabled the official `agy`. So Pulse never reads `jetski-standalone-oauth-token` and never calls Google's backend with it, whatever it would unlock; that is also why a second Antigravity account (#124) is not offered. The two routes Pulse does use stay on this Mac: the running app's own language server, and the official `agy` CLI asked for `/usage` with no model request. Neither touches the OAuth token, and no suspension tied to either was found (checked 2026-11-25).

Antigravity also reports a monthly credit *allowance*, never a balance, which is why `creditBalance` stays nil: an allowance shown there would read as what is left.

## Separate allowances, optionally one ring each

The plan carries a Gemini allowance and a separate one for Claude and GPT, reported as `scope`s of one login — the reason `Provider.splitsByModelGroup` exists and names only this provider. Since 2026-11 some accounts report a third group, a weekly-only allowance for Gemini 4 Argon outside the Gemini one: on a Pro account the CLI answered a group named `Gemini 4 Argon` (no trailing "models", so its scope is the name as given) with one bucket, `gemini-argon-wtu-weekly`, `window` `weekly` (#106, the reporter's `agy` output on 2026-11-05; the account measured here still answered two groups). Its description says Ultra plans fold Argon into the larger Gemini bucket, so the group's presence depends on the plan. Pinned by the `antigravity-cli-usage-argon.json` fixture. The Antigravity pane offers "A ring for each model group", off by default; on, the rail draws one ring per group, each with this provider's icon and all refreshing the same login, and each group has its own switch so a group nobody uses need not cost a ring. A weekly-only group is one window, so its ring has no second ring. The rail-side rules are in [../ui/rings-and-surface.md](../ui/rings-and-surface.md#one-ring-per-model-group).

`modelGroupCount` is a fixed 3 rather than counted from a reading, so the rail's own budget does not move when a reply arrives one group short; with groups left off, the budget is the groups chosen.

## First run

`/Applications/Antigravity.app` or `~/Applications/Antigravity.app`. Not everyone installs into `/Applications`. `Antigravity IDE.app` is deliberately **not** first-run evidence: it is a second product, and the ring it would switch on is the same one — someone with only the IDE turns it on in Settings.

## Settings copy

A picker, not a stated route: every provider with more than one route offers the choice (`hasSourceChoice`), so `Provider.soleRoute` is nil. Options are *Automatic* / *CLI* / *Desktop app* (`UsageSource.options(for:)`; *CLI* is `.tooling` titled by `title(for:)`). The subtitles: automatic “Reads Antigravity while it is open, else the agy CLI.”, CLI “Asks the agy CLI, using the login it already saved.”, desktop app “Asks the language server Antigravity runs while it is open.” Claude's desktop-route availability filter does not apply to it. `UsageRoute.soleRoute(for:)` is nil because the service records which route answered. The wording must not leak to other single-route providers. See [README.md](README.md).

## Activity mark

`supportsLocalActivity` is true. `agy` keeps one SQLite database per conversation in `~/.gemini/antigravity-cli/conversations/` (measured with `agy` 1.5.0 on 2026-11-17); Antigravity.app keeps its own in `~/.gemini/antigravity/conversations/`, and `antigravity-ide/conversations` is the editor's other spelling. All three turn the one ring (`AgentActivity.roots`). Token spend keeps the first apart from the other two ([../token-spend-sources.md](../token-spend-sources.md)): the `agy` process Gemini.app runs in the background opens the app's folder, but a conversation started in a terminal is written to `antigravity-cli`. A database counts as written when it or its `-wal` journal was, because the journal takes the writes until a checkpoint.

Only the newest row of `steps` is read (`step_type`, `status`; `AgentActivity.antigravityVerdict`). The numbers are `CortexStepStatus` and `CortexStepType` from the descriptor in `agy` 1.5; the progression was observed on 2026-11-17 with an `agy -p` run and an Antigravity.app conversation:

- **Pending, generating or queued** (1, 8, 11): the model is working. **Running** (2): a tool is, with the tool's longer grace.
- **Done** (3) on a model response (`PLANNER_RESPONSE`, 15) ends the turn; every turn in the store ends on one. Done on any other step, a prompt or a tool, leaves the move with the model, which opened its next response about ten seconds after a tool finished.
- **Waiting** (9) is waiting for a person and is not drawn. Error, canceled, interrupted and the rest end it too: a tool denied in print mode ended the run there.

The step's own time is inside a protobuf blob, so the grace is timed from the database's last write. A database without a `steps` table, or one that cannot be read at that moment (a WAL database with no journal beside it after `agy` exits, or one busy mid-recovery), is not work and is not cached: it is asked again on the next sample. `AntigravityActivityTests`.

## Windows preview

The experimental Electron port also checks a local Antigravity hub record for its per-launch token. It accepts the record only when the process path identifies Antigravity and the reported HTTPS port belongs to that process; stale records are ignored. It then uses the loopback quota endpoint. This route returned Gemini and Claude/GPT quota windows from Antigravity 2.35 on one Windows machine. Other versions and long-running operation still need verification. The CLI route remains a fallback when supported.
