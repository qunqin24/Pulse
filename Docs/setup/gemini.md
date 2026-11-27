# Set up Gemini CLI in Pulse

Pulse shows how much of each Gemini model's quota is left in Gemini CLI, one row per model, as the fraction Google reports, with the time each one resets.

## What you need

[Gemini CLI](https://github.com/google-gemini/gemini-cli), signed in with a Google account (**Login with Google**). A Gemini API key or Vertex AI sign-in has no quota Pulse can read.

Google stopped serving Gemini CLI to individual, AI Pro and Ultra accounts in June 2026. Workspace, education and Code Assist Standard/Enterprise accounts still work.

## Steps

1. In Terminal, run `gemini` and sign in with Google if it asks.
2. In Pulse: **Settings → Gemini CLI**. Turn on **Show in panel**. There's nothing to paste: Pulse reads the login Gemini CLI saved.
3. Within a few seconds the ring appears, and the account's pane lists each model's quota and when it resets.

Gemini CLI's login lasts about an hour, and only Gemini CLI renews it. If you haven't used Gemini CLI for a while, Pulse says the login has expired — run any `gemini` command and refresh.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Sign in with this service's own app or command-line tool first. | Run `gemini` and choose **Login with Google**. If Gemini CLI is set to an API key or Vertex AI, switch it to a Google login. |
| The saved login has expired. Sign in again with the service's own app or tool. | Use Gemini CLI once (any command), then refresh. If that doesn't help, sign in again in Gemini CLI. |
| This account has no plan with usage limits. | Google no longer serves Gemini CLI for this account's tier. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Google sent something Pulse doesn't recognize, or reported no quota for this account. |

## What Pulse reads

`~/.gemini/settings.json` (only to see how Gemini CLI signs in) and the access token in `~/.gemini/oauth_creds.json`. Pulse never writes to either file and never renews the token. The token is sent only to Google (`cloudcode-pa.googleapis.com`) when Pulse checks your quota.
