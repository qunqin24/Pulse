# JetBrains AI

Profiled provider: [`Sources/Pulse/Providers/Profiled/JetBrainsAIUsageService.swift`](../../Sources/Pulse/Providers/Profiled/JetBrainsAIUsageService.swift) (file route and route order), [`JetBrainsAIOnlineQuota.swift`](../../Sources/Pulse/Providers/Profiled/JetBrainsAIOnlineQuota.swift) (online route), [`Sources/Pulse/Auth/JetBrainsLogin.swift`](../../Sources/Pulse/Auth/JetBrainsLogin.swift) (sign-in). User setup: [../setup/jetbrains-ai.md](../setup/jetbrains-ai.md).

- **Credential:** `localLogin` — nothing pasted. Optionally, a JetBrains account sign-in from the Connection card's **JetBrains account** row, kept in `accounts.dat` under `AccountKey(.jetBrainsAI)`. The route shown on the pane is "The IDE's saved quota, or JetBrains once signed in · Without a sign-in, only the IDE's file is read."
- **Route order** (`JetBrainsAIUsageService.choose`):
  1. The IDE's file, when it holds a real quota that is still current (older IDEs; `isCurrent`: every limit's reset still ahead, or unstated). Nothing is sent, signed in or not. A file whose reset has passed — left by an IDE no longer run — goes on to step 2 when signed in; taken as an answer it kept the account off the network and the cache then dropped the expired window, so nothing showed (found in review, 2026-11-27). Signed out, it is still what is shown.
  2. Otherwise, signed in: the online quota.
  3. Otherwise the file's reason (`.localQuotaUnsaved`, `.localAppMissing`, …). For `.localQuotaUnsaved` the diagnostics' remedy is **Sign in…** (`ConnectionRemedy.firstSignIn`).

  A stored login that is refused or cannot be renewed is `.signedOut`; so is an `accounts.dat` that will not open. Neither falls back to the file's reason. A disabled provider is never read, so neither route runs.

## File route

- **Where:** `~/Library/Application Support/JetBrains/<IDE><version>/options/AIAssistantQuotaManager2.xml`, and `~/Library/Application Support/Google/AndroidStudio<version>/…`. Only folders whose name starts with a known IDE prefix are looked in; of those, the file modified last is read. Read-only.
- **Shape:** XML; `component[@name='AIAssistantQuotaManager2']` has `option` elements whose `value` attribute is JSON (escaped with `&quot;` / `&#10;`, undone by the XML parser):
  - `quotaInfo`: `{ type, current, maximum, until, tariffQuota: { current, maximum, available } }`, figures as strings.
  - `nextRefill`: `{ type, next, tariff: { amount, duration } }`, `duration` an ISO 8601 length such as `PT720H`.
