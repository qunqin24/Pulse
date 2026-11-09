# Set up StepFun in Pulse

Pulse shows your StepFun (阶跃星辰) Step Plan as a ring. On a Token Plan that is your Credits used out of this month's allowance plus any top-up packs, with the date the soonest of them lapse. On the older Coding Plan it is the 5-hour and weekly windows.

## What you need

A Step Plan subscription, signed in to a browser at platform.stepfun.com (or platform.stepfun.ai for the international site). Your Step API key is not used: it buys model calls and cannot see the plan.

## Steps

1. Sign in at https://platform.stepfun.com (or https://platform.stepfun.ai) in your browser, and open the Step Plan usage page once to check it shows your plan.
2. In Pulse, go to Settings → StepFun and turn on "Show in panel".
3. Under "Site", pick the site you signed in to. Switching it later clears the saved session, so you read the new site's.
4. Under "Read from browser", pick the browser you signed in with (or leave it on Automatic) and click "Read".
   - Chrome, Edge, Brave, Arc, Vivaldi, and ego lite: macOS asks once for keychain permission.
   - Safari: give Pulse Full Disk Access first, in System Settings → Privacy & Security.
   - Firefox: nothing extra.
5. Success looks like a StepFun ring on the Pulse panel. Its card shows "Credit allowance" (Token Plan) or the 5-hour and weekly limits (Coding Plan).

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Sign in to StepFun's platform in a browser to see usage. | Sign in at the site chosen under "Site", then click "Read" again. |
| No StepFun session found. Sign in at platform.stepfun.com first. | The browser has no session for that site. Check "Site" matches where you signed in, and the browser picked under "Read from browser". |
| StepFun's saved session expired. Sign in again in your browser. | Sign in again, then click "Read" again. |
| No Step Plan on this StepFun account. | StepFun reports no plan for this account — nothing to draw a ring for. |

## What Pulse reads

Pulse reads only StepFun's session cookies (`Oasis-Token` and the two that travel with it) for the chosen site, and sends them only to that site, asking the same two questions the console's usage page asks. It never sends one site's session to the other.
