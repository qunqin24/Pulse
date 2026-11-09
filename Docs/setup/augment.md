# Set up Augment Code in Pulse

Pulse shows how much of your Augment Code credit allowance is used this billing cycle, and when the cycle ends.

## What you need

An Augment Code account, signed in at [app.augmentcode.com](https://app.augmentcode.com) in your browser. Pulse reads that browser session; there's no API key for this.

## Steps

1. Sign in at [app.augmentcode.com](https://app.augmentcode.com) in your browser.
2. In Pulse: **Settings → Augment Code**. Turn on **Show in panel**. Under **Read from browser**, pick your browser (or leave it on Automatic) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite keep their cookies in the login keychain, so macOS may ask once for permission.
   - Safari needs Full Disk Access for Pulse, in System Settings → Privacy & Security.
3. Within a few seconds the ring appears, and the account's pane shows the credits used and when they reset.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| No session found. Sign in at app.augmentcode.com first. | Sign in in that browser, then click **Read** again. |
| Read a browser session in Settings. | Click **Read** under **Read from browser**. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in again at app.augmentcode.com, then click **Read** again. Pulse can't renew a browser login on its own. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Augment sent something Pulse doesn't recognize, or it didn't state how many credits the cycle has — Pulse doesn't guess the allowance. |

## What Pulse reads

Pulse keeps only Augment's session cookies from your browser, stores them encrypted on this Mac, and sends them only to `app.augmentcode.com` when it checks your usage. It reads your credit figures, your plan's name and the cycle's end date; it doesn't change anything on the account, and it doesn't keep the session alive on its own.
