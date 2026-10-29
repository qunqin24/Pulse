# DimAgent

DimAgent is a built-in subscription provider. Pulse runs `dim usage --json` with the CLI's existing login; it does not open credential files, import cookies, or send prompts. Enable it in Settings after signing in with `dim auth login`.

The response shape was observed with **dimcode 0.5.21 on 2026-10-27**. The opt-in live test also fetched the subscription through `DimAgentUsageService.fetch`, including its filtered child environment. Tests use a reduced, anonymized example with replacement figures. Pack handling follows the subscription bucket fields; a live account with add-on packs has not yet been verified. Native UI interaction was not verified because this host's Accessibility automation permission was disabled.

The token-window fields were checked against the published `dimcode@0.5.21` parser on 2026-10-29, including the shared parser used by add-on buckets. [CLI documentation](https://dimagent.cn/docs/cli) describes window usage and reset times; [quota documentation](https://dimagent.cn/docs/credits) explains that a full token window pauses consumption. The review regressions are synthetic parser/cache/alert checks, not a new live-account or native-UI verification.

## Reading

- `subscription.product.name` supplies the plan name.
- `credits.subscription_bucket` supplies plan credits. `used_units / total_units` is the used fraction; `remaining_units` supplies the detailed amount. Its reported bucket `id` is retained as `cycleID` independently of the stable `dimagent.subscription` row ID: a new known grant re-arms threshold warnings without claiming a scheduled renewal or losing a pinned row.
- Each `credits.addon_buckets` entry has its own stable bucket id and top-up row. It is not added to the plan denominator.
- Each accepted subscription or add-on bucket's `window_states` supplies separate token limits from `window_token_used / window_token_cap`. `window_duration_hours` supplies the actual length (including fractional hours representable as whole seconds), and `window_expires_at` supplies the reset time. Invalid amounts, implausible lengths, malformed non-null dates and already-reset windows are omitted. A null reset date remains unstated. Row IDs use the reported window ID when available, otherwise the duration, with a same-key occurrence suffix to preserve multiple rows. The public CLI does not guarantee ID stability across resets or ordering of same-duration windows without IDs; pinned rows and alert continuity in those cases are not guaranteed.
- `feature_meters` supplies the `web_search` allowance separately. Unlimited meters and unknown feature keys are left out.
- Credit units are not currency. `entitlement_payload_json.quota_policy.grant_units` is not used: its scale differs from the reported bucket units.
- Bucket `expires_at` is an expiry, not a promised renewal. No reset time or fixed month length is invented. A cached bucket and its token limits are removed once the grant expires. Token limits retain the separate reported reset time; their expiry amount is the unused token capacity, floored at zero. Search `period_end` is the meter's reported period boundary.
- Only active or explicitly exhausted buckets are read. Expired buckets, missing numbers, nonfinite or negative amounts, and nonpositive totals are left out. A bucket with a parsed expiry also requires a reported `remaining_units`; otherwise it is omitted so its expiry cannot be lost in the cache. Only the explicit `exhausted` bucket status sets `isExhausted`; shared notification rules may still announce a plan-credit window as spent at 100%.

The standard card, ring, amount display, refresh schedule and notifications use `ProviderUsage`. No token-spend reader or transcript scanning is added. The ring follows Pulse's usual fullest-limit selection; a reader can pin the plan-credit row in Settings.

## CLI execution

`CommandLocator` finds `dim`, including the mise shim path. The child receives a small allowlist of identity/locale and proxy variables. Its PATH includes mise shims so an npm wrapper can find the user's mise-managed Node from a Finder-launched app. No inherited API keys or `DIMCODE_BIN_PATH` override are forwarded.

The request runs in the temporary directory, with empty stdin, a 20-second deadline and a 256 KiB output limit. Missing CLI, expired login, rate limiting, timeout and malformed output use Pulse's shared unavailable states. Explicit `Not signed in` / `Not logged in` errors map to `localLoginMissing`, bypassing cached quota display. Refused or expired existing credentials remain `localLoginExpired`; transient connection failures retain the normal stale-data fallback. Stderr is classified but not displayed or logged by this service.

The bundled `dimagent.svg` uses the official mark from [DimAgent's favicon](https://dimagent.cn/dimagent-favicon.svg), retrieved on 2026-10-27. Its path is unchanged; the green tile and placement transform are omitted, and the viewBox fits the 45 × 32 mark for Pulse's monochrome template rendering.

Implementation: [DimAgentUsageService.swift](../../Sources/Pulse/Providers/Profiled/DimAgentUsageService.swift). Checks: [DimAgentTests.swift](../../Tests/PulseTests/DimAgentTests.swift). Setup: [dimagent.md](../setup/dimagent.md).
