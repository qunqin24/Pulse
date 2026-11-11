# Set up ZoomMate in Pulse

Pulse shows your ZoomMate AI credits: used out of your budget cap for the current billing cycle, with the date the cycle ends.

## What you need

A Zoom account with ZoomMate, signed in to a browser at [zoommate.zoom.us](https://zoommate.zoom.us).

## Steps

1. Sign in at [zoommate.zoom.us](https://zoommate.zoom.us) in your browser.
2. In Pulse: **Settings → ZoomMate**. Turn on **Show in panel**.
3. Under **Read from browser**, pick the browser you signed in with (or leave it on Default browser) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite: macOS asks once for keychain permission.
   - Safari: give Pulse Full Disk Access first, in System Settings → Privacy & Security.
   - Firefox: nothing extra.
4. Within a few seconds the ring appears. Its card shows "Credit allowance" and when the cycle ends.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Click **Read** under **Read from browser**. |
| No session found. Sign in at zoom.us first. | The browser picked has no Zoom session. Sign in at zoommate.zoom.us, or pick the browser you use it in. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in to ZoomMate again, then click **Read** again. |
| No limits reported. | The account is unlimited, or has no budget cap — there is nothing to draw a ring against. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | ZoomMate sent something Pulse doesn't recognize. These are ZoomMate's own web endpoints and may change. |

## What Pulse reads

Pulse keeps only Zoom's session cookie (and Cloudflare's clearance cookie beside it) from your browser, stores them encrypted on this Mac, and sends them only to ZoomMate's two API hosts, `ai.zoom.us` and `zoommate.zoom.us`. Each check exchanges the session for a short-lived token — the way ZoomMate's own page does — and reads your credit status with it. The token is not saved, and nothing is changed on your account. Credit history isn't read.
