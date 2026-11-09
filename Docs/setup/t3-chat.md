# Set up T3 Chat in Pulse

Pulse shows your T3 Chat usage: the four-hour window and the monthly allowance, each as the percentage T3 Chat reports.

## What you need

A T3 Chat account, signed in to a browser (Safari, Firefox, Chrome, Edge, Brave, Arc, Vivaldi or ego lite). T3 Chat has no API key for this — the reading comes from your signed-in session.

## Steps

1. Sign in at [t3.chat](https://t3.chat) in your browser.
2. In Pulse: **Settings → T3 Chat**. Turn on **Show in panel**. Under **Read from browser**, pick your browser (or leave it on Automatic) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite keep their cookies in the login keychain, so macOS asks once for permission.
   - Safari needs Full Disk Access for Pulse in System Settings → Privacy & Security.
   - Firefox needs nothing extra.
3. Within a few seconds the ring appears, and the account's pane lists the four-hour window and the monthly allowance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Sign in at t3.chat in your browser, then click "Read" again. |
| No session found. Sign in at t3.chat first. | Pulse looked in your browser and found no T3 Chat sign-in. Sign in there, then click "Read" again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in again at t3.chat, then click "Read" again — Pulse can't renew a browser login on its own. |
| Checking too often — easing off. | T3 Chat's edge may be asking for a browser check. Open t3.chat in your browser, then click "Read" again later. |
| The service didn't respond. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | T3 Chat changed what its settings page receives, or reported no usage figures. |

## What Pulse reads

Pulse reads only T3 Chat's sign-in cookie out of your browser, keeps it encrypted on this Mac, and sends it only to `t3.chat` — to the same request T3 Chat's own settings page makes for your usage.
