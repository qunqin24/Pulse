# Set up LongCat in Pulse

Pulse shows your LongCat API platform allowance — the tokens used out of your active token pack, or out of the account's allowance when there is no pack — and your fuel packs (加油包), with the soonest one to expire.

## What you need

A LongCat account, and a browser (Safari, Chrome, Edge, Brave, Arc, Vivaldi, ego lite or Firefox) signed in at [longcat.chat](https://longcat.chat/platform/).

## Steps

1. Sign in at [longcat.chat](https://longcat.chat/platform/) and open the platform's usage page once.
2. In Pulse: **Settings → LongCat**. Turn on **Show in panel**. Under **Read from browser**, pick the browser you signed in with (or leave it on **Default browser**) and click **Read**. Your Mac may ask to let Pulse use that browser's Keychain entry.
3. Within a few seconds the ring appears, and the account's pane lists the allowance and the fuel packs.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Under **Read from browser** in Settings, click **Read**. |
| No session found. Sign in at longcat.chat first. | Sign in at longcat.chat in the browser you chose, then read again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in again at longcat.chat, then click **Read** again. |
| No limits reported. | LongCat answered with no allowance or fuel pack that has both a total and an amount used or left. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | LongCat sent something Pulse doesn't recognize. |

## What Pulse reads

Pulse keeps only LongCat's `passport_token` and `uid` cookies from `longcat.chat`, stores them encrypted on this Mac, and sends them only to `longcat.chat`. Redirects are never followed with them.
