# Kimi Code

Service: [`KimiCodeUsageService.swift`](../../Sources/Pulse/KimiCodeUsageService.swift). Sign-in: [authentication.md](authentication.md).

Extra accounts are supported, same device-code path as Codex extras. `keepsLocalTranscripts` is false. No first-run detection: a subscription login Pulse has never driven, and no pasted key, stays off until switched on in Settings.

## Credential

Two, same endpoint. Settings **Read usage from** picks which:

1. **Automatic** (default) — Pulse’s device-code login when one is stored, otherwise the pasted key. A leftover key that the host refuses must not hide a working subscription login.
2. **API key** — `keys.dat` only.
3. **Signed-in account** — `accounts.dat` under the primary `kimiCode` account only.

Pulse renews its own login. The official CLI’s `~/.kimi-code/credentials/` file is **not** read and **not** written — using that refresh token would rotate it and sign the CLI out.

A subscriber who never creates a console key uses (1) or (3). Pin (2) if the key is the one you want read.

Never signed in and no key: `.kimiSignInRequired`. Pulse’s login will not refresh: `.kimiLoginExpired`. A pasted key the host refuses stays `.apiKeyRefused`. An extra account whose login is gone is `.signedOut`.

## Route

`GET https://api.kimi.com/coding/v1/usages` with a bearer token — an API key or Pulse’s OAuth access token. Measured 2026-09-08: the CLI access token answers 200 on this path with no CLI identity headers.

Device-code sign-in is RFC 8628 against `auth.kimi.com`, public client id from the Kimi Code CLI. Settings says the consent page names Kimi Code, not Pulse. Access tokens last about fifteen minutes; refresh tokens about thirty days and **rotate**. That lifetime is why Pulse holds its own login rather than borrowing the CLI’s.

The JSON can still change. This is not a Pulse official-integration claim.

## Two kinds of limit, not the same figure

- `limits[]` — windows the service actually times, each stating a `duration` and a `timeUnit`. Read as given. An unrecognised unit **drops that entry** rather than being guessed at.
- `usage` — the weekly allowance. The reply gives a reset time and **no length**. Because the window rolls, the reset lands anywhere inside the week and says nothing about how long it runs. Seconds sort it after the shorter windows (`reportsLength: false`) and are never displayed. The window clock and forecast must not divide by that number.

Every count arrives as a **string**. `limits[].detail` reports what is *left* with no `used` field, so spend is `limit - remaining` there and `used` where that is given.

`membership.level` is the plan, tidied from `LEVEL_INTERMEDIATE` to “Intermediate”, passed through when unfamiliar. `parallel.limit` is how many requests may run at once, not a balance. `totalQuota` comes back empty. Neither becomes `creditBalance`.
