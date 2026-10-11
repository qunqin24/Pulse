# Qoder

Qoder's credits, read through the account page's own request.

**Nothing here was run against a live account by Pulse.** One reporter's capture from the mainland site (issue #59, a trial account, sanitized into `qoder-credits-trial-stale-reset.json`) is the only real reply seen; the rest of the route, the headers and the reply shape come from monitors that already read it — [CodexBar](https://github.com/steipete/CodexBar)'s `QoderUsageFetcher` and its fixtures (from CodexBar#1590), and the AIBalance notes attached to that issue — not from a capture made here. The parsing is pinned by fixtures written to that shape. Requested in issue #59, which pointed at cockpit-tools; that project carries no licence and guesses the shape by keyword, so nothing was taken from it.

## Place in Pulse

- `Provider.qoder`. Icon `qoder` (lobe-icons). Brand colour `#2ADB5C`. Extra accounts: no. Transcripts: no. Spending history: no.
- First run: offered unchecked in the chooser. Detected hint when `~/Library/Application Support/Qoder` or `QoderCN`, or `Qoder.app`, exists — a hint only; nothing the app keeps is read.
- `usesAPIKey` and `usesSessionCookie` are true, so Settings draws a **session cookie** row and the "Read from browser" row, as for Ollama and Xiaomi.
- Service: [`QoderUsageService.swift`](../../Sources/Pulse/Providers/QoderUsageService.swift). Tests: `QoderParsingTests` (the parts included), `QoderCacheTests`, and the site/session case in `UsageCacheTests`. Fixtures `Tests/PulseTests/Fixtures/qoder-*.json`.

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

Each field is accepted in either spelling. Other readers recorded all-camelCase; the mainland reply in issue #59 **mixes them** — `lastResetAt` / `nextResetAt` in camelCase, everything else (`total_quota.quota_summary.used_value`, …) in snake_case. `nextResetAt` may be ISO 8601 or a Unix stamp in seconds or milliseconds; zero is no date. The reply also carries `plan_quota`, `resource_package_quota` and `dedicated_resource_package_quota`; `total_quota` is their sum (confirmed on the mainland site). They are read for the parts below and drawn only on request. A part that is absent or unreadable is no part — **never an unreadable reply**, since the total stands without it. A trial reply has no `sharedQuota`.

## What the rail is told

- `qoder.credits`, `kind: .credits` ("Credit allowance"): `totalQuota`, the account's plan plus any pack bought on top. `resetsAt` is `nextResetAt` — **unless that is already past at read time, when it is dropped.** A mainland trial answered with a `nextResetAt` a month old beside 586 spendable credits; passed on, the cache (`ProviderUsage.current(at:)`) treated the ring as reset and replaced a complete reading with "no limits reported".
  `nextExpiry`: the soonest **packs to lapse** out of `total_quota.quota_detail` — entries with credits left, not `is_active: false`, and an `expires_at` still ahead (the plan's entry carries `0`, no date). Packs ending on the same local day are added up. The card's reset slot shows "其中 86 积分 10月18日 到期" when that comes before the reset (or there is none), and `--json` carries it as `expiresAt` / `expiringAmount`. **An expiry is not a reset** — it takes credits away rather than giving them back — so it never feeds `hasTurnedOver` or the countdown. A detail list that cannot be read is an empty one, never an unreadable reply.
- `qoder.shared`, `kind: .sharedCredits` ("Team credits"): `sharedQuota`, a team plan's pool. **A second ring, never summed** into the first — a spent personal allowance beside an untouched team pool reads as "plenty left" about the pool that is actually stopping you. No reset is claimed for it; the reply states the account's.

### The parts (issue #76)

**Off by default** (`AppSettings.qoderShowsParts`, Panel group: "Show each part of the credits"). The total mixes three things spent and lapsing on their own, so it can read 57% left while a resource pack is at 95% — the same failure as summing the team pool, inside the account's own credits. On, each part with a positive limit gets a row **after** the total, which stays:

- `qoder.plan`, `kind: .planCredits` ("Plan credits"): `plan_quota`. Carries `nextResetAt` (when ahead), the only part that refreshes.
- `qoder.pack`, `kind: .topUp` ("Top-up pack", the term Pulse already uses for Warp's and V2EX's): `resource_package_quota`. No reset.
- `qoder.dedicated`, `kind: .dedicatedCredits` ("Dedicated credits"): `dedicated_resource_package_quota` — on the mainland site the credits tied to Qwen, but the reply does not name the model family, so neither does Pulse. No reset.

Each part's `nextExpiry` comes from its **own** `quota_detail`. Drawn only when **two or more** parts have an allowance: one alone is the total under another name (the trial reply). The parts count the same credits as the total, so the ring's automatic choice (`headlineWindow`, the fullest) lands on whichever part is closest to spent, and the total never wins it. Changing the setting refetches (`onChange`).

### Both rings

Both: fraction is `usedValue / limitValue` (not the rounded `usagePercentage`); `windowSeconds` is thirty days as a **sort key**, `reportsLength` false — a trial runs a fortnight and a plan a billing month, and the reply says neither. `isExhausted` follows Qoder's `remainingValue` when stated, else `used >= limit`.

**A purchase is not a reset.** Buying a pack raises `limitValue` and drops the fraction with nothing turned over, so for these kinds `hasTurnedOver` accepts only a `nextResetAt` that moved forward, never the forty-point fall ([../notifications.md](../notifications.md)).

**A limit of zero is not drawn.** No ring at 100% for an allowance never granted: a zero shared pool is a placeholder and is dropped, and a zero personal allowance with nothing else is `qoderNoCredits` — an answer, not an outage (`UsageAlerts.standing` → `.answered`). This clears the account's previous reading from memory and disk, so a later failure, relaunch or `--json` export cannot restore an allowance Qoder has withdrawn. An allowance with a positive limit remains a reading even when its remaining credits are zero.

An absent or null `sharedQuota` means no team pool. A present pool must contain a readable summary with nonnegative used and limit values; malformed or incomplete figures are `unreadableReply`, never proof that the account has no credits. Those failures keep the usual same-site/session cache fallback. `QoderCacheTests` covers these transitions through the service and cache with synthetic HTTP responses, not a live account.

## Unconfirmed

- **Whether the route needs `Bx-V` or the browser `User-Agent`.** Sent because every reader sends them.
- **Which cookies authenticate.** If Qoder names its session cookie publicly, the deny list should become an allow list.
- **`nextResetAt` on a paid plan.** On the one trial seen it was a date a month past, thirty days after `lastResetAt`: a period that stopped turning over. Whether a paid plan's moves forward each month is not known.
- **`total_quota` mixes lifetimes.** It sums the plan with bonus packs that each carry their own `quota_detail[].expires_at`, and the single `nextResetAt` belongs to none of them. The packs' dates are read (above); whether a paid plan's `quota_detail` looks the same is not known — only one trial reply has been seen. Packs are not drawn one row each: six rows on the card, and the same credits the ring already counts. The three parts are, on request (above).
- **The parts on a paid account.** The figures in issue #76 (plan 157 / 6,000, pack 1,900 / 2,000, dedicated 4,011 / 6,000, total 6,068 / 14,000) came from the account page, not a captured reply; `qoder-credits-parts.json` is written to the trial reply's shape with those figures. That `nextResetAt` is the plan's refresh (2026-11-09 on that page) is inferred, not confirmed.
