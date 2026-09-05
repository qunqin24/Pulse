# GitHub Copilot

Service: [`CopilotUsageService.swift`](../../Sources/Pulse/CopilotUsageService.swift). Sign-in: [`GitHubDeviceLogin.swift`](../../Sources/Pulse/GitHubDeviceLogin.swift), [authentication.md](authentication.md).

Extra accounts are not supported. `keepsLocalTranscripts` is false. `usesAPIKey` is false (Settings draws a sign-in, not a paste field) but `keepsOwnCredential` is **true** — the token lives in `keys.dat`. Loading keys with `usesAPIKey` alone left a signed-in account reporting “sign in again”.

No first-run detection.

## Route

`GET https://api.github.com/copilot_internal/user` with `Authorization: token …` (GitHub’s older scheme; **Bearer is refused**) and the editor headers Copilot plugins send (`Editor-Version`, `Editor-Plugin-Version`, `X-Github-Api-Version`). Dropping those headers has been reported to change what comes back.

This is **not** a public documented Copilot quota API — the path name says internal — and it can change without notice. GitHub’s device-code *login* is documented; the quota JSON is not.

**The reply reports what is left.** `percent_remaining` at 90 means 10% spent. Inversion happens here.

## Three quotas, not two

`quota_snapshots` for `premium_interactions`, `chat`, and `completions`. Which an account has depends on the plan. A reference implementation this was checked against reads only the latter two; on a free plan `completions` is the largest allowance of the three (2,000 against chat’s 200), so leaving it out hides most of what the account has.

## Unissued vs spent vs overage

A quota the plan does not include arrives with `has_quota: false`, nothing issued, and `percent_remaining: 0` — which read literally is a full red ring for something the account never had. Drop it. Older replies omit the flag; then a 100% remaining lane with nothing issued is treated as a placeholder, while a lane you have **run out of** must not be dropped (that hides the alarm).

Unlimited lanes are dropped: no share to show.

**Spent is not the same as over the allowance.** A lane with overage permitted keeps working past its included share and is billed for it. Copilot’s own client treats exhausted as `used >= quota && !overageEnabled && !unlimited`. `overage_count` above zero means the opposite of blocked. Reading it as spent painted a red ring for someone who had deliberately paid to carry on. Current rule: exhausted when remaining is 0 **and** `overage_permitted` is not true.

## Reset

One date for the whole account (`quota_reset_date_utc`); it lands on the first of a month. Per-snapshot `quota_reset_at` is 0 and useless. A calendar month is 28 to 31 days, so `reportsLength` is false and the clock arc draws nothing.

Plan names from `copilot_plan` are tidied (`individual` → “Individual”); unfamiliar values pass through.

## Sign-in

Device code, scope `read:user` only, verification URL **without** the user code. Token stored in `keys.dat`. Why not paste `gh`’s token: [authentication.md](authentication.md).
