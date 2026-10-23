# Cursor

Service: [`CursorUsageService.swift`](../../Sources/Pulse/Providers/CursorUsageService.swift). Login: [`CursorAppLogin.swift`](../../Sources/Pulse/Auth/CursorAppLogin.swift).

Extra accounts are **not** supported, and that is not an oversight. The same Cursor web sign-in Grok Bot uses would work, but Cursor’s usage summary is read from the **editor’s** stored login and a second account has no editor behind it. Grok Bot needs nothing but the token.

`keepsLocalTranscripts` is false. One named route: “Cursor’s own login”.

## Credential

`GET https://cursor.com/api/usage-summary`, then `POST https://cursor.com/api/dashboard/get-plan-info` and, on a weekly plan, `POST https://cursor.com/api/dashboard/get-current-period-usage` (body `{}`, `Origin: https://cursor.com`, as for [Grok Bot](grok-bot.md#current-route)) — all undocumented, like the CLI routes, and can change without notice.

**The cookie is not stored anywhere — it is built.** The website authenticates with `WorkosCursorSessionToken` rather than a bearer header. The obvious way to get one is to read the browser’s cookie jar. There is no need: the editor keeps its OAuth token in VS Code’s global-state SQLite (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, `ItemTable` key `cursorAuth/accessToken`). The account id is the tail of that token’s `sub` claim after `|`; the cookie value is **that id and the token joined by `::`**, percent-encoded.

Pulse still holds no Cursor credential of its own for the primary account. The token is used to build one request header and is never written, logged, or shown.

Opened **read-only and in place**. Cursor is usually running, so the database is in WAL mode; copying the file aside takes the main database without the journal holding the newest writes.

The row is normally TEXT but has been seen as a BLOB. When it is, it is UTF-16 with no BOM; read as UTF-8 that yields the token with a null after every character, which parses as nothing and explains itself to nobody.

**Newer Cursor builds seal the cell.** When `cursor.storage.authTokenEncryptionAtRest` is on, the value is `cursor-safe-storage:v1:` plus standard base64 of a Chromium `v10`/`v11` ciphertext — Electron's safeStorage, the same scheme `BrowserCookies.decrypt` already knows. The key is `Cursor Safe Storage` in the login keychain (account `Cursor Key`), opened through `BrowserCookies.safeStorageKey`. A plaintext JWT from an older editor is still accepted. A sealed row whose key was denied or dismissed is `.cursorKeyRefused`, not `.cursorLoginExpired`: opening Cursor will not help, and Refresh asks the keychain again.

**The keychain is asked as seldom as possible** (`CursorKeychain`): every read raises macOS's confidential-information dialog unless the reader chose Always Allow, and Cursor and Grok Bot both borrow this login, so asking on each automatic pass put the dialog up every few minutes, twice. A key handed over is kept in memory until Pulse quits (never written). After a refusal an automatic pass does not ask again until the next launch; a manual refresh of Cursor or Grok Bot asks at once (`UsageStore.refresh(_:)` → `allowAsking`). The two providers' reads wait on one another, so one pass asks once. A kept key that no longer opens the row (Cursor made a new one) is forgotten and the keychain read once more; macOS asks about the new item once, whatever was allowed for the old. A key that opens nothing even read afresh is `.unreadable`, shown as an expired login, since opening Cursor rewrites the row.

Redirects are refused. The session goes out as a `Cookie` header, which `URLSession` will carry across a redirect to another host (unlike `Authorization`, which it strips).

Nothing here renews the editor token. Cursor does that the next time it is used. A minute’s expiry headroom is applied before a request is sent.

## Windows

What the plan includes is **two pools, not one**, which is how Cursor’s own account page draws it:

- `autoPercentUsed` — Cursor’s own models (Composer, Cursor Grok), scoped “Cursor Models”
- `apiPercentUsed` — everything else, scoped “Other Models”

Spending past the first eats into the second. The first cut of this shipped a single combined window and was wrong for the reason a combined figure is always wrong: it cannot say which of the two is about to run out.

**Those fields are percentages, not fractions** — 0.0267 means 0.0267%, not 2.67%. Settled by arithmetic rather than taken on trust. **Historical evidence:** on an account 12¢ in, the three percentages implied pools of $450 and $22.50, summing to $472.50 matching `totalPercentUsed` to the cent.

**`plan.used` / `plan.limit` is a different denominator and must not sit beside them** — plan cash value ($20 on Pro) against pools worth hundreds, so a third bar reads as a contradiction. It is used for the extra-spend limit, as the fallback when an account reports no pools at all, and as `creditBalance` (`plan.remaining` is a real balance, not an allowance — which is why this provider reports one and Antigravity does not). A team account’s `pooled` / `onDemand` stand in for the individual pair.

**Enterprise accounts may report neither pair.** Their shared allowance arrives as `individualUsage.overall`, with `used`, `limit` and `remaining` in **cents**. When no model pools are reported, it becomes the same monthly money fallback and the balance; its amounts are converted to dollars for the card, which writes the currency symbol and two decimal places. Evidence: an Enterprise account on 2026-10-23 reported `used: 80`, `limit: 80000`, `remaining: 79920` (fixture `cursor-enterprise-overall.json`), which is `$0.80 / $800.00` used and `$799.20` left.

Billing-cycle length is 28 to 31 days, stored as a flat 30 with `reportsLength: false`.

## Weekly plans

**On a plan whose included usage is weekly, one weekly window replaces the two pools** (#87). Premium is one such plan. There the usage summary reports both pools at 0% while Cursor's page shows the week partly spent under "Weekly usage limit"; the summary cannot see that limit.

What the editor draws instead (Cursor 3.25, `workbench.desktop.main.js`), and what Pulse reads, through the dashboard's REST form of each RPC:

- `get-plan-info` → `planInfo.includedUsagePeriod` is `INCLUDED_USAGE_PERIOD_WEEKLY` (number `2` is also read), and `planInfo.includedUsageResetsAt` is the reset, **milliseconds as a string**.
- `get-current-period-usage` → `planUsage.totalPercentUsed` is the week, a percentage like the pools'. On a weekly plan this reply's `billingCycleStart`/`End` are exactly seven days apart.

The period is Cursor's own word, so the seven days are a stated length (`reportsLength: true`). Extra spend from the summary stays; the plan's `remaining` stays as the balance. **Evidence:** a Premium account on 2026-10-16 answered with the shapes above (fixtures `cursor-plan-info-weekly.json`, `cursor-period-usage-weekly.json`), and Pulse read 35.5%, the figure the editor rounds to 36%.

A `get-plan-info` call that fails leaves the summary's pools as they were. Once the plan says weekly, a `get-current-period-usage` call that fails is a failed read, and a reply without the figure draws no week rather than one at 0%.

## Service status

Settings › Cursor › **Service status** (`ServiceStatus`, `ServiceStatusGroup`, `StatusPage.of(.cursor)`, added 2026-10-15): **every component status.cursor.com shows but Grok Bot's** — Automations, Review Agents, CLI, Cloud Agents, cursor.com, IDE and Origin as of that day; Grok Bot's row is shown in Grok Bot's pane, from the same feed read once — each with the state now, ninety days of bars and the page's uptime figure. It is a **Statuspage** page like Claude's and is read the same way (`readStatuspage`): `/api/v2/summary.json` for the components, `/uptime_showcase?components=<ids>` for the history ([claude-code.md](claude-code.md#service-status)). Colours are the page's theme: operational `#1E8542`, degraded `#F1C40F`, partial `#B35E14`, major `#DE2F1B`, maintenance `#207AB6`; square bars.

**The outage notification is narrower: the IDE, the CLI and Cloud Agents, by id** (`StatusPage.notifiesAbout`) — what the account's usage is spent through. Not cursor.com, Automations or Review Agents; not "Origin", which the page does not explain; not Grok Bot, a provider of its own ([grok-bot.md](grok-bot.md)), whose row is its pane's.

## Grok Bot is not this card

Grok Bot is billed against the Cursor account but is a **separate weekly allowance** and a separate `Provider`. It shipped first as a fourth row here; people looking at the Grok pane asked where Grok Bot was. See [grok-bot.md](grok-bot.md).

## First run

The Cursor `state.vscdb` file's presence, not its contents or the app bundle. `ProviderDiscovery` uses it only to mark the chooser row as detected; reading the token waits until selection.
