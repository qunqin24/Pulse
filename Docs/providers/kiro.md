# Kiro

Pulse reads Kiro's subscription credits through Kiro CLI's native Agent Client
Protocol (ACP). It starts a short-lived `kiro-cli acp --agent-engine v3`
process, completes the ACP handshake, calls `_kiro/account/getUsage`, and then
terminates the helper.

Kiro remains responsible for authentication and token refresh. Pulse does not
open Kiro's SQLite database, request Keychain access, copy an access token, or
store Kiro credentials.

Each pending RPC owns its 20-second timeout, cancelled when the request
finishes or the connection closes. Request IDs continue across refreshes;
old timeout callbacks and queued data from a closed pipe cannot affect the
next helper. Connection teardown also discards any incomplete JSON.

## Requirements

- Kiro CLI with the v3 ACP engine and `_kiro/account/getUsage` support
- an active Kiro CLI login

If Pulse says the CLI is too old, update Kiro CLI and refresh. If it says Kiro
is signed out, sign in with Kiro CLI first.

## What is reported

The ACP reply supplies the plan name, billing-cycle reset, and one or more
bounded credit pools. Pulse draws each bounded pool as a monthly window and
uses the provider's own `used` and `limit` values. The reset date is shown, but
the ring does not infer a fixed 30-day duration from a date-only reset.

This route was validated with Kiro CLI 2.22.1 (ACP agent server 0.66.4) against
the same signed-in account as Kiro's `/usage` panel. The plan, credits, and
reset matched.

The usage method is native structured ACP but is not currently advertised in
the initialize response's public `extensionMethods` list. Pulse therefore
calls it directly and reports a clear version error if Kiro removes or renames
it; it never falls back to scraping terminal output.
