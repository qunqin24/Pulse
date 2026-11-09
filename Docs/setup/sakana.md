# Set up Sakana AI in Pulse

Pulse shows your Sakana AI subscription's two limits — the 5-hour window and the weekly window — each as the percentage Sakana's console shows, and your pay-as-you-go credit balance when the console states it.

## What you need

A Sakana AI account, signed in to a browser at console.sakana.ai.

## Steps

1. Sign in at [console.sakana.ai](https://console.sakana.ai) and open **Billing** once to check it shows your usage.
2. In Pulse: **Settings → Sakana AI**. Turn on **Show in panel**.
3. Under **Read from browser**, pick the browser you signed in with (or leave it on Automatic) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite: macOS asks once for Keychain permission.
   - Safari: give Pulse Full Disk Access first, in System Settings → Privacy & Security.
4. Within a few seconds the ring appears, and the account's card lists the 5-hour and weekly limits, when each resets, your plan, and the balance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Click **Read** under **Read from browser**. |
| No session found. Sign in at console.sakana.ai first. | The browser has no Sakana session. Sign in there, then click **Read** again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in again at console.sakana.ai, then click **Read** again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | The billing page showed neither limit nor balance — the account may have no subscription, or Sakana changed the page. |

## What Pulse reads

Pulse reads only the console's sign-in cookie from your browser, stores it encrypted on this Mac, and sends it only to `console.sakana.ai`, asking for the same billing page you see. It does not follow redirects, so the cookie never goes anywhere else.
