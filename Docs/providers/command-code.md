# Command Code

Service: [`CommandCodeUsageService.swift`](../../Sources/Pulse/Providers/CommandCodeUsageService.swift).

Command Code is a terminal coding agent published by CommandCodeAI. It is installed from npm as [`command-code`](https://www.npmjs.com/package/command-code) and its binaries are `cmd`, `cmdc`, `command-code` and `commandcode`. Docs and account live at [commandcode.ai](https://commandcode.ai); the GitHub repository ([CommandCodeAI/command-code](https://github.com/CommandCodeAI/command-code)) carries a readme and issue templates only — the CLI itself ships as a bundle, not as source.

The ring is named for the product. Its command is `cmd`, which names nothing on a rail of brands and collides with the modifier key on every Mac keyboard.

**Command Code bills money, not tokens.** The account holds a credit balance in US dollars, and rolling usage windows and per-organisation spend limits sit on top of it. That is why its windows are mostly `.spend`.

## Not verified against a live account

**Nobody on this side holds a Command Code account.** The routes and field names below were read out of the shipping client — `command-code@1.51.3`, `dist/cli.mjs`, the same code the CLI's own `/usage` overlay runs — rather than captured from a real reply. That is the same standing [volcengine.md](volcengine.md) has, and it is why:

- the parsing is pinned by fixtures (`Tests/PulseTests/Fixtures/command-code-*.json`), so a schema change is a failing test rather than a wrong number;
- every reading is built only from figures the reply carries, and the one inferred denominator — the plan grant — is labelled as such on screen. See [The monthly row](#the-monthly-row-a-plans-grant-or-a-pay-as-you-go-pool).

What *is* verified: the host and the route answer. `GET https://api.commandcode.ai/alpha/whoami?limits=1` without a credential returns `401` and

```json
{"success":false,"error":{"code":"UNAUTHORIZED","status":401,
 "message":"Invalid 'Authorization' header or token.",
 "docs":"https://commandcode.ai/docs/reference/errors/unauthorized"}}
```

so the address is real and the bearer check is real. Nothing here claims a reading was taken from a signed-in account. **Replace the fixtures with a real capture** the first time somebody with an account can produce one, and delete this section when they have.

## Credential

Two places, in this order — the same arrangement as [opencode-go.md](opencode-go.md), and for the same reason:

1. **A key pasted into Settings**, kept encrypted on this Mac. It wins: somebody who typed a key meant that one, and a stale login left behind by the CLI must not quietly override a deliberate choice.
2. **`~/.commandcode/auth.json`**, written by `cmd auth login`. Plain JSON, owner-only (`0600`):

```json
{"apiKey": "…", "userId": "…", "userName": "…",
 "keyName": "…", "authenticatedAt": "…"}
```

Only `apiKey` is read. The CLI also writes `auth.staging.json` and `auth.local.json` when it is pointed at the vendor's staging or a developer's laptop; neither is a credential for the service Pulse reports on, and neither is read.

**`COMMAND_CODE_API_KEY` is deliberately not read.** The CLI honours it, but Pulse is a launched app and does not inherit the user's shell environment — looking would find nothing on the machines where it is set, and would only add a way to be confusing about it.

## First-run evidence: the key, not the directory

`canReportWithoutSetup` and `installedOnThisMac()` both test for the **stored key**, never for `~/.commandcode`.

The directory is not evidence. The CLI creates it to unpack its bundled skills into, on a machine where nobody has signed in — this repository's own development Mac has a `~/.commandcode` holding nothing but `skills/`. Gating on the directory would switch the ring on at the next update for everyone who ever ran `cmd` once, and they would get a grey ring asking for a key to a service they have no account with. That is exactly the greyed-out rail the offer-once rule exists to prevent.

## Route

Four undocumented account routes on `https://api.commandcode.ai`, each carrying `Authorization: Bearer <apiKey>`. These are the four the CLI's own usage overlay reads, in the same order:

| Call | Purpose |
|---|---|
| `GET /alpha/whoami?limits=1` | The organisation id the other three are scoped by, and `orgLimits[]` |
| `GET /alpha/billing/credits?orgId=…` | The remaining credit, and the rolling window limits |
| `GET /alpha/billing/subscriptions?orgId=…` | The plan and the billing period |
| `GET /alpha/usage/summary?orgId=…&since=…` | What has been spent inside that period |

`whoami` runs first and alone: it is the cheapest call, it is what says whether the key is any good, and its organisation id scopes the rest. A failure there ends the fetch rather than firing three more requests with a credential already known to be bad. `credits` and `subscriptions` then run side by side, and `summary` last because its `since` is the subscription's period start.

**`orgId` is optional** — the CLI omits the parameter when `whoami` did not answer, and so does Pulse. **`since` is passed through verbatim**: it is a query parameter to the service that produced it, not a date this side has any business reformatting.

Losing `credits` is losing the answer, so its failure is reported. Losing `subscriptions` or `summary` is not: a pay-as-you-go balance with no subscription is a complete answer, and the billing period simply goes unstated.

None of this is documented by the vendor. It can change without notice, exactly like the undocumented routes the other agents here are read from.

### Shapes

```
/alpha/whoami?limits=1
  { "org": {"id": …, "login": …}, "user": {"userName": …},
    "orgLimits": [ {"scope": "model" | …, "model": …, "modelLabel": …,
                    "spent": <USD>, "limit": <USD>, "exceeded": <bool>,
                    "resetInterval": "daily"|"weekly"|"monthly"|"total",
                    "resetAt": <ISO>} ] }

/alpha/billing/credits
  { "credits": {"planId": …, "monthlyCredits": <USD remaining>,
                "purchasedCredits": <USD remaining>, "freeCredits": <USD remaining>},
    "windowLimits": {"limited": <bool>,
                     "fiveHour": {"used": <USD>, "cap": <USD>, "resetAt": <epoch ms>},
                     "weekly":   {"used": <USD>, "cap": <USD>, "resetAt": <epoch ms>}} }

/alpha/billing/subscriptions
  { "data": {"planId": …, "status": "active" | …,
             "currentPeriodStart": <ISO or epoch>, "currentPeriodEnd": <ISO or epoch>} }

/alpha/usage/summary
  { "totalCost": <USD spent>, "totalCount": <requests>, "totalTokensSaved": … }
```

**Only `subscriptions` nests.** The other three put their fields at the top level; the subscription arrives under `data`. Getting that backwards reads every field as absent, which looks like an account with no plan rather than a parsing bug.

## Windows

| Id | Kind | Source | `reportsLength` |
|---|---|---|---|
| `five-hour` | `.fiveHour` | `windowLimits.fiveHour` | yes |
| `weekly` | `.weekly` | `windowLimits.weekly` | yes |
| `org.<scope>.<model?>.<interval?>` | `.spend` | `whoami.orgLimits[]` | daily and weekly yes; monthly no |
| `monthly` | `.monthly` | the plan's grant, flagged **`estimated`** | only when the period states both ends |
| `credits` | `.spend` | the purchased pool | only when the period states both ends |

The last two are **mutually exclusive**: a running plan produces `monthly`, an account without one produces `credits`, and a plan that cannot be sized produces neither.

Shortest first. **Ties keep the order they were built in** — `sorted(by:)` is not a stable sort, and this provider produces equal lengths as a matter of course: a weekly rolling limit beside a weekly org limit, a monthly org limit beside a billing period that happens to be thirty days. Left to `sorted` those rows could swap between one refresh and the next, which is the shuffling `headlineWindow`'s own tie rule exists to avoid.

### The monthly row: a plan's grant, or a pay-as-you-go pool

**Command Code sells subscription coding plans**, and the monthly row answers a different question depending on whether one is running. The lineup, as `command-code@1.51.3` knows it:

| `planId` | Monthly grant | The vendor's own name for it |
|---|---|---|
| `individual-go` | $10 | Go |
| `individual-provider` | $15 | Provider |
| `individual-pro` | $30 | Pro |
| `individual-pro-v1` | $80 | Pro |
| `teams-pro` | $40 | Teams Pro |
| `individual-goat` | $70 | GOAT |
| `individual-max` | $150 | Max |
| `individual-ultra` | $300 | Ultra |

The third column is **not what Pulse shows** — it is the CLI's own display table, recorded here only because it is what the grants are advertised under. Pulse tidies the id instead ("Individual Pro", "Individual Goat"), for the reason under [Plan and balance](#plan-and-balance): a name table blanks every tier added after this build, and an unfamiliar name beats none. Note also that two different grants share the name "Pro", which is why nothing here may be reasoned about from the name.

**No reply reports any of those numbers.** `credits.monthlyCredits` is the grant's *remainder*; its size is published on the pricing page. The vendor's own CLI carries this table for that reason, and so does CodexBar. Pulse carries it in [`CommandCodePlans`](../../Sources/Pulse/Providers/CommandCodePlans.swift), deliberately in its own file, because it is the one thing here that goes stale on someone else's schedule.

So this is the **second labelled exception** to "Pulse does not invent a percentage", alongside the money estimate. What that costs is bounded in three ways, and the bounds are the design:

- **The numerator is reported.** `grant - monthlyCredits` subtracts the account's own figure; only the denominator is inferred.
- **The row carries `isEstimated`**, so the card reads "Monthly limit · estimated" rather than passing for a reported limit. A flag and not a `scope`: [json-output.md](../json-output.md) promises `scope` is a product name that is the same in every language, and this marker's wording is translated. `--json` exposes it as `estimated`.
- **A plan this build cannot size draws nothing at all.** Not zero, not the pool. A missing row is this design's real failure mode and it is silent, so it must not be able to render as an untouched allowance for someone whose money is gone. CodexBar's table is missing `teams-pro` and `individual-provider` today, and its unsized plans fall through to a free-tier branch that draws exactly that.

Matching is on the **whole** id, lowercased, with `_` folded to `-`. The CLI matches on a *prefix*, which would size a future `individual-pro-v2` as the $30 `individual-pro`; being wrong by $50 is worse here than saying nothing.

**Adding the three credit buckets together instead was the first attempt, and it is worse than saying nothing.** The grant resets and purchased credit does not, so a Pro subscriber holding $200 of top-up who has burnt $28 of a $30 month read as **12%** — silence, and then a wall.

#### Which question is being answered

`isOnAPlan` decides, and it does not simply read the subscription's status:

- **Subscription answered** → on a plan iff `status == "active"`. Cancelled, past due, trialing and lapsed are all off it.
- **Subscription answered `data: null`** → *not* on a plan, and taken at its word however much a stale `planId` in the credits reply still names one. This is a different answer from no answer at all, and collapsing the two drew a pay-as-you-go account against a $30 grant it does not receive while hiding the purchased credit it actually holds.
- **Subscription did not answer** → on a plan iff a `planId` is named, which `credits` carries as well as `subscriptions`. That call is allowed to fail without sinking the reading, so its silence is not evidence of no plan; reading it as one would answer with the pool, which is the wrong question *and* the wrong number.
- **Answered with a plan but no `status`** → treated as running. The reply's shape has moved, and of the two ways to be wrong, a row this build cannot size draws nothing while the other passes the pooled balance off as a plan.

### Off a plan, the pool is the account's own arithmetic

An account with no plan running is on what it has actually purchased — and *that* pool has both halves reported. This is also the CLI's own fallback whenever it has no table entry to reach for:

```
remaining = max(0, monthlyCredits) + max(0, purchasedCredits) + max(0, freeCredits)
spent     = max(0, summary.totalCost)
pool      = remaining + spent
used      = spent / pool
```

`remaining` is the only figure here that arrives as **what is left**; it is turned into a pool rather than inverted, so nothing downstream inverts it twice.

**Both halves must actually have been reported, and absent is not zero.** There is no window unless at least one credit pot is present *and* the summary answered. Reading absence as zero is wrong in both directions, and one of them is loud:

- Every pot absent — the shape a renamed field produces on an undocumented route — totals nothing left, puts the whole pool in the numerator, and draws a **full red ring with `isExhausted`**, which `UsageAlerts` then announces as a limit that is spent, about an account that said nothing.
- The summary call failing — it is allowed to, quietly — puts zero in the numerator and draws an **untouched ring** for an account that may be at the wall. `CommandCodePlans` argues that case at length for the plan grant; it is no different here.

Where `pool` is zero there is likewise no window — an account that has said nothing about a pool is not the same as one that is empty.

`isExhausted` is `remaining <= 0`: the balance is the account's own statement of what is left, and nothing left is spent whatever the percentage rounds to.

The billing period is a **stated length only where the reply gave both ends of it** — a lapsed plan still states them, which is why the off-plan pool usually has a real length. With no subscription at all, thirty days is a sort key and nothing divides by it. Both boundaries are accepted as either a date string or an epoch number, because the CLI hands both straight to JavaScript's `Date`, which takes either without saying which it got.

### Window limits

`windowLimits.limited` is the account's own statement that these windows are in force, and the CLI draws them only when it is set. A cap reported for an account that is not window-limited is not a limit anybody is being held to, so it is not drawn as one here either.

`resetAt` on these two is **epoch milliseconds** — the CLI subtracts it from `Date.now()` — not the ISO strings `orgLimits` uses. Reading one as the other puts the reset in 1970 or in the year 56000.

`reportsLength` is true because the reply *names* the lengths: the fields are `fiveHour` and `weekly`. Whether either window rolls rather than sitting on a fixed boundary **has not been established from a live account**; if a capture ever shows it does, this is the flag that has to change, exactly as it did for Kimi's rolling week.

### Organisation spend limits

`spent` and `limit` are dollars and arrive **already counted as spent** — no inversion, unlike [antigravity.md](antigravity.md).

- `exceeded` is the account's own verdict and outranks the arithmetic: a limit half used that the account says is done is reported as spent. Erring towards "you are blocked" is the safer mistake.
- **A ceiling of zero or less draws no row.** It was treated as a limit already reached, on the reasoning that a limit with no room in it is full. That is a guess about an encoding nobody here has seen: `-1` is the usual way to say *unlimited*, and reading it as "reached" paints an untouched organisation solid red and has the alerts announce a limit as spent that the account never reported.
- A row with no `limit` is **dropped**. There is no denominator to build a fraction from, and a spend limit drawn at an invented ceiling is worse than one not drawn.
- `scope: "model"` names its model (`modelLabel`, else `model`); anything else is the organisation as a whole and is left unscoped, because a row reading "Spend limit · Org-wide" says nothing the heading does not already say.
- Ids are built from **what the limit is** — scope, model, reset interval — so `org.model.anthropic/claude-opus-5.daily` stays that row whatever order the array arrives in. `UsageWindow.id` is documented as stable across refreshes and a pin is resolved by it, so positional ids silently moved a pin from one model's limit to another's and swapped two rows' identity mid-animation. Two limits alike in all three fields are indistinguishable in the reply as well, and only those fall back to the order they arrived in.

`resetInterval` becomes a length: `daily` and `weekly` are exact and are stated; `monthly` is 28 to 31 days stored as a flat 30, the same stand-in Cursor's billing cycle and Copilot's calendar month use, and it must not feed the window clock or the forecast; `total` is a lifetime cap with no period at all.

## Plan and balance

`plan` is the plan id **tidied, not mapped** — `individual-pro` becomes "Individual Pro". The CLI's own table of display names is a table in a client, so a tier added after this build would be blanked by it, and an unfamiliar name still beats none.

`creditBalance` is the three pots added up, formatted in US dollars — the currency the service prices in, whatever the reader's own is.

## Not offered

- **No extra accounts.** `supportsMultipleAccounts` is unchanged; there is no second login to add. See [authentication.md](authentication.md).
- **No route choice.** One route, and it needs a credential, so `soleRoute` is nil and Settings states nothing.
- **No history and no transcripts.** Command Code keeps sessions under `~/.commandcode/sessions`, not the JSONL the ledger reads, so `keepsLocalTranscripts` and `providesHistory` are both false — the same position OpenCode Go is in.
