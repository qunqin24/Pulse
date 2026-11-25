# sub2api

| `Provider` | Ring name | Host | Icon |
|---|---|---|---|
| `.sub2api` | sub2api | **whatever the reader types** | `sub2api` |

Service: [`../../Sources/Pulse/Providers/Sub2APIUsageService.swift`](../../Sources/Pulse/Providers/Sub2APIUsageService.swift). Address rules, shared with [newapi.md](newapi.md): [`../../Sources/Pulse/Providers/GatewayAddress.swift`](../../Sources/Pulse/Providers/GatewayAddress.swift). Address setting: `AppSettings.serverAddresses`, keyed by account id.

[sub2api](https://github.com/Wei-Shaw/sub2api) is an open-source gateway somebody runs themselves: it fronts their Claude, Codex, Gemini and Grok subscriptions and re-sells them as an OpenAI-shaped API, usually shared among a group. Pulse reads the accounting a group key can see. It never sends a model request through it.

**Upstream terms are the operator's business, not Pulse's.** sub2api's own README warns that using it may breach the upstream providers' terms. Pulse reads usage from a deployment the reader already has a key for and takes no view on that.

## Not verified against a live deployment

No sub2api instance was run for this. The reply shape is taken from the field names in the request that opened [issue #40](https://github.com/qunqin24/Pulse/issues/40) — a real gateway's answer, with the balance figures left in because they are the reporter's own — and cross-read against sub2api's four documented group modes. The fixtures under `Tests/PulseTests/Fixtures/sub2api-*.json` are written to that shape. Nothing here claims a runtime test.

## Why this one and not "a custom provider"

Because it is not custom. The request in issue #40 was for "中转站" in general, and the reply that came with it turned out to name its fields `balance`, `remaining`, `unit`, `isValid` and `planName` — sub2api's, exactly. The class of service has de facto standards, so they get providers like any other product rather than a configuration language.

[New API](newapi.md) is the second, and between them they are most of what people actually run. The shared part turned out to be the **address**, not the reply: `GatewayAddress` is one file, while the two services have no field in common. That is the answer to whether a declarative "fill in a URL and a field path" scheme would have worked — it would have covered the address and none of the rest.

## The route

```
GET {address}/v1/usage
Authorization: Bearer <group key>
```

Status handling is the ordinary one: `401`/`403` → `.apiKeyRefused`, `429` → `.rateLimited`, anything else → `.serverError`. On top of that, **a deployment refuses a key in the body over an HTTP 200** — `"isValid": false` — so that is read as `.apiKeyRefused` too.

## The address is the reader's

Every other provider knows where to go. A self-hosted gateway is told, which means Pulse can be pointed at any host on the internet with a key attached. The rules are therefore a trust boundary rather than a convenience, and they live in [`GatewayAddress`](../../Sources/Pulse/Providers/GatewayAddress.swift) — **shared with [newapi.md](newapi.md)**, because a second copy of a rule like this is a second copy to forget to tighten. What is sub2api's own is the route it ends at and the suffixes a reader may already have typed.

| Rule | Why |
|---|---|
| No scheme typed → **https** assumed | `sub.example.com` is what people paste. The assumption is never http. |
| Plain http refused on a public host | **Refused, not upgraded.** Silently rewriting somebody's address is how a key ends up somewhere they never looked. |
| Plain http allowed on loopback, RFC 1918, IPv4 link-local, IPv6 loopback/unique-local/link-local, and `.local` | A deployment on the reader's own machine or LAN has nothing between it and Pulse to intercept, and demanding a certificate there rules out the ordinary way people run these. |
| User info (`user:pw@host`) refused | A URL whose real host is not the part the eye lands on. |
| Fragment refused | Same trick, written the other way. |
| Query refused | The path Pulse builds is the whole request; a query pasted from a dashboard link would be forwarded with the key. |
| `/v1/usage` appended at most once | People paste the root and people paste the route they tested with curl. Both work; appending blindly makes `/v1/usage/v1/usage`. A path prefix is kept. sub2api trims `/v1` and `/v1/usage`; New API trims `/v1`. |

The check runs on **Save** in Settings, not on every keystroke — `https://s` is not a mistake, it is somebody halfway through a word — and a refusal says what the rule is rather than just colouring the box. It runs again in `fetch()`, which is the copy that cannot be bypassed: a value written before a rule tightened still has to pass.

Two unavailability cases, both naming no provider so the second self-hosted service could share them — which it now does: `.serverAddressMissing` and `.serverAddressRefused`. Both are `Standing.neutral` — nothing was ever asked, so neither is evidence about whether anything can be reached — and both carry the `.editAddress` remedy, which focuses the address field rather than the key field.

## Four shapes through one route

A group key is configured for one of these, and the reply carries whichever it is.

| Shape | Fields | What Pulse draws |
|---|---|---|
| **Wallet** | `balance`, `remaining`, `unit` | Money. **No percentage at all.** |
| **Quota** | `quota { limit, used, remaining, unit }` | One `.spend` window, no length, no reset |
| **Subscription** | `subscription { daily/weekly/monthly _usage_usd, _limit_usd }` | Up to three windows, no length, no reset |
| **Rate limits** | `rate_limits[] { window, limit, used, remaining, reset_at }` | One window each, **with** a length and a reset |

Windows are emitted shortest first.

### A wallet is money, not an allowance

The same rule as [deepseek.md](deepseek.md), reached by the same road: the reply says how much is left and there is no ceiling anywhere in it. So the service reports **no fraction** (no window), exactly as DeepSeek's `balanceOnly` does. Pulse does not invent a denominator. Any ring a wallet gets on the rail is `BalanceRing`'s — a peak Pulse watched or a budget the reader typed, labelled as such, with **Balance only** showing just the money (see [README.md](README.md#subscriptions-and-api-accounts)).

`reportsSpendableBalance` is true, so the wallet gets the "warn me below" field like DeepSeek's and Command Code's. A quota or subscription group reports no wallet and simply never hands one over.

### `remaining` is not always money

Root `remaining` is the wallet's own figure in a wallet group and the remainder *of something else* in the other two. Read as money everywhere, a key with 37.5 of its allowance left would show "$37.50" where a balance goes. So it is read as money only when there is no `quota` and no `subscription` for it to be the remainder of. `balance` is preferred over it wherever both are present.

### A unit that is not a currency reports no money

A deployment selling "credits" or "points" answers with a `unit` that is not an ISO code, and formatting those as dollars puts the wrong name on the figure. Anything that is not three ASCII letters produces no `creditRemaining` at all. A **missing** unit is USD, which is what sub2api's own dashboard assumes.

### Only rate limits have a clock

`rate_limits[].window` is `5h` / `1d` / `7d` — a count and a unit, which is a **statement of the length** — and `reset_at` is a real reset. Those are the only windows here with `reportsLength` true. A label Pulse has no word for (`3h`) is read as `.other(seconds:)` rather than dropped. `m` is **not** read: among hours and days it could be a minute or a month, and as minutes `1m` drew a sixty-second clock. `.other` is named in days only when it is a whole number of them (`36h` is a 36-hour limit, not two days).

The quota and the subscription periods state neither. The subscription reply names daily, weekly and monthly counters and never says when any of them turns over, so their seconds are a sort key and nothing may be divided by them. See [`README.md`](README.md#windowseconds-is-not-evidence-of-a-reported-length).

### Spent comes from the deployment

`isExhausted` is set from the reported `remaining <= 0`, never from the arithmetic. A field that is **absent has said nothing**, and reading silence as zero marks a limit spent that may not be. A limit that is missing, zero or not finite produces **no window** rather than a fraction of a number nobody gave — dividing by zero gives infinity, which clamps to a full ring.

## Credential

A group key pasted into Settings, kept encrypted on this Mac by `APIKeyStore`. There is nothing to borrow: the key is issued by whoever runs the deployment and no tool on this Mac stores one. No discovery hint either — a deployment is somebody else's server and nothing here says it is in use — so the row stays off until it is switched on.

The settings pane asks for the **address first and the key second**, because nothing can be sent anywhere until Pulse knows where.

## More than one deployment or group

People who use relays usually use several ([#125](https://github.com/qunqin24/Pulse/issues/125)), and sub2api issues one key per group. **Add another account** on the sub2api pane adds a ring with its own address, key and name (`addsAccountsByAddress`); nothing is signed in to. Each added account is read by this same service with its own address and key, and every reading is stamped with that account, so a failure on one deployment never lands on another's ring. The first account keeps the provider's own entries, so nothing an existing install stored moves. Storage and removal: [README.md](README.md#extra-accounts).

## Not carried

- **`usage.today` / `usage.total`, `daily_usage[]`, `model_stats[]`.** Real data, and a spending history for this provider is a separate piece of work — `providesHistory` is false. Adding it would mean deciding what a gateway's `cost` means against its `actual_cost`, which is the operator's margin and not a fact about the reader's spending.
- **`expires_at`.** There is no subscription-expiry row on the card for any provider yet.
