# Set up Perplexity in Pulse

Pulse shows the API credit on your Perplexity account as a dollar balance and, when your subscription's monthly credit is the only credit on the account, how much of it is used, as a ring with its renewal date.

## What you need

A Perplexity account, signed in to a browser at perplexity.ai.

## Steps

1. Sign in at [perplexity.ai](https://www.perplexity.ai) and open [your account's usage page](https://www.perplexity.ai/account/usage) once to check it shows your credit.
2. In Pulse: **Settings → Perplexity**. Turn on **Show in panel**.
3. Under **Read from browser**, pick the browser you signed in with (or leave it on Default browser) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite: macOS asks once for Keychain permission.
   - Safari: give Pulse Full Disk Access first, in System Settings → Privacy & Security.
4. Within a few seconds the account's card shows the balance, and the ring if there is one.

**Why there may be no ring.** Perplexity reports each credit grant and the total used, but not which grant the usage came out of. With a bonus or bought credit on the account beside the subscription's, Pulse can't say how much of the subscription's is gone, so it draws no ring from Perplexity's own figures rather than guess. A ring there is Pulse's own estimate of the balance: **Ring measures** on the account's pane picks what it measures — **Since top-up** (the default), **My budget**, or **Balance only** for no ring.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Click **Read** under **Read from browser**. |
| No session found. Sign in at www.perplexity.ai first. | The browser has no Perplexity session. Sign in there, then click **Read** again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in again at perplexity.ai, then click **Read** again. Perplexity's bot screen can also turn a request away this way; opening the site in the same browser and reading again usually helps. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Perplexity sent something Pulse doesn't recognize, or reported no credit at all. |

## What Pulse reads

Pulse reads only Perplexity's sign-in cookie from your browser, stores it encrypted on this Mac, and sends it only to `www.perplexity.ai`, asking the same thing your account's usage page asks. It does not follow redirects, so the cookie never goes anywhere else.
