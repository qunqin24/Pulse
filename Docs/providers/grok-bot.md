# Grok Bot

Service: [`GrokBotUsageService.swift`](../../Sources/Pulse/GrokBotUsageService.swift). Cookie: [`CursorAppLogin.swift`](../../Sources/Pulse/CursorAppLogin.swift). Extra accounts: [`CursorWebLogin.swift`](../../Sources/Pulse/CursorWebLogin.swift), [authentication.md](authentication.md).

**Current behaviour lives here.** The pre-implementation investigation is historical: [`../grok-bot-usage.md`](../grok-bot-usage.md). Where that file and this one disagree, this file and the service win.

Grok Bot is xAI’s, sold through Cursor and billed against the **Cursor** account. It is not a share of Cursor’s monthly model pools, and it is not the SuperGrok weekly pool [grok.md](grok.md) reads. Two companies’ bills, one brand: they share no credential, no endpoint, and **no mark** (`grok.svg` vs `xai.svg`).

Extra accounts are supported. `keepsLocalTranscripts` is false. `soleRoute` names Cursor’s login, because that is whose credential it is.

## Why a ring of its own

It shipped first as a fourth row on Cursor’s card. The question that came straight back was “where is Grok Bot”, asked while looking at the Grok pane — which is the *other* Grok. A name people use is worth a place on the rail.

Do **not** read Grok Bot from `~/.grok/auth.json` or `cli-chat-proxy.grok.com`. That is Grok / SuperGrok.

## Current route

`POST https://cursor.com/api/dashboard/get-sand-usage-status` with the cookie `CursorAppLogin` already makes (or the same cookie shape built from an extra-account token). Body `{}`. Headers include `Origin: https://cursor.com` — an endpoint that checks origin refuses a request without one. Redirects refused (Cookie would otherwise follow to another host).

Cursor’s protocol calls this product “Sand”. Not public API; can change without notice. Fields are decoded optionally so a shape change costs the reading rather than a crash.

The investigation also documented Connect RPC `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus` with a Bearer token. **Current Pulse uses the dashboard REST cookie call**, not that RPC. Historical comparison: on the account measured while implementing, REST and RPC answered **byte for byte**.

## Mapping (current)

`usagePercent` is how much is **gone**, 0…100.

**The reply often states no reset and no length.** On the account measured at implementation, neither REST nor RPC carried `nextResetTimestampUtc` — only `currentPeriodStart`. The field is read where a reply offers one; the row has no reset line where it does not. Seven days are a **sort key** (`reportsLength: false`). That it is weekly is xAI’s own word ([Grok Bot FAQ](https://docs.x.ai/grok-bot/faq)), not an inference from a start stamp.

**Do not derive reset from `currentPeriodStart` + 7 days.** The vendor’s own client does not. Inside `Grok Bot.app` (`Contents/Resources/app.asar`): `nextResetMs: n != null && Number.isFinite(n) && n > 0 ? n : null` where `n` is `nextResetTimestampUtc`. The same bundle’s schema marks both timestamps as proto3 **message** fields (explicit presence) — absent is unset, not a zero the serialiser dropped.

That combination found a bug one layer up: `UsageDetailCard.resetText` used to fall back to `lengthText` whenever `resetsAt` was nil, printing “7 days” for a length nobody reported.

**Absent `usagePercent` is not a zero here** — opposite of Grok’s proto3 scalar. Cursor’s schema declares it `opt: true` (explicit presence). The vendor client: `if (e.usesPooledEnterpriseAllowance || e.usagePercent == null || …) return null`.

**Nothing included is not nothing used.** An account with no Grok Bot allowance answers 0% as well, with the rest of the reply given over to upgrade marketing — drawn literally that is a full green ring for something the account does not have (same trap as Copilot’s unissued quotas). Required before a window is drawn:

- `usesPooledEnterpriseAllowance` is not true (org pot, no personal share)
- `includedLimitZero` is not true
- `hasNonZeroIncludedLimit` is true
- `usagePercent` is present

Those three flags come back as **`.grokBotNotIncluded`, not `.noLimitsReported`**, when the reply actually *says* the plan excludes it. A reply carrying none of the flags at all is `.unreadableReply` — a rename must not become a confident claim about the subscription.

The reply prices the *upgrade* (“$500 of Grok Bot usage each week with Pro+”) and never what is left of this plan’s own allowance. `creditBalance` stays nil.

## Extra accounts

Not OAuth. [`CursorWebLogin`](../../Sources/Pulse/CursorWebLogin.swift): login page + poll. PKCE hashes the **base64url-encoded** verifier string. Tokens ~60 days; no refresh endpoint in Cursor’s client. See [authentication.md](authentication.md).

Pulse does not read the standalone app’s `sand-secrets.json`.

## First run

**Only the standalone app** (`/Applications/Grok Bot.app` or `~/Applications/Grok Bot.app`). Grok Bot is also used inside Cursor, but a Cursor login is no evidence the plan *includes* it — keyed on that, every Cursor user’s first run would carry a ring that says “your plan doesn’t include this”.

## Investigation leftovers (not current work)

[`../grok-bot-usage.md`](../grok-bot-usage.md) still records: native Grok Bot client extra headers were not fully compared; Pulse chose not to decrypt `sand-secrets.json`. Those are historical open questions, not a claim that current REST-cookie behaviour is unverified in code. No runtime test of a live account is claimed in this directory.
