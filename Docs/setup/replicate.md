# Set up Replicate in Pulse

Pulse shows the prepaid credit left on your Replicate account. Replicate reports no allowance or percentage, so the balance is the reading. Any ring is Pulse's own estimate, not a figure Replicate reported: **Ring measures** on the account's pane picks what it measures — **Since top-up** (the default), **My budget**, or **Balance only** for no ring.

## What you need

A Replicate account, signed in at [replicate.com](https://replicate.com) in a browser on this Mac. Your Replicate API token can't read billing, so it isn't used.

## Steps

1. Sign in at [replicate.com](https://replicate.com) in Safari, Chrome, Firefox or another browser on this Mac.
2. In Pulse: **Settings → Replicate**. Turn on **Show in panel**.
3. Under **Connection**, next to **Read from browser**, pick the browser (or leave it on **Default browser**) and click **Read**. Chrome-family browsers may ask for Keychain access to their cookie store.
4. Within a few seconds the account shows its credit balance.

If you belong to an organization, Pulse reads whichever account Replicate's billing page opens on.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Do step 3. |
| No session found. Sign in at replicate.com first. | Sign in at replicate.com in the browser you picked, then click **Read** again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in at replicate.com again, then click **Read**. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Replicate changed its billing page, and Pulse doesn't recognize it. |
| No limits reported. | Replicate didn't report a credit balance for this account. |

## What Pulse reads

Pulse keeps only replicate.com's `sessionid` and `csrftoken` cookies, stores them encrypted on this Mac, and sends them only to replicate.com: once for the billing page (to learn which account it is) and once for that account's credit balance.
