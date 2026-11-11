# Set up Open Design in Pulse

Pulse shows your Open Design plan, OpenDesign Go included: its credit limits and when each resets (5 hours and 7 days on Go, 7 days on Plus, Pro and Max), plus the plan's name and, when Open Design states it, your wallet balance.

## What you need

An Open Design account with a plan, and either of these on this Mac:

- **A browser signed in at [open-design.ai](https://open-design.ai/cloud/dashboard).** This works for OpenDesign Go even if you only use its API key in Codex, Claude Code or CC Switch and never installed the app.
- **The Open Design app, signed in.** It saves the login in `~/.amr/config.json`, and Pulse reads it without any further step.

The OpenDesign Go API key itself can't be used: Open Design only shows usage to the account's sign-in, not to keys made for model calls.

## Steps

1. Sign in at [open-design.ai](https://open-design.ai/cloud/dashboard) in your browser (or sign in to the Open Design app).
2. In Pulse: **Settings → Open Design**. Turn on **Show in panel**.
3. Under **Read from browser**, pick the browser you signed in with (or leave it on Default browser) and click **Read**. With the app signed in instead, skip this step.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite: macOS asks once for keychain permission.
   - Safari: give Pulse Full Disk Access first, in System Settings → Privacy & Security.
   - Firefox: nothing extra.
4. Within a few seconds the ring appears, and the account's pane shows each limit, the plan and the balance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Sign in at open-design.ai and click **Read** (step 3), or sign in to the Open Design app. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in at open-design.ai again and click **Read**. |
| The saved login has expired. Sign in again with the service's own app or tool. | Sign in to the Open Design app again, then refresh Pulse. |
| This account has no plan with usage limits. | The account has no personal workspace or no plan Open Design reports limits for. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Open Design sent something Pulse doesn't recognize, or the plan has no limits and no wallet. |

## What Pulse reads

From the browser, only open-design.ai's sign-in cookies (`__Secure-better-auth.…`); from the app, the control key and API address in the `prod` profile of `~/.amr/config.json`. Either is sent only to Open Design (`amr-api.open-design.ai`, or for the app's login another `https` address on `open-design.ai` it saved). Pulse doesn't change Open Design's files and doesn't sign you out anywhere.
