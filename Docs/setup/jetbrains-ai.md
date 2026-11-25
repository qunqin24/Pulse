# Set up JetBrains AI in Pulse

Pulse shows your JetBrains AI quota — how much of it is used, and when it refills — as a ring. It reads what your JetBrains IDE saved on this Mac. IDEs from version 2026.3 on no longer save the quota there; for those, you can sign in to your JetBrains account in Pulse, and Pulse asks JetBrains for the quota instead.

## What you need

A JetBrains IDE (IntelliJ IDEA, PyCharm, WebStorm, GoLand, Rider, Android Studio and the rest) with AI Assistant signed in and used at least once. With an IDE from 2026.3 on, also a JetBrains account with JetBrains AI (a licence such as AI Pro, or a seat in an organisation).

## Steps

1. Open your IDE and use AI Assistant once — ask it anything — so it checks your quota.
2. In Pulse: **Settings → JetBrains AI**. Turn on **Show in panel**.
3. Within a few seconds the ring appears. If you have several IDEs, Pulse reads the one that saved its quota most recently.

If Pulse says "The app didn't save a quota Pulse can read on this Mac.", your IDE keeps the quota in memory. Sign in:

1. In **Settings → JetBrains AI → Connection**, click **Sign in…** on the **JetBrains account** row.
2. Your browser opens a JetBrains page for the **Junie CLI**. Pulse uses that public sign-in; it has none of its own, so the page names Junie, not Pulse. Sign in and approve.
3. The browser shows "Signed in. You can close this page and go back to Pulse." The ring appears at the next refresh.

When the IDE's file holds a quota, Pulse still reads the file and sends nothing. **Sign out** on the same row deletes the login from this Mac.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Nothing saved on this Mac yet. Open the service's app once, then retry. | No IDE has saved a quota yet. Open an IDE, use AI Assistant once, then refresh. |
| The app didn't save a quota Pulse can read on this Mac. | Your IDE (2026.3 or later) keeps the quota in memory. Sign in to your JetBrains account on the **JetBrains account** row. |
| Sign in to this account again in Settings. | The JetBrains login Pulse saved has expired or was refused. Click **Sign in again…** on the **JetBrains account** row. |
| This account has no plan with usage limits. | The signed-in JetBrains account has no licence or seat with JetBrains AI switched on. Check that you signed in with the account your IDE uses. |
| No limits reported. | JetBrains or the IDE stated a quota without a size (a free or unlimited licence, for instance). There is nothing to draw a ring for. |
| Finish or close the sign-in already running, then try again. | All the local ports the Junie sign-in accepts (62345–62364) are in use, usually by another sign-in. Finish or close it, then try again. |
| The browser didn't come back. If it showed an error, try again. | The sign-in was not finished within five minutes. Click **Sign in…** again. |
| Couldn't read the reply. | The IDE's file or JetBrains' reply isn't in the shape Pulse knows; an update may have changed it. |

## What Pulse reads and sends

Pulse reads one file, `options/AIAssistantQuotaManager2.xml`, in your IDE's settings folder under `~/Library/Application Support/JetBrains` (or `~/Library/Application Support/Google` for Android Studio). It never writes to it and never reads the IDE's own login or the Keychain.

Only after you sign in, and only when that file holds no quota, Pulse sends requests to `oauth.account.jetbrains.com`, `api.jetbrains.cloud` and `api.jetbrains.ai` to read your quota. The login is stored encrypted on this Mac. Details: [../providers/jetbrains-ai.md](../providers/jetbrains-ai.md).
