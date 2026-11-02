# New API

| `Provider` | Ring name | Host | Icon |
|---|---|---|---|
| `.newAPI` | New API | **whatever the reader types** | `newapi` |

Service: [`../../Sources/Pulse/Providers/NewAPIUsageService.swift`](../../Sources/Pulse/Providers/NewAPIUsageService.swift). Address rules, shared with [sub2api.md](sub2api.md): [`../../Sources/Pulse/Providers/GatewayAddress.swift`](../../Sources/Pulse/Providers/GatewayAddress.swift).

[New API](https://github.com/QuantumNous/new-api) is the gateway most self-run relays are actually built on — a fork line going back to one-api — so this is the broadest single thing Pulse can read in this class. The credential is the ordinary `sk-` key already in the reader's AI client; there is no second one to go and find.

**Upstream terms are the operator's business.** Pulse reads accounting from a deployment the reader already has a key for and takes no view on how that deployment got its capacity.

## Not verified against a live deployment

No New API instance was run for this. Everything below is read off the project's own source at `QuantumNous/new-api` — `router/dashboard.go`, `controller/billing.go`, `controller/misc.go`, `setting/operation_setting/general_setting.go` — and the fixtures under `Tests/PulseTests/Fixtures/newapi-*.json` are written to those shapes. Nothing here claims a runtime test.

## Three routes, run together

```
GET {root}/v1/dashboard/billing/subscription    Authorization: Bearer sk-…
GET {root}/v1/dashboard/billing/usage           Authorization: Bearer sk-…
GET {root}/api/status                           (no credential)
```

```json
{ "object": "billing_subscription", "has_payment_method": true,
  "soft_limit_usd": 25.5, "hard_limit_usd": 25.5,
  "system_hard_limit_usd": 25.5, "access_until": 0 }

{ "object": "list", "total_usage": 1234.5 }

{ "success": true, "data": { "quota_display_type": "USD",
                             "display_in_currency": true,
                             "system_name": "Example Relay" } }
```

The first two are OpenAI's own billing paths, which is the whole reason this is readable: New API implements them for compatibility, and `middleware.TokenAuth` accepts the relay key. `401` on a bad key, so status handling is ordinary. The third is the site's public configuration — nothing in it is account-scoped, so it is **not** given the key.

Three concurrent requests every 2–5 minutes (New API is unwatched, so `AdaptiveRefresh.unwatchedCeiling` caps the interval). The status route is asked every pass rather than cached, so an operator changing the display setting is picked up rather than remembered wrongly.

## Neither figure means what its name says

| Field | Name suggests | Actually |
|---|---|---|
| `hard_limit_usd` | a ceiling | `remaining + used` — everything the key has ever had |
| `total_usage` | an amount | the amount **times a hundred** (OpenAI reported cents) |
| `*_usd` | dollars | whatever unit the operator set |

So:

```
remaining = hard_limit_usd − total_usage / 100
```

Both sides are New API's own numbers, so the subtraction is arithmetic on reported figures rather than an inference. **The factor of a hundred is the trap**: read as units, a wallet with $13 left comes out at −$1,209, which is a full red ring and a notification announcing an account as spent. `NewAPIParsingTests` pins it.

## No percentage is drawn

`used / (remaining + used)` looks like a ring and is not one, because that denominator is two unrelated things depending on a **server** setting that appears nowhere in the reply — `DisplayTokenStatEnabled`:

- **on** — the figures are the key's own. A key sold with a quota really does have that allowance, and the fraction would be exactly right.
- **off** — the figures are the *account's*, and `used` is lifetime. Somebody who has spent $900 over a year and just topped up $100 would be drawn at 90% spent with a full wallet, and every top-up would grow the denominator.

One reply, two meanings, no way to tell them apart. So the service itself draws the money and no fraction (`windows: []`). Any ring on the rail is `BalanceRing`'s, from a denominator Pulse watched or the reader typed, never from this reply — the same as a [sub2api](sub2api.md) wallet; with **Balance only** the rail shows just the balance ([deepseek.md](deepseek.md), [README.md](README.md#subscriptions-and-api-accounts)). See also [`README.md`](README.md#pulse-does-not-invent-a-percentage).

## The unit is not in the reply either

New API converts the amount into whatever its operator chose and keeps OpenAI's field name, so a CNY site reports yuan in `hard_limit_usd` and a TOKENS site reports a token count. `GET /api/status` carries the answer:

| `quota_display_type` | Pulse reports |
|---|---|
| `USD` | USD |
| `CNY` | CNY |
| `TOKENS` | **no money** — a token count is not a currency |
| `CUSTOM` | **no money** — an operator's own symbol is not an ISO code |
| absent, or anything else | **no money** |

**Nil rather than a default**, in every one of those rows. A display type added upstream that Pulse has not been taught must not be quietly priced in dollars, and a status route that did not answer is "cannot say" rather than "assume USD" — the reading then reports `.noLimitsReported` instead of putting a dollar sign on a number.

Older builds and one-api forks carry `display_in_currency` (a bool) instead. It distinguishes money from tokens and nothing more, so it is read only when `quota_display_type` is absent and can only ever answer USD — which is what the builds that carried it assumed.

## Unlimited keys

`controller/billing.go` substitutes a literal `100000000` for the amount when a key has `UnlimitedQuota` set, rather than setting a flag. So the sentinel is recognised **by value**, and only when all three of `hard_limit_usd`, `soft_limit_usd` and `system_hard_limit_usd` agree — they are written from one variable upstream, so agreement is what separates the sentinel from a deployment that really did sell somebody exactly that much.

An unlimited key reports `.noLimitsReported`, which is the literal truth and classes as `Standing.answered` for alerts. Computing `remaining` against the sentinel would have shown a hundred million of something.

## The address

Same trust boundary as [sub2api.md](sub2api.md), and the same code — `GatewayAddress`. https except on a private network, no user info, no fragment, no query, refused rather than upgraded. What differs is the suffix trimmed off whatever the reader typed: **`/v1`**, because people paste the base URL out of their AI client's config and for an OpenAI-compatible endpoint that is where it ends. Trimming happens before the route is chosen, which is what keeps `/api/status` from landing under `/v1`.

The address is stored per account in `AppSettings.serverAddresses`, keyed by account id like `sources` and `sessionBrowsers`. It was a scalar while sub2api was the only gateway; a second one turned "the address" into "*whose* address", and a shape that cannot hold two is the shape that quietly gives one provider the other's host.

## Credential

The relay's `sk-` key, pasted into Settings and kept encrypted on this Mac by `APIKeyStore`. No discovery hint — a deployment is somebody else's server. The pane asks for the **address first and the key second**, because nothing can be sent anywhere until Pulse knows where.

## The mark

**Not the logo in New API's own web UI.** That one (`web/src/assets/logo.tsx`) is the command-key glyph, which is exactly what Command Code's mark already is — two rings a reader could not tell apart, which is the one thing a rail of logos must not do. The icon here is the project's brand logo (`web/public/logo.png`) reduced to a monochrome outline: two crescents and the spark between them. A reduction, not a trace — the original is a cyan-to-pink gradient and none of that survives a template image.

## Not carried

- **`access_until`.** The key's expiry, 0 for none. There is no subscription-expiry row on the card for any provider yet.
- **`/api/user/self`**, which carries the account's own quota, groups and top-up history. It needs the console's web session, not the relay key — the same wall [deepseek.md](deepseek.md) hit, and the reason `providesHistory` is false.
- **Multiple keys.** `supportsMultipleAccounts` is false. Somebody with keys on three relays wants three rings; the account machinery and the per-account address would both carry it, but nobody has asked.
