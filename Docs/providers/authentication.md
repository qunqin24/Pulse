# Authentication and credentials

Pulse is not an official integration of any of these products. Where it signs in, it drives a **public client the product already ships** (a CLI, an editor plugin, a login page). Settings says so before anyone starts: the consent page names that product, not Pulse, and the provider can change or withdraw the client.

Current code: [`OAuthLogin.swift`](../../Sources/Pulse/OAuthLogin.swift), [`LoopbackCallback.swift`](../../Sources/Pulse/LoopbackCallback.swift), [`GitHubDeviceLogin.swift`](../../Sources/Pulse/GitHubDeviceLogin.swift), [`CursorWebLogin.swift`](../../Sources/Pulse/CursorWebLogin.swift), [`AccountCredentials.swift`](../../Sources/Pulse/AccountCredentials.swift), [`APIKeyStore.swift`](../../Sources/Pulse/APIKeyStore.swift), [`LocalSecrets.swift`](../../Sources/Pulse/LocalSecrets.swift), [`BrowserCookies.swift`](../../Sources/Pulse/BrowserCookies.swift), [`ClaudeDesktopSession.swift`](../../Sources/Pulse/ClaudeDesktopSession.swift).

This is not a catalogue of secrets. Client ids below are public (they ship in every copy of those CLIs and plugins). Do not copy refresh tokens, cookies, or `accounts.dat` / `keys.dat` into issues.

## Three kinds of secret, three stores

| What | Where | Who renews it |
|---|---|---|
| Pasted API key or Ollama session cookie | `keys.dat` (`APIKeyStore`) | Nobody. User pastes or re-reads the browser. |
| Copilot GitHub token | `keys.dat` as well (`keepsOwnCredential`) | Sign in again. Device tokens here are not the CLI refresh path. |
| Extra-account logins (Claude Code, Codex, Grok, Grok Bot) | `accounts.dat` (`AccountCredentialStore`) | `UsageStore.fetchAdded` via `OAuthLogin.refresh` for the three OAuth providers. Grok Bot has **no** refresh endpoint in Cursor’s client. |

Both files are AES-GCM boxes in Pulse’s Application Support folder, owner-only, key derived from this Mac rather than stored. `LocalSecrets` is shared so there is one copy of the crypto; a different derived key per purpose means a box from one store cannot be opened by the other.

A file that exists but will not decode is **not** empty. Treating it as empty meant saving one provider’s key silently threw away every other provider’s — and said it had succeeded. Saving refuses instead.

Pulse does **not** keep a Keychain item of its own for these. Chromium / Claude Desktop / Safari reads may *prompt* for someone else’s Safe Storage key; that is borrowing, not Pulse storing a secret there.

**Do not say “only OpenCode Go holds a credential” or “Pulse never holds a credential”.** Primary Claude Code, Codex, Cursor, Grok, Grok Bot, and Antigravity borrow another tool’s login. Pulse *does* hold pasted keys, Ollama sessions, Copilot’s token, and every extra-account login.

## Why sign in at all, rather than copy the CLI

Measured: a Codex access token lives on the order of 240 hours; a Claude Code one about five; a Grok CLI token about six hours. Copying the credential would leave the account you are *not* currently using dead within an afternoon. The only way to renew a copied token is the refresh token the CLI is also relying on — which, if the provider rotates it, signs the user out of their own CLI.

Pulse’s extra-account login has its own refresh token and does not read or write what the CLI stored. That separation is the reason for signing in.

`fetchAdded` renews when the access token is within a minute of expiry. A renewal that fails reports `.signedOut`, not a network error: the remedy is the same and the user can act on it. That case names no provider.

## Extra accounts: who can have them

[`Provider.supportsMultipleAccounts`](../../Sources/Pulse/MonitoredAccount.swift) is **`.claudeCode`, `.codex`, `.grok`, `.grokBot`**. Not two. Not Cursor.

