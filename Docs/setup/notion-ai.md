# Set up Notion AI in Pulse

Pulse shows your Notion AI usage allowance, as Notion reports it on **Settings → Notion AI → Usage**: the rolling window (six hours when this was written) and the billing period, each as credits used out of the limit.

## What you need

A Notion account in a **Business** or **Enterprise** workspace, signed in to a browser at [app.notion.com](https://app.notion.com). Free, Plus and personal workspaces have no usage allowance to show.

If you belong to several workspaces, Pulse reads the first one on a Business or Enterprise plan.

## Steps

1. Sign in to Notion in your browser.
2. In Pulse: **Settings → Notion AI**. Turn on **Show in panel**.
3. Under **Read from browser**, pick the browser you signed in with (or leave it on Default browser) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite: macOS asks once for keychain permission.
   - Safari: give Pulse Full Disk Access first, in System Settings → Privacy & Security.
   - Firefox: nothing extra.
4. Within a few seconds the ring appears, and the account's pane lists both windows and when each resets.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Click **Read** under **Read from browser**. |
| No session found. Sign in at notion.com first. | The browser picked has no Notion session. Sign in, or pick the browser you use Notion in. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in to Notion again, then click **Read** again. |
| This account has no plan with usage limits. | The workspace isn't on a Business or Enterprise plan, or you have no workspace. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Notion sent something Pulse doesn't recognize. These are Notion's internal endpoints and may change. |

## What Pulse reads

Pulse keeps only Notion's `token_v2` session cookie from your browser, stores it encrypted on this Mac, and sends it only to `app.notion.com`, asking the same two things Notion's own usage page asks: which workspaces you can see, and that workspace's allowance. Custom Agents and Workers are billed in Notion credits, which this allowance doesn't cover and Pulse doesn't read.