- **Window:** one, `current / maximum`, both stated. `resetsAt` is `nextRefill.next` (not `quotaInfo.until`, the subscription's end). Kind `.other(seconds:)` with `reportsLength: true` when `duration` is an exact ISO 8601 length (weeks, days, hours, minutes, seconds); otherwise `.credits`, 30 days as a sort key, length not claimed.
- **Reasons:** no quota file anywhere, or a file without `quotaInfo` → `.localAppMissing`. Not XML → `.unreadableReply`. Neither `current` nor `maximum` present, and `quotaInfo.type` is `Unknown` or `nextRefill.type` is `Error` → `.localQuotaUnsaved` ("The app didn't save a quota Pulse can read on this Mac."). Otherwise `maximum` missing or ≤ 0, or `current` missing or negative → `.noLimitsReported`, which means a quota stated without a size.
- **IDEs from 2026.3 on (#122):** the IDE stopped writing its quota here. The file stays with `quotaInfo.type: Unknown` and `nextRefill.type: Error`, `idea.log` has no quota lines either, and the Accounts page fetches the quota online and keeps it in memory. That is what the online route is for.
- **Staleness:** the IDE rewrites the file only while running. The reading is marked live on each refresh even though the file may be old; the route note says so on the pane.
- **Evidence:** second-hand. The shape comes from CodexBar's JetBrains provider and its tests (MIT); no IDE's file on this Mac has been read. The fixture is inline in `Tests/PulseTests/JetBrainsAITests.swift`.

## Sign-in

Pulse signs in to the user's JetBrains Account itself, once, in the browser, with the **Junie CLI's public OAuth client**. It does not read the IDE's login, the Keychain or any IDE config file: the IDE's token comes from closed, obfuscated licensing code (`JBAccountInfoService`), and reusing its refresh token could sign the IDE out if the server rotates it.

Every value is taken from [rock3r/headroom](https://github.com/rock3r/headroom) (Apache-2.0) at commit `9a2851d`, `core/auth/src/commonMain/kotlin/dev/sebastiano/headroom/auth/JetBrainsOAuth.kt` and its test `JetBrainsOAuthTest.kt`, which say they are the Junie CLI's. None was read out of a JetBrains binary.

| Step | Value |
|---|---|
| Client id | `junie-cli` |
| Authorize | `GET https://junie.jetbrains.com/cli-auth?client_id=…&scope=…&state=…&code_challenge=…&code_challenge_method=S256&redirect_uri=…` — that order, **no** `response_type` |
| Scopes | `offline_access openid jb-authn-service` |
| PKCE | S256; verifier and `state` are 32 random bytes, base64url (`OAuthLogin.randomToken`) |
| Redirect | `http://localhost:<port>`, **no path**, on the first free port of **62345–62364** (the client is registered for those); `LoopbackCallback` with path `/`, loopback interface only, `state` checked |
| Exchange | form `POST https://oauth.account.jetbrains.com/oauth2/token`: `grant_type=authorization_code`, `code`, `redirect_uri`, `client_id`, `code_verifier`. Reply must have `access_token`, `refresh_token` and `expires_in > 0`; `id_token` is kept (`AccountCredentials.idToken`), and its `email` claim names the login |
| Renewal | the same endpoint: `grant_type=refresh_token`, `refresh_token`, `client_id`, nothing else. A refresh or ID token the reply leaves out stays as it was. Renewed when the access token is within a minute of expiring, before the quota is asked, and written with `AccountCredentialStore.renewed`, which never writes into an emptied slot |

Cancellation, the five-minute wait and errors are `OAuthLogin`'s: Cancel unwinds the listener, a timeout says the browser did not come back, all twenty ports busy says to finish the other sign-in. A renewal failure is classified by `LiveUsageServices.renewalFailure` (refused → `.signedOut`; no answer, 429, 5xx → transient reasons that keep the cache). Sign out deletes the login; the next refresh reads the file again.

## Online route

Ported from headroom's `core/quota/src/commonMain/kotlin/dev/sebastiano/headroom/quota/JetBrainsAiQuotaReader.kt` and `JetBrainsAccessOption.kt` at `9a2851d`, which name the Junie CLI or the IDE as the source of each step (attribution in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)).

1. **Audience switch.** Form `POST https://oauth.account.jetbrains.com/oauth2/token` with `grant_type=switch_audience`, `refresh_token`, `audience=jcp-user-management`, `client_id=junie-cli`, in that order. A 400/401/403 means the refresh token was refused → `.signedOut`. A new refresh token in the reply is **not** stored (headroom does the same).
2. **Access options.** `GET https://api.jetbrains.cloud/user-management/api/ai-access-options` with `Authorization: Bearer <that token>`. Reply `{ "aiAccessOptions": [ { type, aiAccessEnabled, name, licenseId, orgId, orgName, workspaceId, workspaceName, … } ] }`. Only enabled options are read, at most five, no repeats: `type: workspace` with a `workspaceId` is a **seat**; anything else with a `licenseId` is a **licence**. None → `.noPlan`. No list → `.unreadableReply`.
3. **A licence** (AI Pro and the like): `POST https://api.jetbrains.ai/auth/jetbrains-jwt/provide-access/license/v2` with `Authorization: Bearer <ID token>`, JSON body `{"licenseId":"…"}` → `{ "token": … }`. That token reads `POST /user/v5/quota/get` and `POST /user/v5/quota/metadata/refill` on the same host, body `{}`, headers `Grazie-Authenticate-JWT: <token>`, `Grazie-Agent: {"name":"Pulse","version":"1"}` (headroom sends its own name there), `Accept` and `Content-Type: application/json`.
4. **A seat**, once for all seats: switch to `audience=org-service`, then `GET https://api.jetbrains.cloud/org/orgsuserinfo` with that token; the first JWT-shaped text in the reply is the signed list of organisations. Per seat: switch to `audience=ai-access` with `org_id`, `workspace_id`, `orgs_user_info`; refused, once more without `org_id` (the IDE asks with only the workspace). The seat token reads `GET https://api.jetbrains.ai/quota/api/quota/get` and `/quota/api/quota/refill` with `Authorization: Bearer` — the IDE's own `JcpQuotaClient` paths.
5. **Reply.** Quota: `{ "current": { "current": {"amount": "1187.525"}, "maximum": {"amount": "1000000.0"}, "until": <ms>, "tariffQuota": {…}, "topUpQuota": {…} } }`. Refill: `{ "current": { "next": <ms>, "last": <ms>, "tariff": { "amount": {…}, "period": { "millis": 2592000000 } } } }`. Amounts are strings in `{"amount": …}` (a plain number is taken too), in units of **1/100,000 of an AI credit** (the IDE's `UNITS_IN_CREDIT`, per headroom); a fraction of two needs no conversion.

**Mapping, as the file's:** one window per licence or seat, `current / maximum`. `maximum` missing or ≤ 0, or `current` missing or negative → no window; all options answered without one → `.noLimitsReported`. `resetsAt` is the refill's `next` (not `until`). `period.millis` → `.other(seconds:)` with `reportsLength: true`; none → `.credits`, 30 days as a sort key, length not claimed (headroom infers a calendar month from a reset at a month's last millisecond; Pulse does not). A refill that fails leaves reset and length off and keeps the quota. `current`/`maximum` are the whole quota, top-up included, as the file's are; `tariffQuota` and `topUpQuota` are not drawn on their own. One window has id `jetbrains.quota` (the file route's) and no scope, and a licence names the plan (`AIP` → JetBrains AI Pro, `AIU` → JetBrains AI Ultimate, `JUNP` → Junie). Several windows have ids `jetbrains.quota.<first 6 bytes of SHA-256 of the id, hex>` and the product or workspace name as scope, the fullest first. When some options fail and others answer, the answers are shown; when all fail, the first failure is the reason. A refused licence or seat request is `.signedOut`.

**Left out of headroom's flow:** the `grazie-lite` fallback (`POST /auth/jetbrains-jwt/license/obtain/grazie-lite`) — a call named "obtain" may give the account a licence, and Pulse only reads; headroom's `/auth/test` balance call; and its "Combined" window that pools licences, which would be a figure Pulse made, not one JetBrains stated.

**Network** ([../networking.md](../networking.md)): every request goes through `ProfileHTTP.reply` — `NetworkSession.shared` (proxy setting, System Proxy Only guard), redirects refused (`NoRedirects`, so a bearer or ID token never follows a 3xx elsewhere), and `recordedData`, so the diagnostics show each reply with token-named values and the request's own credentials masked (`Grazie-Authenticate-JWT` is masked by name since this change). The sign-in's token exchange goes through the same function outside a check, so it is not recorded.

## What is verified

- **Code (tests, synthetic data):** the authorize URL, token-request bodies and their order, token-reply parsing, renewal keeping what is left out, every request of the online route (URLs, methods, headers, bodies), the seat retry, reply parsing (full, missing fields, zero maximum, top-up only, no refill), reasons (no plan, refused, server error), renew-before-read, route order, remedy, storage key and old-login decoding, header masking. `Tests/PulseTests/JetBrainsAIOnlineTests.swift`.
- **Inferred from headroom:** every URL, the client id, scopes, ports, the audience names and parameters, header names, reply shapes and units. headroom's own tests use mock servers with these shapes.
- **Unverified:** nothing has been sent to JetBrains from Pulse; no live account, licence or seat has been read; whether `jb-authn-service` and the ID token keep working for this client, and how long JetBrains' tokens last, are not measured.