- Claude Code / Codex / Grok: `OAuthLogin` public CLI clients.
- Grok Bot: **not OAuth** — [`CursorWebLogin`](../../Sources/Pulse/CursorWebLogin.swift) (Cursor’s login page + poll).
- Cursor itself is omitted on purpose. See [cursor.md](cursor.md) and [grok-bot.md](grok-bot.md).

`AccountKey` for the first account is the provider’s raw value (`claudeCode`, not `claudeCode#…`). Added accounts get a slot generated once and never reused, so removing one and adding another cannot inherit settings.

## OAuth: Claude Code, Codex, Grok

Pulse cannot register an OAuth application with these providers. `OAuthLogin.Configuration.of` is read from the installed CLI / the provider’s discovery document rather than remembered. A flow with one parameter wrong fails in a way that looks like the user’s fault.

### Claude Code — redirect, any loopback port

- Authorize `https://claude.com/cai/oauth/authorize`, token `https://platform.claude.com/v1/oauth/token`.
- Public client id from the CLI.
- Scopes: **`user:profile` only**. The CLI also asks for inference and session scopes, which would let Pulse **spend** the plan it is only supposed to report on.
- Token endpoint takes **JSON**. Exchange **carries `state`**.
- Extra authorize item `code=true`.
- `fixedPort` is nil: any loopback port, path `/callback`.
- No device flow. Loopback code in `LoopbackCallback` exists for this provider.

### Codex — device code, not redirect

Codex is signed in by OpenAI’s device-code shape (`codex-rs/login/src/device_code_auth.rs`), **not** by a loopback redirect.

1. `POST /api/accounts/deviceauth/usercode` → short code.
2. User types it at `auth.openai.com/codex/device`.
3. Poll `POST /api/accounts/deviceauth/token` — **403 and 404 both mean “still waiting”** (their convention, not RFC 8628’s `authorization_pending`).
4. Reply is an authorization code **and the proof key the provider generated itself**, exchanged against their `deviceauth/callback`.

Nothing is redirected back to this Mac, so there is no local port to collide with the CLI’s own sign-in.

**The redirect flow does not work here.** Matching it field for field to the published client still ended on OpenAI’s hosted error page (`token_exchange_failed`) before the browser ever came back, twice. The loopback listener is kept for Claude Code.

**Scopes must be the full published set**, including `api.connectors.read` and `api.connectors.invoke`. Asking for a narrower set looked like good practice and ended on the same error page. Taken from `codex-rs/login/src/server.rs`. Also required: extra authorize items (`id_token_add_organizations`, `codex_cli_simplified_flow`, `originator=codex_cli_rs`); exchange is the four specification fields and **not** `state` (Anthropic’s does take it); form body percent-encoded strictly (`URLComponents` leaves `:` and `/` alone and would pass `+` through as a space).

The Codex CLI is open source. Read it rather than inferring from a binary’s strings — that is how the first two of these were got wrong.

A sign-in can fail entirely outside Pulse: the device page asks the user to sign in if the browser has no session, and OpenAI’s hand-off to a Google account has come back `token_exchange_failed` there while Pulse’s part had already succeeded (code on screen). Remedy: be signed in at chatgpt.com first. Worth remembering before reading a provider error as a Pulse bug.

### Grok — RFC 8628 device code

Parameters from `auth.x.ai/.well-known/openid-configuration`, not from CLI strings. Client id is the CLI’s and appears in `~/.grok/auth.json` as `oidc_client_id` after `grok login`.

Scopes: `openid email offline_access grok-cli:access`.

- `grok-cli:access` is what the CLI proxy is gated on.
- `email` stops two Grok accounts both being offered as “Grok”.
- Dropped from the CLI’s set: `profile`, `api:access`, conversation and workspace scopes (the last two would let Pulse read and write chats).
- **`billing:read` looks like the right scope and is refused.** Measured: the device endpoint answers `invalid_scope — Scope 'billing:read' is not allowed for this client`. Do not document it as missing-and-needed.
- That the remaining four are *enough* was settled by performing the sign-in (an added account reads both endpoints), not by reasoning about it. This is not a claim that a later change of server policy will keep working.

