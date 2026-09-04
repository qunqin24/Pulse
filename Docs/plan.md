# Claude Usage Reading Plan

## Current Automatic Flow

Pulse currently resolves the primary Claude Code account in this order:

1. OAuth Usage API
2. Claude Desktop Web API
3. Status Line capture
4. Last successful usage cache
5. An actionable unavailable reason

In shorthand:

```text
OAuth -> permitted Desktop session -> Status Line -> valid cache -> error
```

This is the current implementation, not a proposed replacement.

## Branching Rules

- A successful OAuth reading wins immediately.
- An expired or refused OAuth credential falls through to Claude Desktop.
- Automatic Desktop access runs only when Keychain access has already been granted, the session returns a live reading, and it can safely stand in for the CLI account.
- If Desktop cannot provide a live compatible reading, Pulse uses the latest Status Line capture whose windows have not reset.
- A Status Line capture is live for 10 minutes and stale afterwards. Stale captures remain eligible and are labelled with their observation time.
- OAuth network, rate-limit, or server failures currently skip Desktop and go directly to Status Line, then cache:

```text
OAuth network failure -> Status Line -> valid cache -> error
```

- `UsageCache` reconciles the service result after these source decisions. It keeps the newer real observation, marks restored readings stale, drops reset windows, and refuses entries older than 24 hours.
- If neither a source nor the cache has a usable reading, Pulse displays the specific unavailable reason.

## Startup And Permission Behavior

- At launch, Pulse restores the last valid cached reading before starting the first refresh, so the rail does not begin blank.
- When Claude Code is enabled and its source is Automatic or Desktop App, Pulse may request access to `Claude Safe Storage` once if a Claude Desktop cookie store exists.
- Automatic refreshes use the Desktop route only after that permission has been granted; they do not raise a new unsolicited Keychain prompt each pass.
- Explicitly pinning Endpoint, Provider Tooling, or Desktop App disables the normal cross-source fallback. Cache reconciliation still happens afterwards where its error rules allow it.
- Added Claude accounts use their own OAuth credentials only. The primary CLI Status Line and Desktop session are never substituted for an added account.

## Source References

- `Sources/Pulse/ClaudeCodeUsageService.swift`: automatic source selection and Status Line freshness.
- `Sources/Pulse/ClaudeDesktopSession.swift`: Desktop permission, account compatibility, cookies, and Web API calls.
- `Sources/Pulse/UsageCache.swift`: cache reconciliation, expiry, and stale-state rules.
- `Sources/Pulse/UsageStore.swift`: startup cache restoration and post-fetch reconciliation.
- `Sources/Pulse/AppDelegate.swift`: one-time Desktop Keychain permission request.

## Planned Feature: Grok Support

- Add Grok as a supported provider in Pulse.
- Track the implementation and scope in [Issue #9](https://github.com/qunqin24/Pulse/issues/9).
