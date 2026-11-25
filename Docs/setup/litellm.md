# Set up LiteLLM in Pulse

[LiteLLM](https://docs.litellm.ai) is a proxy someone (maybe you) runs on their own server. Pulse shows the budgets your virtual key is held to: the team's budget, if the key belongs to a team, and your own user budget. Each is a ring of spend against the limit LiteLLM reports.

## What you need

The proxy's address and a virtual key on it. The key has to belong to a user or a team with a budget (`max_budget`) set; spend with no budget has no ring.

## Steps

1. Get the address and key your AI client already uses for this proxy. If you run it yourself, create a virtual key for a user or team in the LiteLLM admin UI.
2. In Pulse: **Settings → LiteLLM**. Turn on **Show in panel**. Fill in **Server address** (for example `https://litellm.example.com` — a trailing `/v1` is fine) and click **Save**. Then paste the key into **API key** and click **Save**.
3. Within a few seconds a ring appears. The card lists "Team credits" for the team's budget and the user budget as "Spend limit", or as a daily or weekly limit when the budget has that duration.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add the server address in Settings. | Fill in **Server address** with the proxy's address. |
| The address needs https://, unless the server is on your own network. | Use an `https://` address, or `http://` only for a proxy on this Mac or your local network. |
| Add an API key in Settings. | Paste the virtual key. |
| That key was refused. Check it in Settings. | The key is wrong, expired or for another proxy. Paste the one your client uses. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| No limits reported. | The key's user or team has no budget set, or this proxy doesn't let a key read its own information. |
| Couldn't read the reply. | The proxy answered in a shape Pulse doesn't recognize, or answered about a different user or team. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to the address you entered, to LiteLLM's `/key/info`, `/user/info` and `/team/info` routes. No model request is made.
