# Qoder

Service: [`QoderUsageService.swift`](../../Sources/Pulse/QoderUsageService.swift).

Extra accounts are not supported. `keepsLocalTranscripts` is false. First-run detection: `Qoder.app`, `Qoder IDE.app`, or `~/.qoder`. A session still has to be read in Settings — presence of the app is not a cookie.

## Credential

Two, same store (`keys.dat`):

1. A **personal access token** (`pt-…`). It lasts for the expiry set in the Qoder console. Pulse sends it as `Authorization: Bearer`.
2. A **browser session** for `qoder.com` or `qoder.com.cn`, filled by Settings → Read from browser. Cookies expire; that is why the token is preferred when the stored string is one.

The CLI file under `~/.qoder/.auth` is encrypted and is **not** borrowed. Do not document how to copy the cookie by hand.

## Route

Tried per site (`qoder.com`, then `qoder.com.cn`):

- `GET /api/v2/me/usages/big_model_credits` — **Team Plan** only (`plan_quota`). Measured 2026-09-08: a Team card of 51 / 6,000 lives here; Add-on Credits do not.
- `GET /api/v1/me/organization-shared-usages/big_model_credits` — **Add-on Credits**, the member cap on the org pool (`shared_quota.quota_summary`, e.g. 0 / 314,000). `organization_pool` is the org-wide barrel and is **not** drawn: the usage page shows the member cap.

Not a Pulse official-integration claim; the JSON can change.

## What is shown

- Team Plan — `plan_quota` / `total_quota` / `userQuota`. Monthly sort key, `reportsLength: false`.
- Personal resource pack — `resource_package_quota` when its limit is above zero.
- Add-on Credits — `shared_quota` from the organisation-shared endpoint. No cap means no ring.
- `userType` is the plan name.
- Remaining Credits are `creditBalance` when the remaining figure is above zero.

A limit of nothing is dropped rather than shown as 0%. Exhausted when remaining is 0 or used has reached the limit — Qoder then falls back to basic models; Pulse reports the Credits window as spent.
