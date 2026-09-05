# Cursor

Service: [`CursorUsageService.swift`](../../Sources/Pulse/CursorUsageService.swift). Login: [`CursorAppLogin.swift`](../../Sources/Pulse/CursorAppLogin.swift).

Extra accounts are **not** supported, and that is not an oversight. The same Cursor web sign-in Grok Bot uses would work, but Cursor’s usage summary is read from the **editor’s** stored login and a second account has no editor behind it. Grok Bot needs nothing but the token.

`keepsLocalTranscripts` is false. One named route: “Cursor’s own login”.

## Credential

`GET https://cursor.com/api/usage-summary` — undocumented, like the CLI routes, and can change without notice.

**The cookie is not stored anywhere — it is built.** The website authenticates with `WorkosCursorSessionToken` rather than a bearer header. The obvious way to get one is to read the browser’s cookie jar. There is no need: the editor keeps its OAuth token in VS Code’s global-state SQLite (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, `ItemTable` key `cursorAuth/accessToken`). The account id is the tail of that token’s `sub` claim after `|`; the cookie value is **that id and the token joined by `::`**, percent-encoded.

Pulse still holds no Cursor credential of its own for the primary account. The token is used to build one request header and is never written, logged, or shown.

Opened **read-only and in place**. Cursor is usually running, so the database is in WAL mode; copying the file aside takes the main database without the journal holding the newest writes.

The row is normally TEXT but has been seen as a BLOB. When it is, it is UTF-16 with no BOM; read as UTF-8 that yields the token with a null after every character, which parses as nothing and explains itself to nobody.

Redirects are refused. The session goes out as a `Cookie` header, which `URLSession` will carry across a redirect to another host (unlike `Authorization`, which it strips).

Nothing here renews the editor token. Cursor does that the next time it is used. A minute’s expiry headroom is applied before a request is sent.

## Windows

What the plan includes is **two pools, not one**, which is how Cursor’s own account page draws it:

- `autoPercentUsed` — Cursor’s own models (Composer, Cursor Grok), scoped “Cursor Models”
- `apiPercentUsed` — everything else, scoped “Other Models”

Spending past the first eats into the second. The first cut of this shipped a single combined window and was wrong for the reason a combined figure is always wrong: it cannot say which of the two is about to run out.

**Those fields are percentages, not fractions** — 0.0267 means 0.0267%, not 2.67%. Settled by arithmetic rather than taken on trust. **Historical evidence:** on an account 12¢ in, the three percentages implied pools of $450 and $22.50, summing to $472.50 matching `totalPercentUsed` to the cent.

**`plan.used` / `plan.limit` is a different denominator and must not sit beside them** — plan cash value ($20 on Pro) against pools worth hundreds, so a third bar reads as a contradiction. It is used for the extra-spend limit, as the fallback when an account reports no pools at all, and as `creditBalance` (`plan.remaining` is a real balance, not an allowance — which is why this provider reports one and Antigravity does not). A team account’s `pooled` / `onDemand` stand in for the individual pair.

Billing-cycle length is 28 to 31 days, stored as a flat 30 with `reportsLength: false`.

## Grok Bot is not this card

Grok Bot is billed against the Cursor account but is a **separate weekly allowance** and a separate `Provider`. It shipped first as a fourth row here; people looking at the Grok pane asked where Grok Bot was. See [grok-bot.md](grok-bot.md).

## First run

`CursorAppLogin.hasStoredLogin()`, not the app bundle — same “has this ever run here” evidence as `~/.claude`, and it does not care where the app was dragged to.
