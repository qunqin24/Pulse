# Antigravity

Service: [`AntigravityUsageService.swift`](../../Sources/Pulse/AntigravityUsageService.swift).

The odd one out, and the only route it has. Extra accounts are not supported. `keepsLocalTranscripts` is false: it is an editor, not a CLI, and leaves no session files Pulse can read. History, the money estimate, and the activity mark are left out rather than shown as zeroes.

## Route

Antigravity’s editor starts a `language_server` of its own and talks to it over HTTPS on loopback. That process is the only thing that knows the quota, so **these figures exist only while the app is open** — `.antigravityNotRunning` says that plainly rather than dressing it up as a failure.

Three things are discovered and **none may be assumed**:

1. The process — inside the app bundle, not on `PATH`, matched on `/Antigravity.app/` because `language_server` is Codeium’s binary and its other editors use the same name.
2. The port — the app starts it with `--https_server_port 0` (“take any free one”), so it differs every launch.
3. A per-launch CSRF token from the command line, sent as `x-codeium-csrf-token`.

It listens on more than one port and does not advertise which speaks this protocol, so they are tried in turn.

RPC: `exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`, POST `{}`.

The server signs its own certificate. `LoopbackTrust` accepts it — **only for `127.0.0.1`**. Anything else is refused exactly as it would be anywhere else in the app.

## Mapping

**It reports what is left, not what is gone** — `remainingFraction: 1` means nothing used. Inversion happens here.

The reply nests `groups[].buckets[]`. Each bucket: `bucketId` (stable, so it can be pinned), `window` (`5h` / `weekly`), `remainingFraction`, a real `resetTime` timestamp. The group’s name becomes the window’s `scope` with a trailing “models” trimmed (“5-hour limit · Gemini”).

A bucket whose `window` cannot be read is **left out rather than guessed at**. A window with no length cannot be named or sorted.

## Plan name

Second call: `GetUserStatus`. Only `planName` is decoded. The same reply holds name and email — the user’s, no use to Pulse.

## What was checked rather than assumed

Of the 306 methods the language server exposes, not one has “usage” or “credit” in its name; `GetUserAnalyticsSummary` answers `{}`; `~/.antigravity` holds only binaries and extensions; the editor’s `state.vscdb` keeps conversation titles and two sentinel values under `modelCredits`, no token counts. So history, money estimate, and activity cannot be built — they need per-model token counts that do not exist to be read.

Antigravity also reports a monthly credit *allowance*, never a balance, which is why `creditBalance` stays nil: an allowance shown there would read as what is left.

## First run

`/Applications/Antigravity.app` or `~/Applications/Antigravity.app`. Not everyone installs into `/Applications`.

## Settings copy

`Provider.soleRoute` names “Antigravity’s language server” / “Only while Antigravity is open.” That wording must not leak to other single-route providers. See [README.md](README.md).
