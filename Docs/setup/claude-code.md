# Set up Claude Code in Pulse

Pulse shows Claude Code's 5-hour limit and Weekly limit (Claude Code's own rate-limit windows), along with your plan name (for example "Max 5x").

## What you need

A Claude Pro or Max subscription, signed in to the Claude Code CLI (`claude`). The Claude desktop app can serve as a backup route if you use it too.

## Steps

1. Install Claude Code and run `claude` once in Terminal. On first run it opens your browser to sign you in with your claude.ai account; approve there.
2. In Pulse, go to Settings → Claude Code and turn on "Show in panel". Nothing else is required — Pulse reads the login Claude Code already saved on this Mac. If you want to see or change which route Pulse uses, the Connection group's "Read usage from" picker offers Automatic, Usage endpoint, Provider tooling, and Desktop app; Automatic is the right choice for almost everyone.
3. Optional backup: in the same Connection group, "Claude Code status line" → Connect lets Pulse also read the status line Claude Code prints after each response, so a reading is still available if your saved login expires. Your own status line keeps working alongside it.
4. To add a second Claude Code account, go to Settings → Claude Code, click "Add another account" in its Accounts group, and sign in on the page that opens. This is a separate sign-in from the CLI's own login, so both accounts keep reporting even if the CLI's token later expires.
5. Success looks like a ring for Claude Code on the Pulse panel, filled in with your 5-hour and weekly usage.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Connect Claude Code in Settings to see usage. | Connect the status line (step 3), or just use Claude Code once so it has something to report. |
| Sign in to Claude Code to see usage. / Claude Code's saved login expired. Use Claude Code, or connect the status line. | Run `claude auth login` in Terminal (or `/login` inside Claude Code), then click Retry. |
| Sign in to the Claude desktop app to see usage. / The Claude desktop app's session was refused. Open it and sign in again. | Open the Claude desktop app and sign in there, then click Retry. |
| Pulse needs keychain access for the Claude desktop app's session. Refresh to ask again. | Click Retry and approve the keychain prompt when macOS asks. |
| Sign in to this account again in Settings. (on an added account) | Open that account's Accounts section and click "Sign in again…". |

## What Pulse reads

Pulse reads the OAuth login Claude Code (or, as a fallback, the Claude desktop app) already stored on this Mac, and sends it only to Anthropic to ask for your usage. A second account added through "Add another account" is signed in separately through Pulse's own browser sign-in, and its login is stored on this Mac only.
