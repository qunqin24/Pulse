# Grok

Service: [`GrokUsageService.swift`](../../Sources/Pulse/GrokUsageService.swift). Extra accounts: [authentication.md](authentication.md).

This is the **account’s** weekly SuperGrok / xAI pool, not “Grok Build the CLI”. Grok Bot is a different bill: [grok-bot.md](grok-bot.md).

Extra accounts are supported. `keepsLocalTranscripts` is false. Primary route is named (“Grok’s own login”); an added account is not shown that row.

Issue history: [Pulse #9](https://github.com/qunqin24/Pulse/issues/9).

## Why the ring is called Grok

Since June 2026 a paid plan spends **one weekly pool** across every Grok product — web chat, Imagine, voice, the API, and the CLI. The reply’s `productUsage` lists `GrokChat` beside `GrokTasks`. There is no CLI-specific figure to show. Naming the ring after the CLI would claim one. The breakdown is **not** drawn as separate windows: they are shares of one limit.

## Primary credential

Borrow the OIDC login Grok Build’s CLI stored in `~/.grok/auth.json`. Nothing is held for the primary account.

- `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` for the figures, with header `x-xai-token-auth: xai-grok-cli`.
- `GET https://cli-chat-proxy.grok.com/v1/settings` for the plan name (`subscription_tier_display`, e.g. “SuperGrok”).

Neither endpoint is a public documented usage API. They are what the CLI itself calls and can change without notice.

The stored token lasts about six hours. The CLI renews it while you use Grok; nothing renews it for Pulse on the primary. Aged-out vs never-signed-in are two cases (`.grokLoginExpired` vs `.grokSignInRequired`) because the instruction is different. `.signInRequired` names Codex — do not reuse it here.

## The header selects the shape of the reply

Without `x-xai-token-auth: xai-grok-cli` the same path answers the **enterprise credit form** instead — `monthlyLimit`, `onDemandCap`, a history of billing cycles — which on a personal plan is zeroes throughout. A denominator of nothing is not a reading. **Historical:** it took a while to notice that the empty answer was the wrong *question*.

## Absent percentage is zero — inside a running period

The payload is proto3 serialised to JSON with **implicit** presence, so zeroes are simply absent. Visible in the same reply: `GrokChat` carries a product name and no `usagePercent` while `GrokTasks` carries one. Treating a missing figure as “no reading” would blank the ring for the first hours of every week.

It is only read as zero **inside a period that is currently running**. A reply describing a period that has already ended says nothing about the one that followed it.

This is the **opposite** of Grok Bot’s `usagePercent` rule (explicit presence there; absent means unset). See [grok-bot.md](grok-bot.md).

## Window length

Measured from the period’s own two timestamps (`currentPeriod` start and end), not from a `type` string. `reportsLength` is true. **Historical evidence, one account:** exactly 604,800 seconds. The `USAGE_PERIOD_TYPE_WEEKLY` enum is theirs to rename; the subtraction is not.

## Plan and balance

Settings call is on a shorter budget than usage — figures are already in hand. Only `subscription_tier_display` is read; the same reply carries subagent and planner settings, no use to Pulse.

`prepaidBalance` and `onDemandCap` are denominated in a unit the reply never names, and the cap is an allowance rather than a balance, so `creditBalance` stays nil.

## Added accounts

Same two endpoints with the token Pulse holds. Never looks at `~/.grok/auth.json`. Device-code OAuth, scopes `openid email offline_access grok-cli:access`. `billing:read` is **not allowed for this client** — not a missing scope Pulse forgot. Details: [authentication.md](authentication.md).

## First run

Presence of `~/.grok`. Without that gate, offer-once would switch Grok on at the next update for everyone as a grey ring.
