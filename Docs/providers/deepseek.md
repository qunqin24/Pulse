# DeepSeek

| `Provider` | Ring name | Host | Icon |
|---|---|---|---|
| `.deepSeek` | DeepSeek | `https://api.deepseek.com` | `deepseek` |

Service: [`../../Sources/Pulse/Providers/DeepSeekUsageService.swift`](../../Sources/Pulse/Providers/DeepSeekUsageService.swift). The denominator modes and the watched mark: [`../../Sources/Pulse/Providers/DeepSeekBalanceBasis.swift`](../../Sources/Pulse/Providers/DeepSeekBalanceBasis.swift).

## Verified against a live account

Unlike [command-code.md](command-code.md), this one was. `GET /user/balance` was called with a real key on 2026-09-10 and answered `200` with exactly the documented body; a deliberately wrong key answered `401`. The service was then run end to end through all three modes against that account and its readings checked. The fixtures under `Tests/PulseTests/Fixtures/deepseek-*.json` are written to that confirmed shape rather than containing anybody's balance.

## The route

One route, and it is **documented** — it sits in DeepSeek's own API reference beside chat completions, not in the undocumented account endpoints most of this directory reads.

```
GET https://api.deepseek.com/user/balance
Authorization: Bearer <key>
```

```json
{ "is_available": true,
  "balance_infos": [ { "currency": "CNY", "total_balance": "110.00",
                       "granted_balance": "10.00",
                       "topped_up_balance": "100.00" } ] }
```

Status handling is the ordinary one: `401`/`403` → `.apiKeyRefused`, `429` → `.rateLimited`, anything else → `.serverError`.

**Every figure is a string, including the money.** Parsed at the boundary so nothing downstream knows. A field that is absent or unparseable is **absent, not zero** — the rule the rest of this directory learned the hard way, and it bites hardest here: a balance read as zero is a full red ring and a notification announcing an account as spent.

## Credential

A key pasted into Settings, kept encrypted on this Mac by `APIKeyStore`. There is nothing to borrow — DeepSeek's key lives on its web console and no CLI on this Mac stores one — so `canReportWithoutSetup` is false and the provider stays off until a key is entered.

## There is no allowance, so the ring has no denominator

**This is the first provider Pulse carries that reports no percentage at all.** The reply says how much money is left and stops. There is no quota, no window, no reset, and no spend-history endpoint anywhere in the API. Every other provider reports at least one fraction.

A ring needs a denominator, and there are exactly three places one can come from — which is why `DeepSeekBasis` has exactly three cases and the user picks between them in DeepSeek's settings pane.

| Mode | Denominator | Ring |
|---|---|---|
| `sinceTopUp` **(default)** | The highest balance Pulse has watched | `(peak − balance) / peak` |
| `balanceOnly` | None | No window; the rail draws the money |
| `budget` | A figure the reader typed | `(budget − balance) / budget` |

Both fractions carry a `UsageWindow.Estimate` naming where the number came from — `sinceTopUp` or `yourBudget` — which the card renders after the name ("余额 · 自上次充值") and `--json` reports as the stable token `estimatedFrom`.

**Not `scope`.** That was the first attempt and it shipped wrong for an afternoon: `scope` is a product name and [../json-output.md](../json-output.md) promises it reads the same in every language, so a localized "since top-up" in it broke any script matching on it the moment the reader switched language. The same trap `.localized` in a contract field is always going to be.

### `sinceTopUp` is measured, not inferred

This is the whole reason it is the default. Pulse reads the balance every refresh — 2 to 30 minutes — and remembers the highest it has seen. **A balance that goes up can only be a top-up**, so that resets the mark and the ring starts from full again. Nothing here is a guess about DeepSeek's pricing, a table of plans, or a number anyone typed. Contrast [command-code.md](command-code.md), where the plan grant genuinely is a table in a client.

What it costs is the first run: a Mac that has never watched this account has no mark, so the first reading becomes one and the ring reads 0% until money is actually spent. That is a true statement about what Pulse has seen. A peak of zero draws no window at all — an account that has never had credit is not one that has spent it.

### "No fraction" is not "no reading"

Three separate places read `usedFraction == nil` (or `headline == nil`) as *nothing came back*, which was sound while every provider reported a percentage. On `balanceOnly` all three were wrong about a perfectly good reading, and each had to be pointed at whether there is a reading rather than whether there is a fraction:

- `UsageCache.reconciled` threw the reading away and handed back the previous one, so the setting appeared to do nothing.
- The hover card drew a bubble with only the provider's name in it.
- The rail drew the icon and the figure at 35% and 40% opacity — the dimming that means "Pulse has no data for this one".

`UsageRingView` now takes `hasReading` rather than inferring it, and the rail's label dims only when it has neither a percentage nor a figure.

### The card shows the money

`balanceOnly` produces a reading whose body is nothing but a balance, and the card's body is otherwise limits, an unavailability message and a footnote — so hovering it drew a bubble with only the provider's name in it, which reads as a card that failed to load. Where a provider reports money and no allowance the money *is* the reading, so the card says it as a plain figure. No bar: a bar at zero beside a healthy balance reads as an empty account. No explanatory line either — it said the provider reports no limit, which the card has already made obvious by having nothing else on it.

### A reading with no windows is still a reading

`balanceOnly` is the first **complete** answer Pulse has ever produced with no windows in it. `UsageCache.reconciled` tested `!windows.isEmpty` to mean "this fetch went wrong" — a fair assumption while every service with nothing to report returned `.noLimitsReported` — so it kept handing back the previous reading and switching the setting appeared to do nothing at all. The test is now `ProviderUsage.reportsSomething`: a balance is an answer. A reading carrying neither windows nor a balance is still a failure to fall back from, and `UsageCacheTests` pins both halves.

Marks live in `deepseek-baseline.json` in Pulse's Application Support folder, **one per currency**, written off the main thread on a serial queue — the same arrangement `UsageAlerts` writes its memory with, and for the same reason: this is written on every pass. The mark is advanced on every reading whichever mode is in force, so switching to `sinceTopUp` later finds a peak already there rather than starting over from whatever the balance happens to be that afternoon.

### `budget` is the reader's own line

Blank, zero or negative leaves the mode with no denominator, which draws the balance alone rather than a fraction of a number nobody gave. A balance above the budget is **0% used**, not a negative fraction.

## `is_available` is the only thing that may say "spent"

DeepSeek's own flag for "this balance can no longer pay for a call". Nothing else sets `isExhausted` — in particular a generous budget can put the ring near the top while the account is perfectly able to pay, and that is the reader's line rather than DeepSeek's verdict. [../notifications.md](../notifications.md)

## `kind` is `.balance`, not `.spend`

Prepaid credit is **not a limit**: there is no ceiling to reach and no window to turn over. `.spend` made the row read "Spend limit", which put the word *limit* on something that has none. `reportsLength` is false and `resetsAt` is nil, always — the seconds exist only to sort the row. `--json` reports the kind as `balance`.

## Currencies

`balance_infos` is an **array** and an account can hold both CNY and USD. They cannot be added, and Pulse will not pick a "main" one by comparing figures across currencies — ¥100 against $10 is not a comparison. The ring follows the reader's choice if they made one, else the first entry with money in it, else the first entry at all. `creditBalance` is formatted in the currency the purse is actually priced in, not the reader's locale.
