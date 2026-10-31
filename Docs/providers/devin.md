# Devin

| `Provider` | Ring name | Routes | Icon |
|---|---|---|---|
| `.devin` | Devin | the app's saved plan · `https://app.devin.ai` | `devin` |

**Two routes.** The endpoint is live and needs a session, which Pulse reads out of a Chromium browser without asking for anything; the saved plan needs nothing at all but is only as fresh as the app's last launch. `.automatic` asks the endpoint when there is a credential and **never crosses to the saved plan if it fails** — the two need not be the same account or organization. The saved plan answers when there is no credential, and the tooling route always answers with it.

Service: [`../../Sources/Pulse/Providers/DevinUsageService.swift`](../../Sources/Pulse/Providers/DevinUsageService.swift).

## The card's "On this Mac" history

Not the same source as the ring. The history is `.agents([.devinCLI, .devinDesktop], slices: [omp → "devin"])`: the CLI's `sessions.db`, the desktop app's `acp-events` records, **plus a slice of Oh My Pi's store** — the records whose transcripts state `provider: "devin"`. On a Mac whose only Devin usage ran through `omp --model devin/…`, neither client has a store to read and the slice is the card's whole history. The provider is the stated backend, so a model routed to Devin's account under another name (`devin/glm-5-3-flash-1m`) still counts; the slice's view cache and the slice rules are in [../ui/panel-geometry.md](../ui/panel-geometry.md#detailed-card).

Devin is Cognition's agent. Its Mac app is the **former Windsurf editor** — `/Applications/Devin.app` still identifies itself as `com.exafunction.windsurf`, and every key it writes is still named `windsurf.*`. That inheritance is the whole route: it is a VS Code fork, so its global state is an ordinary SQLite file, and the plan it last read from the account is one row in it.

## Verified against a live account

**Both routes, on 2026-09-14**, against a Pro subscription on this machine. Devin.app 3.10.23 (Electron 42, `windsurf@3.10.23`). The row was read and the figures were watched moving; the endpoint answered `200` with the body quoted below, out of a session read from Edge's `localStorage`. Every shape on this page came off this Mac rather than out of somebody else's parser — and the two routes agreed: the saved row said 98% and 99% *remaining* while the endpoint said 2% and 1% *used*.

## The saved plan

No credential, no network, no keychain prompt, no Full Disk Access. The file is the user's own, under their own Application Support, and is opened **read-only and in place** — the app may be running and its rollback journal belongs to that process.

```sql
SELECT value FROM ItemTable
 WHERE key LIKE 'windsurf.reactSettings.cachedPlanInfoData%'
```

The key carries the account id: `windsurf.reactSettings.cachedPlanInfoData:user-<32 hex>`. CodexBar's notes name an older key, `windsurf.settings.cachedPlanInfo`; this build has never seen it and it is read as a fallback only.

**The support directory is looked for under two names**, newest first. An Electron app's support directory follows its product name, so a Mac that ran Windsurf before the rename carries `Application Support/Windsurf` and a fresh install carries `Application Support/Devin`.

### Two shapes, because the plans differ

A paid plan reports percentages and sets the message counters to `-1`:

```json
{ "planName": "Pro", "billingStrategy": "quota",
  "dailyRemainingPercent": 98, "weeklyRemainingPercent": 99,
  "dailyResetAtUnix": 1789372800, "weeklyResetAtUnix": 1789891200,
  "hideDailyQuota": false, "hideWeeklyQuota": false,
  "remainingMessages": -1, "totalMessages": -1,
  "overageBalanceMicros": 10000000,
  "startTimestamp": 1789296110000, "endTimestamp": 1791888110000 }
```

A free one reports a message pool instead — captured out of `state.vscdb.backup`, written the moment before this account was upgraded:

```json
{ "planName": "Free", "isDevinFree": true,
  "remainingMessages": 2500, "totalMessages": 2500,
  "duration": 0, "startTimestamp": 0, "endTimestamp": 0 }
```

`-1` is how a paid plan says *not applicable*. Read as a count it draws an allowance of minus one out of minus one, so anything below zero at either end is absent rather than empty.

## What is drawn

| Field | Window | Notes |
|---|---|---|
| `dailyRemainingPercent` | `.daily`, 86,400s | Dropped entirely when `hideDailyQuota` |
| `weeklyRemainingPercent` | `.weekly`, 604,800s | Dropped entirely when `hideWeeklyQuota` |
| `remainingMessages` / `totalMessages` | `.messages` | No window, no reset, `reportsLength` false |
| `overageBalanceMicros` | — | `creditBalance` display string; micros, so 10,000,000 is ten dollars |
| `planName` | — | The card's plan line |

**Nothing here is inferred.** Devin reports both percentages itself and states both resets, so `used = 100 − remaining` and the window clock draws from a length the provider actually gave. Both resets land on a fixed 08:00 UTC boundary.

`.daily` and `.messages` are new `UsageWindow.Kind` cases and exist for the same reason `.monthly` and `.balance` do: the shortest window anyone else reports is five hours and the next is a week, and an allowance counted in messages has no period at all. Filing either under a period nobody stated would put a length on the card that no provider gave.

## The limitation: it is a launch-time snapshot

**The row is written when the app starts, not while it runs.** Measured on 2026-09-14: the account was spent down through the morning and the file sat at 100% throughout, while the web page had already moved; the app was quit and reopened at 09:20:01 and the row changed at 09:20:16, fifteen seconds later. CodexBar's own note on the Windsurf cache says the same thing and it is correct.

So the reading is stamped with **the launch**, not with now. The time comes from `logs/`, where each run creates one directory whose *name* is its start time (`20260914T092003`, in this Mac's zone). The name rather than the directory's modification date, which moves: writing inside an existing file leaves it alone, but a log file created an hour into the session bumps it, and every minute it gains is a minute the card under-reports the age of a reading that has not changed since launch.

That is what puts "as of …" on the card instead of letting a morning-old figure pass for a fresh one, and `UsageCache`'s 24-hour ceiling drops it entirely once a day has gone by without a relaunch.

`DevinUsageService.reading(for:launchedAt:now:)` validates the launch stamp and marks old snapshots. The cache also applies the age and reset limits to directly fetched readings before banking or displaying them:

- Within `snapshotFreshFor` (ten minutes) the row is a **live** reading; past it the reading is `.stale`, which is what the card's "as of …" line is drawn from.
- A window whose reset has already passed is **dropped, not aged**: its figure belongs to a window that no longer exists. The other window — and a balance, which has no reset at all — stays.
- Past `UsageCache.maximumAge` (24 hours) the snapshot is not shown at all. It reads as `.devinPlanUnread`, whose remedy — open the app — is exactly what records a new row.
- A snapshot with **no reliable stamp** — `logs/` missing, or a name that does not parse — is refused the same way rather than dated with the fetch's own clock. The database's modification date is deliberately not used as a fallback: every other key in the file keeps it current, so a reading from breakfast would be drawn as a second old. Undated is not fresh.

A `.stale` saved plan is still **banked** by the cache even though it is not current: it is the last plan the app wrote, and `--json` (which never fetches) reads only the banked figures.

## The endpoint

```
GET https://app.devin.ai/api/<org>/billing/quota/usage
Authorization: Bearer <token>
x-cog-org-id: <internal id>        # only where the organization was given as one
```

The whole reply, measured — 232 bytes:

```json
{ "daily_percentage": 2, "weekly_percentage": 1,
  "daily_reset_at": "2026-09-14T00:00:00-08:00",
  "weekly_reset_at": "2026-09-20T00:00:00-08:00",
  "hide_daily_quota": false, "has_quota_allocation": true,
  "is_quota_plan": true, "overage_balance": 10 }
```

It **names no plan** on this account, so the card's plan line is empty unless the reply carries one — and it is never borrowed from the row the app saved, which names no organization to check against the endpoint's. `has_quota_allocation: false` draws no rings at all: zero percent of nothing is a plan with no quota on it, and two empty rings read as a full allowance.

### The credential is read from the browser

Not from the app: the four `devin_*` keys CodexBar looks for are **not there** in `Application Support/Devin/Local Storage/leveldb` — checked on this Mac. The app authenticates through the Codeium extension's stored session against `server.codeium.com`, a different credential for a different API.

They are in a **Chromium browser's `localStorage`**, which [`ChromiumLocalStorage`](../../Sources/Pulse/Auth/ChromiumLocalStorage.swift) reads. Two keys under `https://app.devin.ai` carry everything the endpoint needs:

```text
auth1_session                                 {"token":"auth1_…","userId":"user-…"}
last-internal-org-for-external-org-v1-<slug>  org-<32 hex>
```

The organization id is **hyphenated** (`org-`), not underscored — which is why both spellings are accepted. The key's suffix is the *external* slug and is often the literal string `null`, so the value is what is read rather than the name. `windsurf.com` is the fallback origin: the same account signed in through the older storefront leaves `devin_auth1_token` and `devin_primary_org_id` there, the same two values under different names.

The session's `userId` is kept as the credential's `accountID`, and the `last-internal-org…` value beside it is the organization the endpoint is scoped to. Together with the route they form the credential's `UsageScope`. A pasted token names no user, so its scope uses a SHA-256 fingerprint of the token together with the organization entered beside it. The token itself is not written into the usage cache.

**Read on every pass, never stored.** A saved copy would be a second place for the session to go stale and the one that cannot renew itself; the browser's copy is by definition the current one, and reading it costs about forty milliseconds. Nothing is written to `keys.dat` for this provider unless the reader pastes something.

**Which browser** is the reader's choice, in Settings, defaulting to the one this Mac opens links with and then the rest. Only Chromium browsers are offered: Firefox and Safari keep no `localStorage` LevelDB, so listing them would be a choice that cannot work. **No keychain prompt** — unlike cookies, `localStorage` is not encrypted.

### Binary storage boundaries

`ChromiumLocalStorage` converts on-disk lengths and offsets with checked casts and bounds each range against the bytes remaining. Oversized varints and lengths are rejected before they can overflow an integer or index a buffer. Table entries stop before the restart array; those bytes cannot complete a truncated key or value.

A `WriteBatch` is accepted whole or rejected whole, with its entry count matching its payload. Log records must stay within their 32KB block. Fragment chains require a FIRST and LAST, including the valid zero-length FIRST when only a header fits at a block boundary; orphaned fragments are ignored. Origin filtering and Snappy decompression remain in place. CRCs and the LevelDB manifest are not validated by this reader.

### Pasting instead

For anyone whose browser is not a Chromium, the same two values go in one field, whitespace-separated — a token may contain a colon and an organization URL certainly does:

```text
eyJ… my-team
Authorization: Bearer eyJ… org_1a2b3c
eyJ… https://app.devin.ai/org/my-team/settings
```

A whole `Authorization:` line is accepted because that is what a browser's network tab puts on the clipboard. The organization is normalised to the segment the API wants: `org_…` / `org-…` is an internal id and becomes `organizations/<id>`, anything else is a slug and becomes `org/<slug>`; an `app.devin.ai` URL is reduced to whichever of the two it carries. A pasted value **wins over the browser**. The path is then tried in each spelling until one answers, because the shape of that segment is the part CodexBar found varies. **A refused token is not retried** — it would be refused at every spelling.

### The reply reports what is *spent*

This is the trap in carrying both routes. The saved plan reports `dailyRemainingPercent`; the endpoint reports `daily_percentage`, which is **used**. Inverting the second would be inverting twice. Windsurf's own `GetPlanStatus` protobuf is the other way round again (`daily_quota_remaining_percent`); that one is not implemented here.

| Field | Becomes |
|---|---|
| `daily_percentage`, `daily_reset_at`, `hide_daily_quota` | `.daily`, 86,400s |
| `weekly_percentage`, `weekly_reset_at`, `hide_weekly_quota` | `.weekly`, 604,800s |
| `overage_balance`, else `overage_balance_cents` ÷ 100 | `creditBalance` |
| `has_quota_allocation` | `false` draws nothing at all |
| `plan_name` / `planName` / `plan` / `tier` | the plan line, else none — never borrowed from the saved row |

Resets arrived with an offset (`-08:00`) rather than as `Z`. Epoch seconds and milliseconds are read as well, since CodexBar's notes carry both and neither costs anything.

**CodexBar's fraction heuristic was deliberately not copied.** It reads a percentage of 1 or less as a fraction and multiplies by a hundred; a genuine 0.4% used would then be drawn as 40%, which is a figure nobody reported — and this account's measured reply carried whole numbers. Its recursive key-hunting fallback — any key whose name contains "day" or "week" — is not copied either, and for the same reason.

A reply that parses as JSON and carries neither window nor balance is `.unreadableReply`, not an account with nothing in it.

## Two accounts in one store, and two organizations behind one account

More than one `cachedPlanInfoData:user-…` row can exist where two accounts have signed in on this Mac, and **nothing in the file says which is current**. The tooling route takes the one whose `endTimestamp` is furthest out — an active subscription outranks a lapsed one — and the plan name is on the card either way. `hasMultipleDevinAccounts` is in the payload but names nothing that resolves this.

**A shared user id is not the same allowance, and the two routes are never fused.** The endpoint is scoped to an **organization**; the saved row is keyed by a **user id** and carries no organization at all. One user can belong to several organizations, so the same `userId` can sit under two different quotas — and there is no evidence anywhere on this Mac of which organization a saved row belongs to. The consequences are deliberate and conservative:

- The endpoint's plan line is **the reply's own** when it names one, and otherwise absent. The saved row's plan name is not borrowed, whatever `userId` the browser session carries: matching a user id does not establish the organization, and another organization's plan name is the same invention as a made-up percentage.
- `.automatic` **never crosses from the endpoint to the app's saved plan.** If there is a credential the endpoint is tried, and a failure is reported as it is; the saved plan answers only when there is no credential to try, or when the tooling route was chosen explicitly.
- The **cache** holds the same line. `ProviderUsage.requiresScopeMatch` is computed from the provider (Devin is the only one), and a banked reading stands in for another only when `UsageScope`s agree on **route, organization and identity**. `Identity` is the browser session's `userId`, the saved row's account id, or — for a pasted credential, which names nobody — a SHA-256 hash of the token, never the token itself. A missing identity or organization is never a wildcard.

A **pasted token names no user** (and neither does the older flat `windsurf.com` storage), so its scope is a hash of the credential plus the organization it was pasted with: the *same* pasted credential's readings stay together, a different one's do not, and it never matches a saved row's route. The app cache's scope is its own route and user id, and can therefore never stand in for an endpoint reading.

## Failure copy

- `.devinAppMissing` — no support directory under either name. "Devin isn't installed."
- `.devinPlanUnread` — the store is there and holds no plan row, its newest row has no reliable launch stamp, or that stamp is older than `UsageCache.maximumAge`. Either way: "Open Devin and sign in, so it can record your plan."
- `.devinOrganizationMissing` — a token was pasted with no organization beside it. Its own case rather than `.apiKeyMissing`, which would say "add a key" about a field that already has one.

All three are `.neutral` to `UsageAlerts`: true until somebody does something, and not an outage to announce. The first two offer `openApp("Devin")`; the third offers the credential field.

## First-run evidence

Presence of `User/globalStorage/state.vscdb` under the `Devin` or `Windsurf` Application Support directory marks the chooser row as detected. The database and browser storage are not opened during discovery. A detected hint is not evidence of a login, and Devin stays disabled until selected; only then may its fetch search Chromium browsers for the web session.

## Fixtures

The saved plan: `devin-pro.json`, `devin-free.json`, `devin-hidden-daily.json`, and `devin-state.vscdb` — a two-row store pinning the choice above. Written to the confirmed shapes with the account identity removed.

The endpoint: `devin-quota-usage.json` is the measured reply, field for field. `devin-quota-hidden.json` and `devin-quota-no-allocation.json` are written to CodexBar's account of the shapes this account does not produce — a hidden daily window, a balance in cents, a reset in epoch milliseconds, and a plan with no allowance.

The reader: `ChromiumLocalStorageTests` builds a LevelDB log by hand rather than committing anybody's profile.
