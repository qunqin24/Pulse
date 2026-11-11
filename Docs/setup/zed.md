# Set up Zed in Pulse

Pulse shows two things from your Zed account, when the account has them: how much of your edit-prediction allowance is used, and how much of your token spending limit is spent.

## What you need

A Zed account, signed in at [zed.dev](https://zed.dev) in a browser on this Mac. Signing in only inside the Zed editor isn't enough: the editor keeps its login in the macOS Keychain, which Pulse doesn't read.

## Steps

1. Sign in at [zed.dev](https://zed.dev) in Safari, Chrome, Firefox or another browser on this Mac.
2. In Pulse: **Settings → Zed**. Turn on **Show in panel**.
3. Under **Connection**, next to **Read from browser**, pick the browser (or leave it on **Default browser**) and click **Read**. Chrome-family browsers may ask for Keychain access to their cookie store.
4. Within a few seconds the ring appears, and the account's pane lists what Zed reports.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Do step 3. |
| No session found. Sign in at zed.dev first. | Sign in at zed.dev in the browser you picked, then click **Read** again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in at zed.dev again, then click **Read**. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Zed changed its billing page, and Pulse doesn't recognize what it sent. |
| No limits reported. | Your plan has unlimited edit predictions and no spending limit is set, so there is nothing to measure against. |

## What Pulse reads

Pulse keeps only zed.dev's `zed.session` cookie, stores it encrypted on this Mac, and sends it only to Zed's own billing service (`cloud.zed.dev`) when it checks your usage.
