# Grok Bot usage investigation (historical)

**Status: superseded as an implementation plan.** Pulse now ships Grok Bot as its own provider. Current behaviour, mapping rules, and extra-account login: [providers/grok-bot.md](providers/grok-bot.md). SuperGrok / Grok Build CLI pool: [providers/grok.md](providers/grok.md). Cursor monthly pools: [providers/cursor.md](providers/cursor.md).

This page is kept as **investigation evidence** — endpoints, headers, field names, protobuf notes, and the reasons the first product shape was rejected. It is not a description of what to build next. Where this file and `GrokBotUsageService` disagree, **the service wins**.

No runtime re-test of a live account is claimed here. Do not paste cookies, tokens, or authenticated payloads into issues.

---

## Objective (then)

- Find how Grok Bot (Cursor internal name “Sand”) usage is read: endpoint, auth, headers, response fields, where credentials land on disk.
- Distinguish it from the Grok Build / SuperGrok quota, and choose a Pulse path.

## Details that remain true

- Grok Bot is **not** Grok Build. Do not use `~/.grok/auth.json` or `https://cli-chat-proxy.grok.com/v1/billing?format=credits` to read Grok Bot.
- Grok Bot is a separate weekly allowance on the **Cursor** account. Internal protocol name: `Sand`.
- Two private interfaces were confirmed during investigation:
  - REST: `POST https://cursor.com/api/dashboard/get-sand-usage-status`
    - `Cookie: WorkosCursorSessionToken=…`
    - `Accept: application/json`
    - `Content-Type: application/json`
    - `Origin: https://cursor.com`
    - Body: `{}`
  - Connect RPC: `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`
    - `Authorization: Bearer <Cursor access token>`
    - `Connect-Protocol-Version: 1`
    - `Content-Type: application/json`
    - Body: `{}`
- Pulse can read a Cursor access token from:
  - macOS: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  - SQLite key: `cursorAuth/accessToken`
  - Cookie constructed from JWT `sub` + token (see `CursorAppLogin`).
- OpenUsage also mentioned: SQLite `cursorAuth/refreshToken`; Keychain services `cursor-access-token` / `cursor-refresh-token`. Pulse’s current primary path does not use those Keychain items.
- Response fields seen (camelCase and snake_case):
  - `currentPeriodStart` / `current_period_start`
  - `nextResetTimestampUtc` / `next_reset_timestamp_utc`
  - `usagePercent` / `usage_percent`
  - `includedLimitZero` / `included_limit_zero`
  - `availableBankedResetCount` / `available_banked_reset_count`
  - `usesPooledEnterpriseAllowance` / `uses_pooled_enterprise_allowance`
  - `hasAvailableUsage` / `has_available_usage`
  - `hasNonZeroIncludedLimit` / `has_non_zero_included_limit`
  - `upgradeRecommendation` / `upgrade_recommendation`
  - `sandTrialExpiresAt` / `sand_trial_expires_at`
  - `sandTrialCancelable` / `sand_trial_cancelable`
- Mapping intent from the investigation (refined in the service since):
  - `usagePercent` is percent **used**.
  - `currentPeriodStart` to `nextResetTimestampUtc` often forms a weekly window **when both exist**.
  - `usesPooledEnterpriseAllowance == true`: no personal bar.
  - `hasNonZeroIncludedLimit == false` or `includedLimitZero == true`: do not draw a fake empty/full ring.
  - Fail-soft was the original idea (do not fail Cursor’s main usage). **Superseded:** Grok Bot is its own fetch, not a Cursor sidecar.

xAI docs (weekly included usage; Cursor vs SuperGrok eligibility uses the larger side):

- https://docs.x.ai/grok-bot/faq
- https://docs.x.ai/grok-bot/settings-and-notifications

Claude fallback notes that used to live beside this investigation now point at [plan.md](plan.md) / [providers/claude-code.md](providers/claude-code.md).

## Work state (investigation, frozen)

### Completed then

