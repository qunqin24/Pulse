# Qoder

Service: [`QoderUsageService.swift`](../../Sources/Pulse/QoderUsageService.swift).

Extra accounts are not supported. `keepsLocalTranscripts` is false. First-run detection: `Qoder.app`, `Qoder IDE.app`, or `~/.qoder`. A session still has to be read in Settings — presence of the app is not a cookie.

## Credential

A browser session for `qoder.com` or `qoder.com.cn`, stored in `keys.dat`. Settings offers the same “Read from browser” row as Ollama. The CLI file under `~/.qoder/.auth` is encrypted and is **not** borrowed.

Do not document how to copy the cookie by hand.

## Route

`GET https://qoder.com/api/v2/me/usages/big_model_credits` (then `qoder.com.cn` if that session is refused). Cookie header, `Origin` / `Referer` of the matching site. Not a Pulse official-integration claim; the JSON can change.

## What is shown

- `totalQuota.quotaSummary` — the plan Credits window (`usedValue` / `limitValue`). Monthly sort key, `reportsLength: false`. Reset from `nextResetAt` when present.
- `sharedQuota` — a second window when the account has org shared Credits, scoped “Shared”.
- `userType` is the plan name.
- Remaining Credits are `creditBalance` when the remaining figure is above zero.

A limit of nothing is dropped rather than shown as 0%. Exhausted when remaining is 0 or used has reached the limit — Qoder then falls back to basic models; Pulse reports the Credits window as spent.
