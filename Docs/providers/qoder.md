# Qoder

Qoder's credits, read through the account page's own request.

**Nothing here was run against a live account by Pulse.** One reporter's capture from the mainland site (issue #59, a trial account, sanitized into `qoder-credits-trial-stale-reset.json`) is the only real reply seen; the rest of the route, the headers and the reply shape come from monitors that already read it — [CodexBar](https://github.com/steipete/CodexBar)'s `QoderUsageFetcher` and its fixtures (from CodexBar#1590), and the AIBalance notes attached to that issue — not from a capture made here. The parsing is pinned by fixtures written to that shape. Requested in issue #59, which pointed at cockpit-tools; that project carries no licence and guesses the shape by keyword, so nothing was taken from it.

## Place in Pulse

- `Provider.qoder`. Icon `qoder` (lobe-icons). Brand colour `#2ADB5C`. Extra accounts: no. Transcripts: no. Spending history: no.
- First run: offered unchecked in the chooser. Detected hint when `~/Library/Application Support/Qoder` or `QoderCN`, or `Qoder.app`, exists — a hint only; nothing the app keeps is read.
- `usesAPIKey` and `usesSessionCookie` are true, so Settings draws a **session cookie** row and the "Read from browser" row, as for Ollama and Xiaomi.
- Service: [`QoderUsageService.swift`](../../Sources/Pulse/Providers/QoderUsageService.swift). Tests: `QoderParsingTests` (the parts included), `QoderCacheTests`, and the site/session case in `UsageCacheTests`. Fixtures `Tests/PulseTests/Fixtures/qoder-*.json`.

## Two sites, one row

`qoder.com` (international) and `qoder.com.cn` (mainland) are separate sign-ins on separate hosts. **One row with a site setting**, as MiniMax's two sites now are: it is one product sold under one name, and nobody subscribes to both. Unlike MiniMax's pasted keys, the session is read back from the browser, so changing the site can clear it. `AppSettings.qoderSite` (`QoderSite`) decides:

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
  `nextExpiry`: the soonest **packs to lapse** out of `total_quota.quota_detail` — entries with credits left, not `is_active: false`, and an `expires_at` still ahead (the plan's entry carries `0`, no date). Packs ending on the same local day are added up. The card's reset slot shows the expiry when it comes before the reset (or there is none), in one of four shapes (`UsageDetailCard.expiryText`, issue #76):

  | Lapsing | Of the row's remainder (`remaining`) | Shown |
  |---|---|---|
  | One day | part of it | 「其中 86 积分 10月18日 到期」 |
  | One day | all of it (`coversRemainder`) | 「11月7日全部到期」 — no amount: the bar says how much |
  | Several days (`lots`, `totalAmount`) | part of it | 「其中 2,389 积分 11月7日起陆续到期」 |
  | Several days | all of it | 「11月8日起分 4 批全部到期」 |

  The several-day shapes exist because the mainland site's sign-in campaign grants 100 credits a day that each lapse thirty days after the claim, so a pack row can hold a lot a day for a month; naming the soonest alone said 100 of 400 had a deadline when all of them did. `--json` keeps the soonest lot as `expiresAt` / `expiringAmount`. The figure beside the line never wraps (`.fixedSize()`); the line shrinks to 80% and is then cut, which is why every language's wording is kept short — Russian drops the lot count to fit. **An expiry is not a reset** — it takes credits away rather than giving them back — so it never feeds `hasTurnedOver` or the countdown. A detail list that cannot be read is an empty one, never an unreadable reply.
- `qoder.shared`, `kind: .sharedCredits` ("Team credits"): `sharedQuota`, a team plan's pool. **A second ring, never summed** into the first — a spent personal allowance beside an untouched team pool reads as "plenty left" about the pool that is actually stopping you. No reset is claimed for it; the reply states the account's.

### The parts (issue #76)

**Off by default** (`AppSettings.qoderShowsParts`, Panel group: "Show each part of the credits"). The total mixes three things spent and lapsing on their own, so it can read 57% left while a resource pack is at 95% — the same failure as summing the team pool, inside the account's own credits. On, each part with a positive limit gets a row **after** the total, which stays:

- `qoder.plan`, `kind: .planCredits` ("Plan credits"): `plan_quota`. Carries `nextResetAt` (when ahead), the only part that refreshes.
- `qoder.pack`, `kind: .topUp` ("Top-up pack", the term Pulse already uses for Warp's and V2EX's): `resource_package_quota`. No reset.
- `qoder.dedicated`, `kind: .dedicatedCredits` ("Dedicated credits"): `dedicated_resource_package_quota` — on the mainland site the credits tied to Qwen, but the reply does not name the model family, so neither does Pulse. No reset.

Each part's `nextExpiry` comes from its **own** `quota_detail`, and **the total then shows none**: its soonest lapse is always one of the parts', and it repeated that part's line word for word, reading as one row listed twice. **Turning the parts on clears a ring pinned to the total** (`qoder.credits`): before the parts existed it was the only limit, so the pin meant automatic, and kept it would have held the ring on the total over the part closest to spent. A pin to a part stays. **Only a person turning it on does this, not a launch** (issue #89): the setting is restored through `AppSettings`' `init`, since an assignment from the `false` default to the stored `true` read as turning it on and dropped the total's pin on every launch. Drawn only when **two or more** parts have an allowance: one alone is the total under another name (the trial reply). The parts count the same credits as the total, so the ring's automatic choice (`headlineWindow`, the fullest) lands on whichever part is closest to spent, and the total never wins it. Changing the setting refetches (`onChange`). **A spent part turns the ring red while other parts still have credits** — the plan spent beside a pack with some left reads "spent" on the ring, though Qoder may go on drawing from the pack. That is what the reader asked for by switching it on; the total, still on the card, says what is left overall.

### Both rings

Both: fraction is `usedValue / limitValue` (not the rounded `usagePercentage`); `windowSeconds` is thirty days as a **sort key**, `reportsLength` false — a trial runs a fortnight and a plan a billing month, and the reply says neither. `isExhausted` follows Qoder's `remainingValue` when stated, else `used >= limit`.

**A purchase is not a reset.** Buying a pack raises `limitValue` and drops the fraction with nothing turned over, so for these kinds `hasTurnedOver` accepts only a `nextResetAt` that moved forward, never the forty-point fall ([../notifications.md](../notifications.md)).

**A limit of zero is not drawn.** No ring at 100% for an allowance never granted: a zero shared pool is a placeholder and is dropped, and a zero personal allowance with nothing else is `qoderNoCredits` — an answer, not an outage (`UsageAlerts.standing` → `.answered`). This clears the account's previous reading from memory and disk, so a later failure, relaunch or `--json` export cannot restore an allowance Qoder has withdrawn. An allowance with a positive limit remains a reading even when its remaining credits are zero.

An absent or null `sharedQuota` means no team pool. A present pool must contain a readable summary with nonnegative used and limit values; malformed or incomplete figures are `unreadableReply`, never proof that the account has no credits. Those failures keep the usual same-site/session cache fallback. `QoderCacheTests` covers these transitions through the service and cache with synthetic HTTP responses, not a live account.

### The credits themselves (issue #88)

**Off by default** (Card contents: **Quota amounts**; `AppSettings.qoderShowsAmounts` is its default until changed). Two parts at the same percentage can be 6,000 credits and 2,700, and only the credits say whether what is left will last. Every row Qoder draws carries `UsageWindow.amounts` — `usedValue`, `remainingValue` and `limitValue` as stated, nothing recomputed — and with the setting on the card puts "5,843 / 6,000" beside the row's name (`UsageDetailCard.amountText`): left out of all when the percentage counts what is left, used out of all when it counts what is used. A remainder Qoder did not state is not subtracted for it, so that row shows no amount while counting what is left. The card only: the rail, the ring and `--json` are unchanged. On the name's own line, so the row's height and the card's budget do not change; checked in all six languages with `CreditAmountRenderTests`.

### Credit history (issue #88)

The account's own usage records, in credits, over the last 31 local days: what was used (Σ`original_credits`, before discounts and free allowances) and what was deducted (Σ`credits`). On the reporter's account a week was 1,341 and 51, which is why both are shown. Two places, no setting of their own:

- **The card's history** (Card contents: **Today, 7 days and 31 days** or **31-day chart**): `QoderCreditSection` stands where `ActivitySection` stands for providers with a history — "Whole account", Today / 7 days / 31 days with the credits used large and "Charged …" under them, the 31 days as bars with today lit, and "From Qoder's usage records, in credits." It is drawn in `ActivitySection`'s rows at its heights, inside the `activityHeight` every detailed card already budgets. Asked when the detailed card opens, never on the refresh timer (`CardLedgers.readQoderCredits`, the same five-minute `lifetime` as the card's history); another session or site drops the figures at once, and a read that comes back for one no longer kept is dropped.
- **Qoder's settings pane** (`QoderCreditsGroup`, "Usage history"): the same three figures and the month as bars (`CreditBarChart`, the day's two figures on hover — not `SpendBarChart`, which speaks in tokens), read when the pane opens and on **Refresh**; no session says so rather than drawing an empty month.

`GET https://{site}/api/v1/me/usages/big_model_credits/histories?page=<n>&page_size=500&start_time=<ms>&end_time=<ms>&order_by=begin_at&order=-1` (`QoderSite.historiesURL`, `QoderClient.fetchCreditDays`), with the same session and headers as the credits route. These are the account's records, so the editor's work is in them as much as the CLI's — local files would have covered the CLI only (Qoder's IDE keeps no per-turn usage on disk, and its CLI writes zero tokens since 0.3.4). Not the account page's chart route: by the reporter's measurements it leaves the day in progress at zero until the next day, and its figure is the consumption before discounts. `begin_at` places a record on the reader's own day; quiet days are zero.

**Nothing unless the month closed**: a failed page, a body without `data` or `page_result`, a record without `begin_at` or either credit figure, or paging still pointing on after six pages of 500 leaves nothing drawn, never a sum of the part that came back. No records at all is a month of zeroes. The shape is second-hand — written from the reporter's measured replies on a mainland account and his patch's tests, not captured here (`QoderCreditDaysTests`, `CreditAmountRenderTests`); the international site is assumed to answer the same path.

## Unconfirmed

- **Whether the route needs `Bx-V` or the browser `User-Agent`.** Sent because every reader sends them.
- **Which cookies authenticate.** If Qoder names its session cookie publicly, the deny list should become an allow list.
- **`nextResetAt` on a paid plan.** On the one trial seen it was a date a month past, thirty days after `lastResetAt`: a period that stopped turning over. Whether a paid plan's moves forward each month is not known.
- **`total_quota` mixes lifetimes.** It sums the plan with bonus packs that each carry their own `quota_detail[].expires_at`, and the single `nextResetAt` belongs to none of them. The packs' dates are read (above); whether a paid plan's `quota_detail` looks the same is not known — only one trial reply has been seen. Packs are not drawn one row each: six rows on the card, and the same credits the ring already counts. The three parts are, on request (above).
- **The parts on a paid account — confirmed.** The reporter of issue #76 posted a sanitized reply from a paid mainland account (2026-10-12): the field names, the mixed spelling, `nextResetAt` as the plan's refresh (2026-11-09 00:00, matching the account page) and `lastResetAt` 110 days before it (so their difference is not a period, as `reportsLength = false` assumes) all match. Spent packs stay in `quota_detail` with `is_active: true` and `remaining_value: 0` — 19 of 23 there — so filtering on remaining, not on `is_active`, is required. `expires_at` is a millisecond timestamp, not a calendar day. `qoder-credits-parts.json` keeps its earlier figures.
