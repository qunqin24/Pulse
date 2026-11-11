# Set up Qwen Cloud in Pulse

Pulse shows your Qwen Cloud individual Token Plan's allowances: the 5-hour window, the weekly window and the monthly allowance where the plan has one, each as the share Qwen Cloud reports used.

## What you need

A Qwen Cloud individual Token Plan, and a browser (Safari, Chrome, Edge, Brave, Arc, Vivaldi, ego lite or Firefox) signed in at [home.qwencloud.com](https://home.qwencloud.com/billing/subscription/token-plan-individual).

## Steps

1. Sign in at [home.qwencloud.com](https://home.qwencloud.com/billing/subscription/token-plan-individual) and open the Token Plan page once.
2. In Pulse: **Settings → Qwen Cloud**. Turn on **Show in panel**. Under **Read from browser**, pick the browser you signed in with (or leave it on **Default browser**) and click **Read**. Your Mac may ask to let Pulse use that browser's Keychain entry.
3. Within a few seconds the ring appears, and the account's pane lists the windows and when each resets.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Under **Read from browser** in Settings, click **Read**. |
| No session found. Sign in at qwencloud.com first. | Sign in at home.qwencloud.com in the browser you chose, then read again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in again at home.qwencloud.com, then click **Read** again. |
| This account has no plan with usage limits. | Qwen Cloud counts no Token Plan subscription on this account. |
| No limits reported. | Qwen Cloud answered with no 5-hour, weekly or monthly figure. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Qwen Cloud sent something Pulse doesn't recognize. |

## What Pulse reads

Pulse keeps only Qwen Cloud's sign-in cookies (the login tickets, account markers, CSRF token, browser id and security token) from `qwencloud.com`, stores them encrypted on this Mac, and sends them only to Qwen Cloud's own hosts (`home.qwencloud.com` and `cs-data.qwencloud.com`). Redirects are never followed with them.
