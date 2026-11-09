# Set up Raycast AI in Pulse

Pulse shows your Raycast AI credits: how much of the period's allowance is used, and when the next credits arrive.

## What you need

A Raycast account with AI credits (a Pro plan or higher), signed in at raycast.com in a browser.

## Steps

1. Sign in at [www.raycast.com](https://www.raycast.com) in your browser.
2. In Pulse: **Settings → Raycast AI**. Turn on **Show in panel**. Under **Read from browser**, pick your browser (or leave it on Automatic) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite keep their cookies in the login keychain, so macOS asks once for permission.
   - Safari needs Full Disk Access for Pulse in System Settings → Privacy & Security.
   - Firefox needs nothing extra.
3. Within a few seconds the ring appears, and the account's pane shows the credit allowance and when it renews.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Sign in at www.raycast.com in your browser, then click "Read" again. |
| No session found. Sign in at www.raycast.com first. | Pulse looked in your browser and found no Raycast sign-in. Sign in there, then click "Read" again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in again at www.raycast.com, then click "Read" again — Pulse can't renew a browser login on its own. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Raycast sent something Pulse doesn't recognize, or the account reports no credit total (for example, no AI plan). |

## What Pulse reads

Pulse reads only Raycast's session and CSRF cookies out of your browser, keeps them encrypted on this Mac, and sends them only to `www.raycast.com` — to the same request Raycast's own settings page makes for your credits. Nothing on this Mac's Raycast app is read.