- CodexBar Claude source review (no Claude Status Line JSON/drop-file there).
- Pulse Claude fallback checked; `docs/plan.md` created (now a pointer).
- Cloned `xai-org/grok-build`; confirmed Grok Build quota is not the Grok Bot target.
- CodexBar Grok Bot: `POST /api/dashboard/get-sand-usage-status`, same Cursor session cookie, weekly fields.
- OpenUsage Connect RPC + Cursor token sources.
- Recovered Grok Bot protobuf: `GetSandUsageStatusResponse` field numbers and types.
- Confirmed `/Applications/Grok Bot.app` on the investigation machine.

### Left open then (still not claimed done)

- Exact token location for a **standalone** Grok Bot install with no Cursor app / no Cursor login (directory, database/Keychain names, fields).
- Whether Pulse should prefer Cookie REST or Bearer Connect RPC; extra native-client headers were not fully compared. **Shipped choice:** Cookie REST. On one account REST and RPC were byte-identical.
- App data directory `~/Library/Application Support/Grok Bot` was located; credentials inside were **not** read during investigation. Later: `sand-secrets.json` `cursor-accounts`, Electron safeStorage. Pulse does not read that file.

## Recommended direction then (partially rejected)

1. Read Grok Bot as an extra weekly window **inside** `CursorUsageService`, not in `GrokUsageService`.
2. Reuse Pulse’s Cursor access token / constructed `WorkosCursorSessionToken`.
3. Optional concurrent branch on the Cursor fetch; ignore Grok Bot failure so Cursor’s main usage still succeeds.
4. Show a window only with a valid `usagePercent` and a non-zero included allowance.
5. Treat the interface as unpublished; keep fields optional.

**What shipped instead:** item 1 was tried and abandoned. A fourth row on the Cursor card produced “where is Grok Bot?” from someone looking at the Grok pane. Independent provider `GrokBotUsageService`, own ring, Cursor login, xAI icon.

## Outcome vs this investigation (implementation-time evidence)

These were measured while implementing, not re-verified for this doc rewrite:

- **`nextResetTimestampUtc` was absent** on the account used. REST and Connect RPC replies were byte-identical, both with `currentPeriodStart` only. Field is optional; no reset row when missing; seven days are a sort key (`reportsLength: false`), never a divisor.
- **Do not use `currentPeriodStart + 7 days` as a reset.** Grok Bot’s own client does not. From `Grok Bot.app/Contents/Resources/app.asar`: `nextResetMs: n != null && Number.isFinite(n) && n > 0 ? n : null`. Schema: both timestamps are proto3 **message** fields (explicit presence).
- “Weekly” is xAI documentation, not inferred from `currentPeriodStart`.
- That account returned `usagePercent: 0` + `hasNonZeroIncludedLimit: true` (included, unused). “Not included” also returns 0 plus upgrade copy — drawing that is a fake full-green ring.
- `UsageDetailCard.resetText` used to print window length when reset was missing; that length is sometimes only a sort key. Fixed to show nothing.

### Extra accounts (evidence, now implemented)

Not OAuth — Cursor has no third-party authorize/token pair. From the asar:

1. Browser: `https://cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&redirectTarget=sand`
2. Poll: `https://api2.cursor.sh/auth/poll?uuid=…&verifier=…` — 404 = not ready; 200 returns `accessToken` / `refreshToken`

PKCE hashes the **base64url-encoded verifier string**, not the raw random bytes. Tokens ~60 days (`exp` on one Mac). No refresh endpoint in the client; expiry means sign in again.

Standalone client stores Cursor accounts in `~/Library/Application Support/Grok Bot/sand-secrets.json` under `cursor-accounts`, Electron safeStorage. Pulse does not read it.

## Files (then and now)

- Current: `Sources/Pulse/GrokBotUsageService.swift`, `Sources/Pulse/CursorWebLogin.swift`, `Sources/Pulse/CursorAppLogin.swift`, `Sources/Pulse/GrokUsageService.swift`, `Sources/Pulse/CursorUsageService.swift`.
- Historical references outside this repo (CodexBar `CursorSandUsage` / `CursorStatusProbe`; OpenUsage `CursorUsageClient` / `CursorAuthStore` / `CursorUsageMapper`; `/Applications/Grok Bot.app`). Those trees are not part of Pulse and may have moved.
