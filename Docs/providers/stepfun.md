# StepFun

StepFun's (阶跃星辰) Step Plan, read through the console's own request.

**Measured on one account.** The Token Plan reply (`stepfun-token-plan.json`) is a real capture from a Plus subscription on `platform.stepfun.com`, 2026-09-24, as is the plan-status reply and the signed-out 401. The whole path — cookies read from Chrome, both requests, the ring, the plan name and the expiry line — was checked in a bundled build against that account the same day. The Coding Plan shape and the route's headers come from monitors that already read it — [CodexBar](https://github.com/steipete/CodexBar)'s StepFun fetcher (MIT) — not from a capture made here. `platform.stepfun.ai` was seen to answer the same route with the same 401 when signed out; no signed-in reply from it has been seen.

## Place in Pulse

- `Provider.stepFun`. Name "StepFun" — the company, since the plan's name alone says nothing about whose it is. Icon `stepfun` (lobe-icons). Brand colour `#0160FF`, the deep end of its gradient. Extra accounts: no. Transcripts: no. Spending history: no.
- First run: offered unchecked. Detected hint when `~/.stepcode` exists (StepFun's own coding CLI, Step Code) — a hint only; the CLI's saved credential is not read.
- `usesAPIKey` and `usesSessionCookie` are true, so Settings draws a **session cookie** row and "Read from browser", as for Qoder.
- Service: [`StepFunUsageService.swift`](../../Sources/Pulse/Providers/StepFunUsageService.swift). Tests: `StepFunParsingTests`. Fixtures `Tests/PulseTests/Fixtures/stepfun-*.json`.

## Why a browser session

The Step API key buys inference and answers nothing about the plan. The one documented account route, `GET https://api.stepfun.com/v1/accounts`, answers the key with the account's **prepaid balance** — a separate system: Step Plan usage never draws on it. The plan's allowance is only on the console.

## Two sites, one row

`platform.stepfun.com` and `platform.stepfun.ai` are separate sign-ins. `AppSettings.stepFunSite` (`StepFunSite`, default `.china`) decides which host the browser is asked for cookies and where the request goes; **changing it clears the saved session**, and readings carry a `UsageScope` of `.webSession`, the host and the session's SHA-256 (`requiresScopeMatch`), exactly as Qoder's do ([qoder.md](qoder.md)).

## The route

`POST https://{site}/api/step.openapi.devcenter.Dashboard/QueryStepPlanRateLimit`, body `{}`, with the session as `Cookie` and the console's own headers: `oasis-appid: 10300`, `oasis-platform: web`, `oasis-webid`, `Origin`, `Referer` (`/plan-usage`), a Chrome `User-Agent`. Then `…/GetStepPlanStatus` for the plan's name (`subscription.name`, "Plus"); its failure costs the name and nothing else.

**`oasis-webid` must be the token's own device.** A token presented with another device id is refused as stolen. It is the `Oasis-Webid` cookie when the session carries one, otherwise the `device_id` claim read (not verified) from the token.

| Status | Reported as |
|---|---|
| 200, `status: 1` | parsed |
| 200, another `status` | `stepFunSessionExpired` if it speaks of auth or a token, else `unreadableReply` |
| 401, 403 | `stepFunSessionExpired` — signed out is `{"code":"unauthenticated","message":"auth failed: token is missing"}` with a 401, measured |
| 429 | `rateLimited` |
| 5xx | `serverError` |
| no response | `unreachable` |

## The cookies

**An allow list**: `Oasis-Token` (required), `Oasis-Webid` and `INGRESSCOOKIE` (sent when present). Nothing else the host set is forwarded. Control characters refuse the whole header. `document.cookie` did not show `Oasis-Webid` on the account measured (it is HttpOnly or absent), and the console's request succeeded anyway; the browser store read by Pulse sees HttpOnly cookies.

## Two plans, one reply

Since 2026-06-18 StepFun sells a **Token Plan**: Credits (1M Credit = ¥1) issued monthly into a pool that is cleared at the month's end, plus top-up packs, each good for its own thirty days, spent soonest-lapsing first. The **Coding Plan** before it — still renewed for anyone who kept auto-renew on — meters a five-hour and a weekly window by request. One reply carries whichever the account has, and zeroes the other's fields.

**Classified by what the reply carries, not by `plan_family`.** A window with a stated reset is the Coding Plan; a Token Plan sends both windows as `0` with a reset of `"0"`, which means "no window", not "spent".

### Token Plan

```json
{ "status": 1, "five_hour_usage_left_rate": 0, "five_hour_usage_reset_time": "0", "plan_family": 2,
  "plan_credit_rate_limit": { "subscription_credit_left_rate": 0.9999462, "subscription_credit_reset_time": "0",
    "topup_credit_left_rate": 0,
    "credit_buckets": [ { "type": 1, "credit_total": "1600000000", "credit_residual": "1599913834",
                          "expire_at": "1791187256", "next_reset_at": "0" } ] } }
```

- **One ring**, `stepfun.credits`, `kind: .credits` ("Credit allowance"): every bucket — the month's pool and any packs — summed, because they are spent from one balance. Fraction is `(total − residual) / total`; spent when nothing is left in any bucket.
- `resetsAt` is the soonest `next_reset_at` still ahead — a quarterly or yearly plan's next monthly issue. **A monthly plan states none**, and none is claimed: its pool simply ends.
- That end is `nextExpiry`: the soonest `expire_at` with credits left, packs ending the same day added together (`UsageWindow.Expiry.soonest`, shared with Qoder). On the account measured it was the subscription's own end, 2026-10-05. The card shows it when it comes before any reset — "其中 16亿 积分 10月5日 到期"; amounts from ten thousand up are abbreviated as token counts are (`TokenCount.short`).
- Bucket sizes arrive as decimal strings, rates as numbers; timestamps are seconds as strings, `"0"` for none.
- Without buckets, the stated `subscription_credit_left_rate` (else `topup_credit_left_rate`) is the fraction — **never both added**, since their sizes are not given. Nothing at all is `stepFunNoPlan`.
- `windowSeconds` is thirty days as a sort key; `reportsLength` false.

### Coding Plan

`five_hour_usage_left_rate` / `weekly_usage_left_rate` are the **fraction left**; used is one minus it. Each window counts only with a reset time (`*_reset_time`, seconds or milliseconds). `stepfun.5h` (`.fiveHour`, 5 hours) and `stepfun.weekly` (`.weekly`, 7 days), both `reportsLength` true: those are the plan's own lengths.

## What an empty answer means

`stepFunNoPlan` — the session works and the account has no Step Plan on it — is an answer, not an outage (`UsageAlerts.standing` → `.answered`), and like Qoder's no-credits answer it **clears the banked reading** so a later failure or relaunch cannot bring back a plan StepFun says is gone.

## Unconfirmed

- **A signed-in reply from `platform.stepfun.ai`.** Assumed identical.
- **The Coding Plan's reply**, and what a spent window reads as.
- **Top-up buckets.** Assumed to be further entries of `credit_buckets` (type `2`) with their own thirty-day `expire_at`; not seen.
- **`next_reset_at` on a quarterly or yearly plan.** Assumed to be the next monthly issue.
- **Whether `oasis-webid` or `INGRESSCOOKIE` is needed** when the browser supplies the whole session.
