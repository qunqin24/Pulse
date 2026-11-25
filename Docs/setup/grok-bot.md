# Set up Grok Bot in Pulse

Pulse shows your weekly Grok Bot allowance — xAI's assistant sold through Cursor and billed against your **Cursor** account, not your Grok/SuperGrok account. It's a different bill from the "Grok" ring — see [Grok setup](grok.md) if that's the one you're after.

## What you need

Grok Bot access through Cursor Pro, Cursor Pro+, Cursor Ultra, a Cursor Teams seat, or a linked SuperGrok/X Premium+ account — either by signing in from Pulse's Settings in your browser (no Cursor installation required) or through the Cursor editor already signed in on this Mac.

Pulse does **not** read credentials saved inside the standalone `Grok Bot.app` (`sand-secrets.json`). If you only use the standalone Grok Bot app and do not have the Cursor editor installed, use **Sign in…** in Settings.

## Steps

1. In Pulse, go to Settings → Grok Bot and turn on "Show in panel".
2. If you already use the Cursor editor on this Mac and are signed in there, Pulse reads Cursor's saved login automatically.
3. Otherwise (for example, if Cursor isn't installed or you want to use a different Cursor account), click **Sign in…** next to **Cursor account** in Connection and finish signing in on Cursor's page in your browser. Pulse stores that login encrypted on this Mac for about 60 days before you'll need to sign in again; click **Sign out** to forget it and fall back to the Cursor editor's login.
4. Refresh Pulse (or wait for its next automatic check). A ring for Grok Bot fills in on the Pulse panel.

### Adding another account

If you have more than one Cursor account with Grok Bot, go to Settings → Grok Bot, and click "Add another account" in its Accounts group, then "Sign in…". Pulse opens Cursor's own sign-in page in your browser — sign in there. This login is kept separately from the primary account, and lasts about 60 days before you'll need to sign in again.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Sign in from Settings to see usage. | Click **Sign in…** next to **Cursor account** in Settings → Grok Bot (or sign in to Cursor on this Mac). |
| Sign in to this account again in Settings. | Click **Sign in again…** in Connection diagnostics (or, on the primary account, **Sign in again…** next to **Cursor account**). |
| Cursor's saved login was refused. Open Cursor to renew it. | Click **Open Cursor** and sign in again, or click **Sign in…** next to **Cursor account** in Settings to sign in via your browser instead. |
| Pulse needs your keychain to read Cursor's saved login. Refresh to be asked again. | Click **Retry** and allow Keychain access, or click **Sign in…** next to **Cursor account** in Settings. |
| This Cursor plan doesn't include Grok Bot. | Your current Cursor/Grok plan doesn't include a Grok Bot allowance. |
| The service didn't respond. | Click Retry. |
| Checking too often — easing off. | Click Retry after a minute. |
| The service returned an error. | Click Retry. |
| Couldn't read the reply. | The provider's reply changed shape. Try again later; if it keeps happening, [report it](https://github.com/qunqin24/Pulse/issues). |

## What Pulse reads

If you sign in next to **Cursor account** (or add an extra account), Pulse keeps the sign-in it obtained through Cursor's own login page encrypted on this Mac and uses that instead of the Cursor editor's files. Otherwise, Pulse reads the login Cursor's own editor already stored on this Mac — nothing is pasted, nothing extra is saved, and `Grok Bot.app`'s local storage is never opened.
