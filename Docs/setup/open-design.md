# Set up Open Design in Pulse

Pulse shows your Open Design plan, OpenDesign Go included: its credit limits and when each resets (5 hours and 7 days on Go, 7 days on Plus, Pro and Max), plus the plan's name and your wallet balance.

## What you need

[Open Design](https://open-design.ai) signed in on this Mac, with the account your plan is on. Pulse reads the login Open Design saved, so there is no key to paste.

An OpenDesign Go API key — the one you put in Codex, Claude Code or CC Switch — can't be used here: Open Design only shows usage to the account login, not to keys made for model calls. Sign in to the Open Design app once with the same account instead.

## Steps

1. Open Open Design and sign in. It saves the login in `~/.amr/config.json`.
2. In Pulse: **Settings → Open Design**. Turn on **Show in panel**.
3. Within a few seconds the ring appears, and the account's pane shows each limit, the plan and the balance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Sign in with this service's own app or command-line tool first. | Sign in to Open Design (step 1). |
| The saved login has expired. Sign in again with the service's own app or tool. | Sign in to Open Design again, then refresh Pulse. |
| This account has no plan with usage limits. | The login has no personal workspace. Open Open Design once to finish setting up the account. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Open Design sent something Pulse doesn't recognize, or the account has no plan limits and no wallet. |

## What Pulse reads

Pulse reads the control key and the API address from the `prod` profile in `~/.amr/config.json`, and sends the key only to Open Design (`amr-api.open-design.ai`, or another `https` address on `open-design.ai` that Open Design saved). Pulse doesn't store the key and doesn't change Open Design's files.
