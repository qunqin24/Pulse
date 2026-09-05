# Kimi Code

Service: [`KimiCodeUsageService.swift`](../../Sources/Pulse/KimiCodeUsageService.swift).

Extra accounts are not supported. `keepsLocalTranscripts` is false. No first-run detection: nothing to install, Pulse never goes looking for a key, so it stays off until switched on.

## Credential

A key the user pastes, kept in `keys.dat`. No fallback to another tool’s file.

## Route

`GET https://api.kimi.com/coding/v1/usages` with a bearer token.

The service comments this as Kimi’s **documented** usage endpoint, unlike most of the undocumented account routes elsewhere. That is not a Pulse official-integration claim, and the JSON can still change.

## Two kinds of limit, not the same figure

- `limits[]` — windows the service actually times, each stating a `duration` and a `timeUnit`. Read as given. An unrecognised unit **drops that entry** rather than being guessed at.
- `usage` — the weekly allowance. The reply gives a reset time and **no length**. Because the window rolls, the reset lands anywhere inside the week and says nothing about how long it runs. Seconds sort it after the shorter windows (`reportsLength: false`) and are never displayed. The window clock and forecast must not divide by that number.

Every count arrives as a **string**. `limits[].detail` reports what is *left* with no `used` field, so spend is `limit - remaining` there and `used` where that is given.

`membership.level` is the plan, tidied from `LEVEL_INTERMEDIATE` to “Intermediate”, passed through when unfamiliar. `parallel.limit` is how many requests may run at once, not a balance. `totalQuota` comes back empty. Neither becomes `creditBalance`.
