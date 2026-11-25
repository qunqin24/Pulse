# Set up Grok in Pulse

Pulse shows your account's weekly Grok pool — the single allowance a SuperGrok or X Premium+ plan spends across Grok chat, Imagine, voice, the API, and Grok Build (the coding CLI). This is not the same as Grok Bot, which is a separate allowance billed through Cursor — see [Grok Bot setup](grok-bot.md) for that.

## What you need

A SuperGrok, SuperGrok Plus, SuperGrok Heavy, or X Premium+ subscription, and the Grok Build CLI installed and signed in on this Mac.

## Steps

1. Install Grok Build if you haven't already: `curl -fsSL https://x.ai/cli/install.sh | bash` (or `npm install -g @xai-official/grok`).
2. Run `grok login` in Terminal. It opens your browser to sign in with your xAI/X account, then stores the login at `~/.grok/auth.json`.
3. In Pulse, go to Settings → Grok and turn on "Show in panel". There is nothing to paste: Pulse reads the login the CLI just saved. The "Read usage from" row will say "Grok's own login".
4. Refresh Pulse (or wait for its next automatic check). A ring for Grok fills in on the Pulse panel with your weekly usage.

### Adding another Grok account

If you use more than one Grok account, go to Settings → Grok, and click "Add another account" in its Accounts group, then "Sign in…". Pulse shows a code and opens xAI's sign-in page — sign in there and approve the code. This is a separate login Pulse keeps for itself; it doesn't touch `~/.grok/auth.json` or your CLI session.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Sign in to Grok to see usage. | Pulse copies the command `grok` — run it in Terminal. If you're not signed in yet, it opens your browser to log in (or run `grok login` directly). |
| Grok's login expired. Use Grok to renew it. | Run `grok` (or `grok login`) again in Terminal to refresh the CLI's session. |
| Sign in to this account again in Settings. (added accounts) | Click "Sign in again…" next to that account. |
| The service didn't respond. | Click Retry. |
| Checking too often — easing off. | Click Retry after a minute. |
| The service returned an error. | Click Retry. |
| Couldn't read the reply. | The provider's reply changed shape. Try again later; if it keeps happening, [report it](https://github.com/qunqin24/Pulse/issues). |
| No limits reported. | Your account reported no usage windows. Check that your plan is active. |

## What Pulse reads

For your main account, Pulse reads the login the Grok Build CLI already saved at `~/.grok/auth.json` on this Mac — it doesn't store a copy. For any extra accounts you add, Pulse keeps its own sign-in, encrypted on this Mac, separate from the CLI's.
