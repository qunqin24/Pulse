# Ollama Cloud (experimental)

This provider reads the two **account quota windows** shown on the signed-in
[Ollama settings page](https://ollama.com/settings): Session usage (5 hours) and
Weekly usage (7 days), including reset timestamps when present. It does not
convert local token counts into subscription balances.

## Set up

1. Sign in to Ollama in your own browser and open <https://ollama.com/settings>.
2. Open the browser's developer tools, choose **Network**, and reload the page.
3. Select the request to `https://ollama.com/settings`. Under **Request Headers**,
   copy the value of **Cookie** (including `Cookie:` is also accepted).
4. In Pulse, choose **Settings → Ollama Cloud**, enable **Show in panel**, paste
   into **Session cookie**, and press **Save**. Refresh and compare both windows
   and reset times with the web page.
5. Use **Clear** to delete the saved cookie. After session expiry, sign in again
   in your browser and replace it. Pulse does not refresh a browser login.

A session cookie can grant access to your account. Treat it as a password: do not
paste it into issues, PRs, chat, screenshots or repository files. Clear the
clipboard after copying. A normal Ollama API key is **not** a replacement.

## Security and privacy

- Only cookies explicitly provided in the field are used. There is no browser
  database scan, automatic import, login automation or CLI credential discovery.
- Only known session-cookie names are retained (`wos-session`, legacy
  `__Secure-session`, NextAuth session-token names and numbered chunks). Unrelated
  cookies are discarded. Malformed headers and control characters are refused.
- Cookies live in a separate, non-synchronizing macOS Keychain item. They do not
  enter preferences, the existing encrypted API-key file, tests or logs.
- Reads use a fixed HTTPS URL on `ollama.com`; **all redirects are refused** so a
  cookie cannot be forwarded to another host. Requests use an ephemeral session
  without a shared cookie store or URL cache. No model inference is performed.
- HTML stays in memory, is size-limited to 2 MiB, and is not saved or logged.
  External XML entities are disabled and entity declarations rejected.
- There is no persisted Ollama quota cache. Failed refreshes show an error; an
  in-flight response from a replaced/cleared cookie must not restore old quota.

## Supported data and limitations

This is **not a documented Ollama quota API**. The official
[Usage API documentation](https://docs.ollama.com/api/usage) covers token/duration
metrics from individual model responses. The upstream
[quota API request](https://github.com/ollama/ollama/issues/12532) tracks the gap.
Other tools, including [CodexBar's documented Ollama integration](https://github.com/steipete/CodexBar/blob/main/docs/ollama.md),
use the same signed-in page approach. These references informed the data-source
choice; this adapter uses its own Foundation XML document parser.

The parser accepts explicit `Session usage` and `Weekly usage` totals ending in
`% used`. It does **not** use the first model-segment width as the total, infer a
missing number, or treat a changed page as an empty balance. Both windows must be
present; invalid percentages, ambiguous totals and malformed timestamps fail
closed. Missing timestamps stay unknown. Local models, plan names, extra-usage
balances, hourly variants, team billing, and per-model usage are out of scope.

Ollama may change labels, page structure, authentication or anti-bot requirements.
A successful account login does not guarantee this integration will keep working.

## Validation

Run `./Scripts/test-ollama.sh`. It compiles the **production** client with Swift 6
and warnings as errors and exercises synthetic HTML, zero/exhausted quota,
missing/invalid/ambiguous data, reset association, sign-in pages, entity/size
limits, cookie filtering/header injection and HTTP response classification.
No private fixtures or real credentials are included.

The full application still requires Xcode, not only Command Line Tools:

```sh
./Scripts/check-localization.sh
swift build -Xswiftc -swift-version -Xswiftc 6
./Scripts/bundle.sh
```

Before marking this integration ready for release, manually verify:

- A real personal Cloud account's two percentages and reset times match the page.
- Save, clear, relaunch, invalid-cookie and expired-cookie handling work.
- Replacing a cookie during a refresh cannot restore the earlier account's data.
- A disabled provider produces no automatic settings requests.
- English/Chinese settings fit at supported display sizes; the rail icon renders.

Initial validation uses synthetic pages; live-account and full settings-UI checks
have **not** been completed. Never attach raw authenticated page HTML to a PR.
