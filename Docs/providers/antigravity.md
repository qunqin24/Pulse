# Antigravity

Service: [`AntigravityUsageService.swift`](../../Sources/Pulse/AntigravityUsageService.swift).

The odd one out. Extra accounts are not supported. `keepsLocalTranscripts` is false: it is an editor, not a CLI, and leaves no session files Pulse can read. History, the money estimate, and the activity mark are left out rather than shown as zeroes.

## Route

Antigravity starts a `language_server` of its own and talks to it over HTTPS on loopback. That process is the only thing that knows the quota, so **these figures exist only while something of Antigravity’s is running** — `.antigravityNotRunning` says that plainly rather than dressing it up as a failure.

Three things are discovered and **none may be assumed**:

1. The process — inside an app bundle, not on `PATH`, matched on the **bundle path** because `language_server` is Codeium’s binary and its other editors ship the same one.
2. The port — started with `--https_server_port 0` (“take any free one”), so it differs every launch.
3. A per-launch CSRF token from the command line, sent as `x-codeium-csrf-token`.

RPC: `exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`, POST `{}`.

The server signs its own certificate. `LoopbackTrust` accepts it — **only for `127.0.0.1`**. Anything else is refused exactly as it would be anywhere else in the app.

### Two origins, several processes

`Origin` is the preference order: `Antigravity.app`, then `Antigravity IDE.app`. `/Antigravity.app/` does not match `/Antigravity IDE.app/` — the space separates them, which is why both fragments are written with their slashes. The IDE’s copy is named `language_server_macos_arm`; it still contains `/language_server`, so the name test holds for both.

**Every candidate is tried, and every port each listens on.** Taking the first match and giving up was a real fault: measured with only the IDE open, it runs *two* language servers and the one that answers was second — the other returns **401 to this RPC**, which is that process saying “not me”, not the account being refused. So `.refused` is worth no more than a closed port here and the search continues — and so is an undecodable 200, or the first odd body ends the search and the server that would have answered is never asked. An answer with no limits in it is held rather than returned, because that is also what a wrong server says; it is only reported as `.noLimitsReported` if nothing better turns up.

**What is reported when nothing answered matters too.** A server that refused is still Antigravity *running*. Reporting `.unreachable` there says the app is not there while it is — and the notification rules count `.unreachable` as a fault while `.antigravityNotRunning` is not, so the multi-origin search briefly turned "Antigravity is being unhelpful" into a banner about an app that was open. `fetch` tracks whether anything answered at all and picks between the two.

### What the IDE actually serves (measured 2026-09-06)

CodexBar’s notes say the IDE’s local endpoints expose only session/model quota data and not the weekly grouping. **Not what this Mac reports.** With `Antigravity.app` closed and only `Antigravity IDE.app` open, `RetrieveUserQuotaSummary` returned the full payload — both groups, weekly and five-hour buckets, real reset times:

| bucket | scope | window | remainingFraction |
|---|---|---|---|
| `gemini-5h` | Gemini Models | 5h | 1 |
| `gemini-weekly` | Gemini Models | weekly | 0.9949068 |
| `3p-5h` | Claude and GPT models | 5h | 1 |
| `3p-weekly` | Claude and GPT models | weekly | 1 |

That payload is committed as `Tests/PulseTests/Fixtures/antigravity-quota.json` and is what `AntigravityParsingTests` holds the parser against. `GetUserStatus` on the same port named the plan (`Pro`). Their note may be about an older IDE build; either way, do not drop the IDE origin on the strength of it without re-measuring.

### The `agy` CLI, not implemented

There is a third source: Google ships a standalone CLI (`brew install --cask antigravity-cli`, binary `antigravity` symlinked to `agy`, state under `~/.gemini/antigravity-cli`) which runs its own embedded HTTPS server, and CodexBar reports it as the richest of the sources and the one that works with no editor open at all.

It is **not implemented, because it could not be observed**: the cask is not installed on the machine this was written on, so whether `agy` spawns a matching `language_server` process with a `--csrf_token` on its command line — which is the whole of the discovery above — is unknown. Adding it is one `Origin` case once somebody can watch it run. Writing that case from a guess is exactly what “none may be assumed” is about.

## Mapping

**It reports what is left, not what is gone** — `remainingFraction: 1` means nothing used. Inversion happens here.

The reply nests `groups[].buckets[]`. Each bucket: `bucketId` (stable, so it can be pinned), `window` (`5h` / `weekly`), `remainingFraction`, a real `resetTime` timestamp. The group’s name becomes the window’s `scope` with a trailing “models” trimmed (“5-hour limit · Gemini”).

A bucket whose `window` cannot be read is **left out rather than guessed at**. A window with no length cannot be named or sorted.

## Plan name

Second call: `GetUserStatus`. Only `planName` is decoded. The same reply holds name and email — the user’s, no use to Pulse.

## What was checked rather than assumed

Of the 306 methods the language server exposes, not one has “usage” or “credit” in its name; `GetUserAnalyticsSummary` answers `{}`; `~/.antigravity` holds only binaries and extensions; the editor’s `state.vscdb` keeps conversation titles and two sentinel values under `modelCredits`, no token counts.

So history, money estimate, and activity cannot be built — they need per-model token counts that do not exist to be read.

`~/.gemini` was **not** on that list and should have been: it holds `antigravity/`, `antigravity-ide/` and a `jetski-standalone-oauth-token` of `{auth_method, token}`. That is the Google OAuth route CodexBar calls experimental, and its own notes say the OAuth payload can only prove model availability — an all-100% placeholder rather than real quota. Worth knowing before anyone spends a day on it. It carries no token counts either, so it changes nothing above.

Antigravity also reports a monthly credit *allowance*, never a balance, which is why `creditBalance` stays nil: an allowance shown there would read as what is left.

## First run

`/Applications/Antigravity.app` or `~/Applications/Antigravity.app`. Not everyone installs into `/Applications`. `Antigravity IDE.app` is deliberately **not** first-run evidence: it is a second product, and the ring it would switch on is the same one — someone with only the IDE turns it on in Settings.

## Settings copy

`Provider.soleRoute` names “Antigravity’s language server” / “Only while Antigravity is open.” The second half is now slightly narrow — the IDE counts too — but it names the right condition and the right remedy, so it is left alone until the `agy` source makes it properly wrong. That wording must not leak to other single-route providers. See [README.md](README.md).
