# Set up Devin in Pulse

Pulse shows Devin's daily and weekly usage remaining, as percentages, when your plan reports them, plus a credit balance if your account carries one. A free plan with no percentages shows a messages-left count instead.

## What you need

A Devin (Cognition) account. Either the Devin Mac app, signed in, or a Chromium-based browser (Chrome, Edge, Brave, Arc, Vivaldi, or ego lite — not Safari or Firefox) signed in at app.devin.ai.

## Steps

1. Sign in at https://app.devin.ai in a Chromium browser, or open the Devin Mac app and sign in there. Either is enough on its own.
2. In Pulse, go to Settings → Devin and turn on "Show in panel". Under "Read from browser", pick the browser you signed in with (or leave it on Default browser) and click "Read". Nothing needs to be pasted, and there is no keychain prompt.
3. Success looks like a ring for Devin on the Pulse panel, showing your daily and weekly usage remaining (or a messages-left count on a free plan).

Pulse can only read Chrome, Edge, Brave, Arc, Vivaldi, and ego lite for Devin. If you use Safari or Firefox, either sign in at app.devin.ai once in one of those, or just open the Devin Mac app: without a browser session, Pulse shows the plan the app saved the last time it started. That is a snapshot, so the card marks it "as of" when the app last launched — open the app again to refresh it.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Devin isn't installed. | Install the Devin Mac app, or use the browser session route instead. |
| Open Devin and sign in, so it can record your plan. | Open the Devin Mac app and sign in — it saves your plan the moment it starts. |
| No Devin session found. Sign in at app.devin.ai first. | Sign in at app.devin.ai in the browser Pulse is set to read, then click "Read" again. |

## What Pulse reads

Pulse reads your app.devin.ai session from a Chromium browser's local storage each time it checks and sends it only to app.devin.ai — nothing is saved on this Mac. The saved-plan fallback reads, read-only, a file the Devin Mac app already wrote to your Application Support folder; it needs no permission and no network access.
