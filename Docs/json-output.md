# `Pulse --json`

Owns: the JSON contract other people's status lines are built on. Where the figures come from and how often they move: [refresh-and-data.md](refresh-and-data.md).

```bash
/Applications/Pulse.app/Contents/MacOS/Pulse --json
```

Source: [`Sources/Pulse/UsageReport.swift`](../Sources/Pulse/UsageReport.swift). Dispatched in `PulseMain` before `LegacyDefaults.migrateIfNeeded()`, alongside `--statusline`.

## It prints the cache and never fetches

A status line polls every couple of seconds. Fifteen providers cannot be asked at that rate, and a command that opened network connections and touched the keychain every time a terminal redrew would be a worse citizen than no command at all.

So this reads what the **running app** last banked and says how old it is. Every account carries `observedAt` and `ageSeconds`; decide for yourself what counts as too old. With the app not running the figures simply stop moving — they are never presented as current. An installation where the app has never run prints an empty rail rather than a guess at what would be switched on.

It **reads and never writes**. `AppSettings.storedRail()` exists for this: `restored()` stamps `hasRun`, the offered list and the resolved enabled set on its way through, which is right once at launch and wrong for something running every two seconds.

## Nothing in it is translated

Window names are localized in the app and would change under a script's feet, so `UsageWindow.name` is **not a field**. What is there instead:

- `kind` — a flat token: `fiveHour`, `weekly`, `spend`, `monthly`, or `other:<seconds>`. `UsageWindow.Kind` is `Codable`, but its synthesised form is an object with an associated value in it; fine on disk, awkward in a `jq` filter.
- `scope`, `name` — product names, the same in every language.
- `label` — the user's own name for an added account, theirs to have written in any language.

## Shape

```
generatedAt            ISO 8601
accounts[]
  id                   "claudeCode", "claudeCode#<slot>" for an added account
  provider             the Provider case
  name                 the product's name
  label                the user's name for it; the product's name for a first account
  plan                 when the provider names one
  creditBalance        when the provider reports one
  observedAt           when this reading was taken, absent when there is none
  ageSeconds           generatedAt − observedAt
  headline{}           the window the ring shows: windowId, usedPercent, exhausted, resetsAt
  windows[]
    id, kind, scope
    usedPercent        the figure the ring shows — the display rule, so a
                       status line agrees with the panel
    usedFraction       the reading itself, unrounded
    exhausted          the provider's word, not usedPercent >= 100
    windowSeconds
    reportsLength      false when windowSeconds is only a sort key. Do not divide by it.
    resetsAt
```

`headline` repeats a window from `windows` on purpose: the common case is one number in a status line, and making every consumer re-implement "which limit matters" — the fullest, or the provider's included pool, unless one is pinned — is how they end up disagreeing with the ring.

`usedPercent` carries the display rule, so anything used never reads 0% and not quite full never reads 100%. `UsageWindow.percentValue` is the one copy of it; `percentText` is that plus a `%`.

## Examples

```bash
# every account, one line each
Pulse --json | jq -r '.accounts[] | "\(.name) \(.headline.usedPercent // "–")%"'

# the limit closest to biting, across everything
Pulse --json | jq -r '[.accounts[] | select(.headline) | {n:.name, p:.headline.usedPercent}]
                      | max_by(.p) | "\(.n) \(.p)%"'

# anything whose figures have gone stale
Pulse --json | jq -r '.accounts[] | select((.ageSeconds // 1e9) > 1800) | .name'
```

## Adding a field

Additive changes are safe; renaming or removing one breaks somebody's status line. `UsageReportTests` pins the shape — add to it in the same patch.
