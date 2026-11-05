# Xiaomi Coding Plan

Xiaomi's MiMo open platform, read through the console's own account routes.

**Nothing here is a runtime test against a live account.** The routes, the envelope and the cookie names were read off [CodexBar](https://github.com/steipete/CodexBar)'s own implementation and its `docs/mimo.md`, which is where this provider came from; the parsing is pinned by fixtures written to that contract, not captured from a real reply. A live account will settle the parts marked below.

## Place in Pulse

- `Provider.xiaomiMiMo`. Icon `xiaomimimo`. Extra accounts: no. Transcripts: no. Spending history: no.
- First run: offered unchecked in the chooser, with no detected hint. A browser on this Mac is no evidence of an account. After choosing it, import a session in Settings. It participates in the enabled-account refresh pass, including the first pass after selection.
- `usesAPIKey` is true so Settings draws a credential row; `usesSessionCookie` is true so that row is a **browser session** rather than an API-key paste. The second one is the point: the platform *does* issue API keys, and they buy inference. None of them answers the console routes below.
- Service: [`XiaomiMiMoUsageService.swift`](../../Sources/Pulse/Providers/XiaomiMiMoUsageService.swift). Tests: `XiaomiMiMoTests`, fixtures `Tests/PulseTests/Fixtures/xiaomi-*.json`.

## The name

**"Xiaomi Coding Plan", not "Xiaomi MiMo".** The platform sells two different things on one account: inference by the yuan to anyone with a key, and a monthly token allowance bought on top of that. Only the second has a denominator, so only the second can be a ring — and naming the row for the platform would have it stand for both. CodexBar calls its equivalent "Xiaomi MiMo" because it leads with the balance; this one leads with the plan.

It is eighteen characters, four past "GitHub Copilot", which is what the Settings sidebar was previously sized to; "Alibaba Coding Plan" is now the longest. See [`../ui/settings.md`](../ui/settings.md).

## One row, not two

**Asked and answered: this is not another MiniMax.** z.ai / Zhipu are split into a mainland row and an international one, and MiniMax into two sites under one provider, because those really are two storefronts: separate accounts, separate keys, and a key for one refused by the other. That split cost a real bug before it existed (issue #13, an international subscriber's key sent to the mainland service), so the question is worth asking of every Chinese provider added since.

Xiaomi is one storefront:

- The official documentation at `mimo.xiaomi.com`, in **both** its English and its Chinese edition, points the Token Plan at the same `platform.xiaomimimo.com/token-plan`. There is no second console and no region selector.
- No sibling console host resolves — `platform-sgp.xiaomimimo.com` and a bare `xiaomimimo.com` do not connect at all.
- CodexBar's own provider carries one host and no region handling.

`token-plan-cn.xiaomimimo.com` and `token-plan-sgp.xiaomimimo.com` both **do** resolve, which is what prompts the question. They are **inference** endpoints — the base URL a CLI wrapper points at, which is how CodexBar's local-usage fallback uses the `sgp` one — not consoles and not account boundaries. One account reaching whichever is nearer is the opposite of the MiniMax case.

Not verified: whether signing up from outside mainland China lands on this same console. Two editions of the vendor's own documentation serving one URL is the evidence there is. If an overseas account turns out to have its own console, this is the page that was wrong, and the remedy is the second row rather than a region switch inside one — see the reasoning under `Provider.displayName` for why.

## Credential

A browser session for `platform.xiaomimimo.com`, read by [`BrowserCookies`](../../Sources/Pulse/Auth/BrowserCookies.swift) or pasted as a `Cookie:` header — the same two ways in as Ollama's; Qoder and StepFun use them too.

`XiaomiMiMoCookie` keeps **only** these names and discards the rest of the store:

| Cookie | |
|---|---|
| `api-platform_serviceToken` | required |
| `userId` | required |
| `api-platform_ph` | sent when present |
| `api-platform_slh` | sent when present |

Both required names or the header is refused before a request is made. Everything else a browser holds for that host — analytics, preferences, whatever the site adds next — never leaves the process. Values are checked rather than trusted: a control character anywhere in the header is refused outright, because a value carrying a newline is a header injection.

A repeated name takes the first and is **not** an error. Every browser store routinely holds a host-only row and a domain row for one cookie, and the host match returns both; throwing there discarded the whole browser in silence. That lesson is Ollama's, written down in `OllamaSessionCookie.normalize` and repeated here because the shape of the mistake is the shape of this whole feature.

Safari's store needs Full Disk Access; the Chromium browsers ask for keychain permission once. Both are properties of reading a browser, not of this provider — [authentication.md](authentication.md).

## Routes

`GET https://platform.xiaomimimo.com/api/v1/…`, three of them, fetched together:

| Path | Carries |
|---|---|
| `tokenPlan/usage` | `data.monthUsage.items[]` — `used`, `limit` per bucket |
| `tokenPlan/detail` | `data.planCode`, `data.currentPeriodEnd`, `data.expired` |
| `balance` | `data.balance` and `data.currency`, as strings |

**The plan's failure is the call's failure; beside a plan, the balance's is one line on the card.** The ring comes from `tokenPlan/usage`, so a usage route that does not answer is an unavailable provider. The balance is money on the card and nothing else depends on it, so losing it costs that line. `tokenPlan/detail` is in between: it carries the reset and the plan's name, and without it the row still draws with neither.

`monthUsage.items` is a list because the console draws a row per bucket. The plan's own allowance is the first, and an **empty list is an account with no plan** — one that buys tokens by the yuan. Never drawn as 0%, which would read as a full month nobody has.

**An account with no plan is read as its balance** (#82, `XiaomiMiMoUsageService.reading(from:)`). Such an account has money and no allowance, which is what an API account is, so it gets an API account's ring: a live reading with no windows and `creditRemaining` set, which `UsageStore.ringed` gives the `BalanceRing` basis chosen in Settings (balance only, since the last top-up, or a budget; [deepseek.md](deepseek.md)), with the money on the rail until there is a denominator. The pane offers the basis and the "warn below" line for it, as for any account whose reading is a balance (`AccountEntryFields.reportsBalance`). Only with neither a plan nor a balance is it `.xiaomiNoCodingPlan`, still a complete answer rather than a fault; `zaiNoCodingPlan` exists for the same reason.

**Only a stated "no plan" counts** (`XiaomiMiMoClient.saysNoPlan`): a usage reply with code 0 and no allowance in it, or a plan the detail route calls expired. A usage route that did not answer, answered with a non-zero code, or did not decode is the call's failure — otherwise a usage route timing out beside a balance that answered would turn a Coding Plan subscriber into a pay-as-you-go account for a refresh.

An `expired` plan keeps reporting last month's figures until it renews. Those are not a current allowance, so nothing is drawn.

## The envelope answers inside a 200

Every route returns `{ "code": …, "message": …, "data": … }` over **HTTP 200**, including when the session is refused: `code` 401 or 403 in the body with a 200 on the wire. So the body is read on every route, not just on the one that failed — read as a success, a refused session comes out as "no Coding Plan on this account", which sends somebody to look at their subscription instead of at their login.

This is the same shape that had Zhipu reporting "the service returned an error" for the commonest mistake there is; see [zai.md](zai.md).

**Every route's outcome is kept, not discarded.** The first version wrapped all three calls in `try?`, which made the whole status-code switch below unreachable: an HTTP 401, a 429 and a 500 all became three nils and came out as "the reply could not be read". Each route now returns a `Result`, and when none of them answers the most actionable failure wins — a refused session outranks a timeout, because that is the one with a remedy. A transport failure is `.unreachable`, not `.unreadableReply`; the second means something came back.

The envelope is checked on **both** plan routes as well as on the balance, for the same reason. Read without it, a `code` 500 carrying an empty `items` came out as `.xiaomiNoCodingPlan` — a server fault reported as a subscription, and one `UsageAlerts` would then treat as an answer that clears an outage.

On the wire, `3xx` and `401`/`403` are all read as an expired session — an expired login is answered by redirecting the API call at the sign-in flow, so a redirect here is a credential problem rather than a moved endpoint.

## What the rail is told

One window, `kind: .monthly`, `id` `xiaomi.plan`.

`windowSeconds` is thirty days and **`reportsLength` is false**. The platform states when the period ends and never how long it is, and a billing month is not a fixed number of seconds — so the length is a sort key, the window-clock arc is not drawn, and the forecast does not divide by it. Copilot's calendar month is carried the same way; see the `windowSeconds` section of [README.md](README.md).

Beside a plan, the balance rides along as `creditBalance`, a formatted string, **not `creditRemaining`**: the plan is the ring, and the balance there is what is spent past it, so no "warn below" line is offered. Without a plan the balance is the reading itself and carries `creditRemaining` (above). `reportsSpendableBalance` stays false for the provider either way; the pane asks the reading.

## Unconfirmed

- **The bucket.** `monthUsage.items.first` is taken as the plan's allowance. On an account whose console shows several buckets, the first may not be the one the plan is sold as.
- **The currency.** `balance.currency` is fed to `NumberFormatter` as an ISO code. If the platform returns `¥` or `RMB` rather than `CNY`, the card prints the number with no symbol.
- **`planCode`.** Shown as the plan's name. Whether it is a human-readable name or an internal code is not known from the contract.
