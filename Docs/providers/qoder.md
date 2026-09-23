# Qoder

Qoder's credits, read through the account page's own request.

**Nothing here is a runtime test against a live account.** The route, the headers and the reply shape come from monitors that already read it — [CodexBar](https://github.com/steipete/CodexBar)'s `QoderUsageFetcher` and its fixtures (from CodexBar#1590), and the AIBalance notes attached to that issue — not from a capture made here. The parsing is pinned by fixtures written to that shape. Requested in issue #59, which pointed at cockpit-tools; that project carries no licence and guesses the shape by keyword, so nothing was taken from it.

## Place in Pulse

- `Provider.qoder`. Icon `qoder` (lobe-icons). Brand colour `#2ADB5C`. Extra accounts: no. Transcripts: no. Spending history: no.
- First run: offered unchecked in the chooser. Detected hint when `~/Library/Application Support/Qoder` or `QoderCN`, or `Qoder.app`, exists — a hint only; nothing the app keeps is read.
- `usesAPIKey` and `usesSessionCookie` are true, so Settings draws a **session cookie** row and the "Read from browser" row, as for Ollama and Xiaomi.
- Service: [`QoderUsageService.swift`](../../Sources/Pulse/Providers/QoderUsageService.swift). Tests: `QoderParsingTests`, `QoderCacheTests`, and the site/session case in `UsageCacheTests`. Fixtures `Tests/PulseTests/Fixtures/qoder-*.json`.

## Two sites, one row

`qoder.com` (international) and `qoder.com.cn` (mainland) are separate sign-ins on separate hosts. **One row with a site setting**, not two providers like MiniMax: it is one product sold under one name, and nobody subscribes to both. `AppSettings.qoderSite` (`QoderSite`) decides:

- which host the browser is asked for cookies (`BrowserCookies.session(forHost:)`: the host, its dot-form and its subdomains — never `qoder.com.cn` on behalf of `qoder.com`);
- where the request goes.

**Changing the site clears the saved session** (Settings does it), because a session kept across the switch would be sent to the host that did not issue it. The cache agrees: `qoderSessionMissing` is not papered over, and every reading carries a `UsageScope` of `.webSession`, the site's host, and the SHA-256 of the session (`requiresScopeMatch`), so one site's banked figures never stand in for the other's failure.

## The route

`GET https://{site}/api/v2/me/usages/big_model_credits`, with the session as `Cookie`, and the headers the page sends: `Origin` and `Referer` (`/account/usage`) for the site, `X-Requested-With: XMLHttpRequest`, `Bx-V: 2.5.35`, and a Chrome `User-Agent`. `Bx-V` belongs to the bot screening Alibaba puts in front of its sites; every known reader sends all of these, so this does too.

| Status | Reported as |
|---|---|
| 200 | parsed |
| 3xx, 401, 403 | `qoderSessionExpired` |
| 429 | `rateLimited` |
| 5xx | `serverError` |
| no response | `unreachable` |
| anything else, or a body that is not the shape below | `unreadableReply` |

## The cookies

**A deny list, where Ollama and Xiaomi keep an allow list.** Qoder's session cookie has no published name, and other readers forward everything the host set. `QoderCookie.normalize` keeps what the host set and drops third-party analytics prefixes (`_ga`, `_gcl`, `_fbp`, `Hm_`, …). **Alibaba's own (`cna`, `isg`, `tfstk`) are kept**: the same family carries the bot screening, and dropping one is how a session that works in the browser gets refused here. Control characters refuse the whole header; a single cookie Pulse cannot pass on unaltered is dropped rather than costing the session.

## The reply

```json
{ "quotaKey": "big_model_credits", "nextResetAt": "2024-09-01T00:00:00Z",
  "totalQuota":  { "quotaSummary": { "usedValue": 125, "limitValue": 500, "remainingValue": 375 } },
  "sharedQuota": { "quotaSummary": { "usedValue": 200, "limitValue": 1000, "remainingValue": 800 } } }
```

camelCase today; the snake_case of an earlier build (`total_quota.quota_summary.used_value`, …) is accepted too. `nextResetAt` may be ISO 8601 or a Unix stamp in seconds or milliseconds; zero is no date. The earlier build also sent `plan_quota` and `resource_package_quota`; `total_quota` is already their sum, so they are not read.

## What the rail is told

- `qoder.credits`, `kind: .credits` ("Credit allowance"): `totalQuota`, the account's plan plus any pack bought on top. `resetsAt` is `nextResetAt`.
- `qoder.shared`, `kind: .sharedCredits` ("Team credits"): `sharedQuota`, a team plan's pool. **A second ring, never summed** into the first — a spent personal allowance beside an untouched team pool reads as "plenty left" about the pool that is actually stopping you. No reset is claimed for it; the reply states the account's.

Both: fraction is `usedValue / limitValue` (not the rounded `usagePercentage`); `windowSeconds` is thirty days as a **sort key**, `reportsLength` false — a trial runs a fortnight and a plan a billing month, and the reply says neither. `isExhausted` follows Qoder's `remainingValue` when stated, else `used >= limit`.

**A purchase is not a reset.** Buying a pack raises `limitValue` and drops the fraction with nothing turned over, so for these kinds `hasTurnedOver` accepts only a `nextResetAt` that moved forward, never the forty-point fall ([../notifications.md](../notifications.md)).

**A limit of zero is not drawn.** No ring at 100% for an allowance never granted: a zero shared pool is a placeholder and is dropped, and a zero personal allowance with nothing else is `qoderNoCredits` — an answer, not an outage (`UsageAlerts.standing` → `.answered`). This clears the account's previous reading from memory and disk, so a later failure, relaunch or `--json` export cannot restore an allowance Qoder has withdrawn. An allowance with a positive limit remains a reading even when its remaining credits are zero.

An absent or null `sharedQuota` means no team pool. A present pool must contain a readable summary with nonnegative used and limit values; malformed or incomplete figures are `unreadableReply`, never proof that the account has no credits. Those failures keep the usual same-site/session cache fallback. `QoderCacheTests` covers these transitions through the service and cache with synthetic HTTP responses, not a live account.

## Unconfirmed

- **Whether the route needs `Bx-V` or the browser `User-Agent`.** Sent because every reader sends them.
- **The mainland site's shape.** Assumed identical to the international one, as CodexBar assumes.
- **Which cookies authenticate.** If Qoder names its session cookie publicly, the deny list should become an allow list.
- **`nextResetAt` on a trial.** Whether it is the trial's end or a monthly turnover is not known.
