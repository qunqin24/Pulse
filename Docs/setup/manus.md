# Set up Manus in Pulse

Pulse shows your Manus credits: the plan's monthly credits and the credits that refresh daily, each as the share used, and your total credit balance.

## What you need

A Manus account, signed in to a browser at manus.im.

## Steps

1. Sign in at [manus.im](https://manus.im) in your browser.
2. In Pulse: **Settings → Manus**. Turn on **Show in panel**.
3. Under **Read from browser**, pick the browser you signed in with (or leave it on Default browser) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite: macOS asks once for keychain permission.
   - Safari: give Pulse Full Disk Access first, in System Settings → Privacy & Security.
   - Firefox: nothing extra.
4. Within a few seconds the ring appears, and the pane lists the daily limit, the monthly limit and the balance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| No session found. Sign in at manus.im first. | The browser has no Manus session. Sign in, then click **Read** again. |
| Read a browser session in Settings. | Click **Read** under **Read from browser**. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in to manus.im again, then click **Read** again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Manus sent something Pulse doesn't recognize, or reported no credits. |

## What Pulse reads

Only the `session_id` cookie is kept from the browser. It is stored encrypted on this Mac and sent only to Manus's own API (`api.manus.im`) when Pulse checks your credits.