**Grok’s device flow is the specification’s; Codex’s is not.** They share a name and nothing else (`OAuthLogin.DeviceFlow`). Writing either as a special case of the other gives a parser that reads neither reliably.

On the standard flow a refusal and a “still waiting” arrive with the **same HTTP 400**; only the body’s `error` tells them apart. Measured against xAI with an unapproved code: `400 {"error":"authorization_pending"}`. `slow_down` lengthens the interval by the five seconds the specification names. The poll makes its own request rather than calling `post`, so “not yet” never travels as a `Failure` the UI would show every few seconds.

**xAI does send `verification_uri_complete`, and it is used.** Pre-filling is the device-code phishing attack only when the link comes from somebody else. Here Pulse asked for the code and opens the page itself. GitHub deliberately sends none (see Copilot). Use the field where the service offers it; never construct it where it does not. Still copy the code for a page that turns out not to fill itself in.

The redirect flow was not chosen for Grok. Cloudflare answers 403 to anything but a browser on `auth.x.ai/oauth2/authorize`, so whether the client accepts an arbitrary loopback port cannot be probed without performing a sign-in. Loopback fields are still filled from the CLI’s `http://127.0.0.1:<port>/callback` in case that changes.

### LoopbackCallback (Claude Code)

Binding is a **separate step** from waiting: the port is only known once the listener is ready, and the redirect address goes into the authorize request before the browser opens. Folding the two together produced a redirect to `localhost:0`.

Codex’s client is registered for exactly `http://localhost:1455/auth/callback` (unused now that Codex is device-code). Claude Code accepts any loopback port.

`state` is checked in the callback, handed over at `start(expecting:)` rather than at `awaitCode`: the browser can beat that call.

**Cancelling has to unwind the wait, not merely mark it cancelled.** A bare `CheckedContinuation` ignores cancellation; a 300-second timeout in an unstructured `Task` does not inherit it. Pressing Cancel left the attempt running, and five minutes later the abandoned cleanup wrote “the browser didn’t come back” over a second sign-in. `withTaskCancellationHandler` settles it. `OAuthLogin.post` lets `CancellationError` through instead of reporting the service failing to answer.

**A busy port does not fail an `NWListener`, it parks it in `.waiting`.** Only `.failed` / `.cancelled` were handled, so a fixed-port sign-in would hang with a dead button. Unreachable today (Codex moved to device flow, Claude binds `.any`) but a live trap for the next fixed-port provider.

Query values are read encoded and decoded here: a query string spells a space `+` and `URLComponents` will not undo that, while decoding before substitution turns a literal plus (`%2B`) into a space.

## GitHub Copilot — device code, `read:user` only

[`GitHubDeviceLogin`](../../Sources/Pulse/GitHubDeviceLogin.swift). This is a **security decision**, not a missing paste field.

The Copilot usage endpoint accepts any GitHub OAuth token — the one `gh` already holds works (verified historically). That token carries `repo` and `workflow`: the run of someone’s source code, handed over to draw a percentage. The device flow asks for `read:user` and nothing else.

Pulse cannot register an OAuth app with GitHub, so it drives the VS Code Copilot plugin’s public client. Consent page names the editor.

**The verification link must not carry the code.** RFC 8628 has `verification_uri_complete`; GitHub deliberately does not send one. Its page: *“Never use a code sent by someone else.”* Pre-filling **is** the device-code phishing attack. A `user_code` query parameter was tried and is ignored; it is not kept. The code goes on the clipboard instead. If a service ever offers `verification_uri_complete`, that is the service’s decision to make (Grok does; GitHub does not).

GitHub’s codes last fifteen minutes; polling patience is 900 seconds so Pulse does not report failure while the code on screen is still good.

The token is stored in `keys.dat` (`keepsOwnCredential`), not `accounts.dat`.

## Grok Bot extras — Cursor web login, not OAuth

Cursor publishes no authorize/token pair for a third party. Calling this OAuth sets the wrong expectations.

1. Browser: `https://cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&redirectTarget=sand`.
2. Poll: `https://api2.cursor.sh/auth/poll?uuid=…&verifier=…`. **404 means “not yet”, not “wrong address”.** Only a 403 carrying `error` ends the attempt.

