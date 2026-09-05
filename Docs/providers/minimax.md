# MiniMax and MiniMax CN

One service, two providers: [`MiniMaxUsageService.swift`](../../Sources/Pulse/MiniMaxUsageService.swift).

| Provider | Ring name | Host | Icon |
|---|---|---|---|
| `.minimax` | MiniMax | `https://api.minimax.io` | `minimax` |
| `.minimaxCN` | MiniMax CN | `https://api.minimaxi.com` | `minimax` |

Same product, two storefronts, two accounts. There is no separate brand name for the mainland one, so the region is the distinction. A key for one is refused by the other. One mark: two accounts of one brand already share a mark on the rail.

Extra accounts are not supported. `keepsLocalTranscripts` is false. No first-run file detection.

## Route

`GET {host}/v1/token_plan/remains` with the key as a bearer token, falling back to the older `/v1/api/openplatform/coding_plan/remains` on a **404** (an older account, not a failure).

Undocumented; can change without notice. Parsing follows CodexBar’s written account of the reply.

The **first** failure reason is kept, not the last: a `.apiKeyRefused` from the current path must not be overwritten by a later miss.

`base_resp.status_code` is the service’s verdict and is **not** the HTTP status. A refused key is a perfectly good HTTP 200.

## Mapping

**It reports what is left.** `current_*_remaining_percent` at 96 means 4% spent. Inversion happens here. (Copilot and Antigravity also invert remaining-style fields; MiniMax’s file comment that Antigravity is the only other one is slightly behind Copilot.)

**Every figure can be a string or a number**, the same field in different replies. CodexBar’s own two fixtures disagree (`"96"` and `75`). Reading only one shape blanks a window for whichever accounts get the other.

**Lanes exist that the subscription does not include** — status 3, nothing issued, 100% remaining, a video lane on a plan with no video. Read literally that is a ring pinned at 0% for something the account cannot use, so they are left out. The same shape covers a genuinely unlimited lane, which has no percentage worth showing either.

**`*_usage_count` is the quota that is *left*, not the quota used** — the name says the opposite of what it holds. Reading it as a spend inverts every figure on the card. It is the fallback when the percentages are absent, which is the shape the older endpoint returns.

The payload is not always under `data`; some replies put it at the root. Reading only `data` reported a good account as having no limits.

Each model gives up to two windows. The short one’s length is measured from its own timestamps (5 hours, in every reply seen) and is **dropped when they are absent** rather than assumed. The weekly one names its own length so it survives that.
