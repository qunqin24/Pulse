# Set up Bifrost in Pulse

[Bifrost](https://github.com/maximhq/bifrost) is an AI gateway someone (maybe you) runs. Pulse shows the budgets its governance puts on your virtual key — dollars spent out of dollars allowed, per period — including budgets set per upstream provider or per model.

## What you need

The gateway's address and a **virtual key** on it that has at least one budget. Whoever runs the gateway creates virtual keys and budgets in its dashboard (Governance → Virtual Keys).

## Steps

1. Get the virtual key (it usually starts with `sk-bf-`) and the gateway's address from whoever runs it — the same address your AI client uses, with or without `/v1` on the end.
2. In Pulse: **Settings → Bifrost**. Turn on **Show in panel**. Fill in **Server address** (for example `https://bifrost.example.com`, or `http://localhost:8080` for one on this Mac) and click **Save**. Then paste the virtual key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists each budget. A budget set on a model or upstream provider is labelled with its name.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add the server address in Settings. | Fill in "Server address" with your gateway's address. |
| The address needs https://, unless the server is on your own network. | Use an `https://` address, or `http://` only for a server on your own machine or local network. |
| Add an API key in Settings. | Paste the virtual key into "API key". |
| That key was refused. Check it in Settings. | The virtual key is wrong, inactive, or for a different gateway. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | The gateway sent something Pulse doesn't recognize, or the key has no budgets. Rate limits alone aren't shown. |

## What Pulse reads

Pulse sends the virtual key, in Bifrost's `x-bf-vk` header, to `{your address}/api/governance/virtual-keys/quota` and nowhere else. No model request is made. The address and key are kept encrypted on this Mac.