Proof key is PKCE’s algorithm. The verifier is 32 random bytes **base64url-encoded**; the challenge is the base64url of the SHA-256 of **that encoded string**, not of the raw bytes. Read out of `Grok Bot.app` (`Contents/Resources/app.asar`), not inferred.

Tokens last about **sixty days** (measured from `exp` on one Mac). No refresh endpoint exists in Cursor’s client. When one ages out, `fetchAdded` reports `.signedOut` and the remedy is to sign in again.

`OAuthLogin.Configuration.of(.grokBot)` is nil. `fetchAdded` still calls `OAuthLogin.refresh` when the token is no longer fresh; that fails closed into `.signedOut`, which is the honest path.

Pulse does **not** read `~/Library/Application Support/Grok Bot/sand-secrets.json`. That file was identified during investigation; the extra-account token Pulse obtained itself is what is stored.

## Browser cookies — Ollama Cloud only

[`BrowserCookies.swift`](../../Sources/Pulse/BrowserCookies.swift) exists because Ollama publishes no quota API. Setup, host filter, and parser rules: [`../ollama-cloud.md`](../ollama-cloud.md).

**User-browser cookie reading is not how Claude, Cursor, or anyone else authenticates.** Claude Desktop borrows the *desktop app’s* Chromium cookie store (`sessionKey` / `sessionKeyV3` on `claude.ai`) via [`ClaudeDesktopSession`](../../Sources/Pulse/ClaudeDesktopSession.swift) — a different path, gated on a Keychain grant for `Claude Safe Storage`. Cursor **builds** a `WorkosCursorSessionToken` from the editor’s SQLite token; it does not open Safari or Chrome.

Failure class this feature keeps rediscovering: **a wrong lookup reads as an empty one**, then the next browser is tried, and Settings reports a session from a browser the user never signed in at.

- Safari host match must not be a suffix (`notollama.com`).
- Duplicate cookie names are normal (host-only + domain); throwing discarded the whole browser.
- Edge’s keychain service is `Microsoft Edge Safe Storage`, not a name derived from the display string “Edge”.
- Default browser first, even if it prompts. A cheap browser with a months-stale session is worse than a prompt.
- Naming a browser in Settings means *only* that one is opened.

Parsers were driven against data built on purpose (synthetic `binarycookies`, Chromium values encrypted with the documented scheme). File discovery on a real machine is not claimed as verified here.

## Claude Desktop Keychain grant

There is no way to ask the Keychain for an item silently (`SecKeychainSetUserInteractionAllowed` is deprecated with no replacement). [`AppDelegate`](../../Sources/Pulse/AppDelegate.swift) asks for `Claude Safe Storage` once at launch, fenced three ways: a desktop cookie store exists, Claude Code is enabled with source Automatic or Desktop App, and **once** — a refusal is a decision.

`.automatic` then reads the remembered grant (`usageIfAlreadyPermitted`) rather than raising the dialog. Pinning `.desktopApp` calls `usage` directly, so a first-time pin can prompt there.

A grant that stops working is asked about again rather than treated as asked-and-refused: the Keychain ties the allowance to the code signature, and Pulse is ad-hoc signed, so every update is a different app as far as the ACL is concerned.

The desktop session rides its own ephemeral `URLSession` so a `Set-Cookie` on those replies is never carried onto Pulse’s other requests. The session belongs to the desktop app and is borrowed for one call.

## What “not public API” means here

Most usage endpoints Pulse calls are **undocumented account or editor routes**. They can change without notice. A few paths are documented by the vendor (Claude Code’s status-line hook; Kimi’s usage URL as the service comments it; GitHub’s device-code *login*, not the Copilot quota JSON). None of that makes Pulse an official integration, and none of it is a promise the JSON will stay stable.

Do not write “official API” unless the vendor documents that exact usage contract. Do not write “the only credential is the provider’s” when Pulse also stores keys, sessions, Copilot tokens, and extra-account logins.
