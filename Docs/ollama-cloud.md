# Ollama Cloud

This provider reads the two **account quota windows** shown on the signed-in
[Ollama settings page](https://ollama.com/settings): session usage (5 hours) and
weekly usage (7 days), with their reset times when the page carries them. It
does not turn local token counts into a subscription balance.

Ollama publishes no quota API. The official
[usage API](https://docs.ollama.com/api/usage) reports token and duration
metrics from individual model responses, and the
[request for a quota endpoint](https://github.com/ollama/ollama/issues/12532)
is still open — so a signed-in page is the only place these figures exist.
Other tools read them the same way, including
[CodexBar](https://github.com/steipete/CodexBar/blob/main/docs/ollama.md).

Originally contributed by [@PcOffeeP](https://github.com/PcOffeeP)
([#8](https://github.com/qunqin24/Pulse/pull/8)); the parser and the security
notes below are theirs. Pulse reworked how the session is obtained and where it
is kept — see below.

## Set up

Sign in to Ollama in your own browser, then in Pulse open **Settings → Ollama
Cloud**, switch on **Show in panel**, and press **Read from browser**.

That is the whole thing. **Pulse reads the session out of your browser for
you** rather than asking you to copy a cookie out of the developer tools —
which was the original flow, and is a step nobody performs correctly at two in
the morning. What that costs you is stated on the row before you press it:

- **Your default browser is tried first**, whichever it is, and the row names
  it. That is deliberate over trying the cheapest browsers first: the browser
  you open links with is where you are actually signed in, and a session pulled
  from some other browser may be months out of date. Pick a specific one under
  **Browser** if you would rather — naming one means *only* that one is opened.
- **Safari needs Full Disk Access**, because its cookie file lives inside its
  container. Only the installed `Pulse.app` can be granted it; a `swift run`
  build cannot.
- **Chrome, Edge, Brave and Arc keep their key in the login keychain**, so
  macOS will ask once — "Pulse wants to use your confidential information".
  The row says so before you press it.
- **Firefox** is plain SQLite and asks for nothing.

**Clear** deletes the saved session. When it expires, sign in again in your
browser and press **Read from browser** again — Pulse cannot renew a browser
login.

A session cookie grants access to your account. Treat it as a password: do not
paste it into issues, pull requests, chat, screenshots or repository files.

## What is read, and what is not

- **One host.** Firefox and Chromium are queried for `ollama.com`, its
  dot-form, and its subdomains. Safari's file is a binary format with no query
  language, so the same rule is applied by hand — a suffix match is *not* that
  rule and would have returned `notollama.com` and `evil-ollama.com` alongside
  the real host. Verified against a `binarycookies` file built for the purpose.
- **Only the names that authenticate** survive the read: `wos-session`, the
  legacy `__Secure-session`, NextAuth session-token names and their numbered
  chunks. Everything else — analytics, preferences — is discarded inside the
  call and never reaches storage. Malformed headers and control characters are
  refused.
- **A repeated name is kept, not rejected.** Browsers routinely hold both a
  host-only and a domain row for the same session name, and the host rule
  returns both on purpose; throwing on the duplicate discarded the whole
  browser silently and moved to the next one, which then reported a session
  read from a browser you had never signed in at.
- Nothing else in the cookie store is read, copied, or kept. No login is
  automated, no CLI credential is discovered, and no other domain is touched.

## Where the session is kept

In `keys.dat`, Pulse's own encrypted store — AES-GCM boxes in its Application
Support folder, owner-only, with the key derived from this Mac rather than
stored ([`APIKeyStore.swift`](../Sources/Pulse/APIKeyStore.swift)).

**Not the keychain**, which is what the original contribution used. Pulse holds
no keychain item of its own anywhere; one encrypted store for every secret it
keeps means one piece of crypto to be right about, and it is the same store the
OpenCode Go and Kimi Code keys live in. Nothing is written to `UserDefaults`,
which is a plist any process running as you can read.

## Reading the page

- A fixed HTTPS URL on `ollama.com`, with **all redirects refused** so the
  cookie cannot be forwarded to another host. An ephemeral session, with no
  shared cookie store and no URL cache. No inference is performed.
- The HTML stays in memory, is capped at 2 MiB, and is neither saved nor
  logged. External XML entities are disabled and entity declarations rejected.
- The parser accepts explicit `Session usage` and `Weekly usage` totals ending
  in `% used`. It does **not** take the first model segment's width as the
  total, infer a missing number, or read a changed page as an empty balance.
  Both windows must be present; invalid percentages, ambiguous totals and
  malformed timestamps fail closed, and a missing timestamp stays unknown.
- Local models, plan names, extra-usage balances, hourly variants, team billing
  and per-model usage are out of scope.

**A successful reading is cached like every other provider's**
([`UsageCache.swift`](../Sources/Pulse/UsageCache.swift)), so a later refusal
shows the last good figures with the time they were taken rather than an error
with nothing. Only `.live` readings are stored, they come back marked stale,
and a window whose reset time has passed is dropped rather than aged. The
original contribution deliberately cached nothing here; the cache's two rules
are what make it safe, and they are not specific to this provider.

Ollama may change its labels, page structure, authentication or anti-bot
requirements at any time. Being able to sign in is no guarantee this keeps
working.

## Checking it

There is no test target in this repository. The parser, the cookie filter and
both cookie-store formats are driven from throwaway probe packages against data
built on purpose — a `binarycookies` file assembled record by record, and
Chromium values encrypted with the same PBKDF2/AES-128-CBC scheme — so none of
it needs anybody's real credentials to verify. What that cannot cover is
finding the files and reading them on a real machine.

```sh
./Scripts/check-localization.sh
swift build -Xswiftc -swift-version -Xswiftc 6
./Scripts/bundle.sh
```

Never attach raw authenticated page HTML to a pull request.
