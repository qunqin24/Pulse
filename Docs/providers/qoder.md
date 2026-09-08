# Qoder

Service: [`QoderUsageService.swift`](../../Sources/Pulse/QoderUsageService.swift).

Extra accounts are not supported. `keepsLocalTranscripts` is false. First-run detection: `Qoder.app`, `Qoder IDE.app`, or `~/.qoder`. A session still has to be read in Settings — presence of the app is not a cookie.

## Credential

Two, same store (`keys.dat`):

1. A **personal access token** (`pt-…`). It lasts for the expiry set in the Qoder console. Pulse sends it as `Authorization: Bearer`.
2. A **browser session** for `qoder.com` or `qoder.com.cn`, filled by Settings → Read from browser. Cookies expire; that is why the token is preferred when the stored string is one.

The CLI file under `~/.qoder/.auth` is encrypted and is **not** borrowed. Do not document how to copy the cookie by hand.

## Route

Tried in order, international then China:

- `GET /api/v2/quota/usage` — CLI snapshot shape (`userQuota`, `org_resource_package`).
- `GET /api/v2/me/usages/big_model_credits` — dashboard shape (`totalQuota`, `sharedQuota`).

Not a Pulse official-integration claim; the JSON can change.

## What is shown

- Plan Credits — `totalQuota` / `userQuota`. Monthly sort key, `reportsLength: false`.
- Add-on Credits — `addOnQuota` when present, scoped “Add-on”.
- **Shared pack** — `sharedQuota` or `org_resource_package` (`cap` / `used` / `remaining`). This is the member cap on the organisation pool, not the pool itself. No cap means no ring: Pulse does not invent a percentage for an unlimited shared pack.
- `userType` is the plan name.
- Remaining Credits are `creditBalance` when the remaining figure is above zero.

A limit of nothing is dropped rather than shown as 0%. Exhausted when remaining is 0 or used has reached the limit — Qoder then falls back to basic models; Pulse reports the Credits window as spent.
