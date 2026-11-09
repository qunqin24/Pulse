# Set up Xiaomi Coding Plan in Pulse

Pulse shows your Xiaomi Coding Plan's monthly token allowance (used out of your plan's limit) as a ring, plus your account balance alongside it. If your account has no Coding Plan — only pay-as-you-go inference — Pulse says so instead of drawing a ring.

## What you need

A Xiaomi MiMo open-platform account with a Coding Plan, signed in to a browser at platform.xiaomimimo.com.

## Steps

1. Sign in at https://platform.xiaomimimo.com in your browser.
2. In Pulse, go to Settings → Xiaomi Coding Plan and turn on "Show in panel". Under "Read from browser", pick the browser you signed in with (or leave it on Automatic) and click "Read".
   - Chrome, Edge, Brave, Arc, Vivaldi, and ego lite: macOS asks once for keychain permission.
   - Safari: give Pulse Full Disk Access first, in System Settings → Privacy & Security.
   - Firefox: nothing extra.
3. Success looks like a ring for Xiaomi Coding Plan on the Pulse panel, showing tokens used this month, plus your account balance.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Sign in to Xiaomi's platform in a browser to see usage. | Sign in at platform.xiaomimimo.com, then click "Read" again. |
| Xiaomi's saved session expired. Sign in again in your browser. | Sign in again at platform.xiaomimimo.com, then click "Read" again. |
| No Coding Plan on this Xiaomi account. | This is expected if you only pay for inference by usage — there is no monthly plan to show a ring for. |

## What Pulse reads

Pulse reads your session for platform.xiaomimimo.com from the browser each time it checks, keeps only the cookies that site needs to answer, and sends them only to platform.xiaomimimo.com. Everything else your browser holds is left alone.
