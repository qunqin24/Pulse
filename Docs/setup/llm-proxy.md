# Set up LLM API Key Proxy in Pulse

[LLM API Key Proxy](https://github.com/Mirrowel/LLM-API-Key-Proxy) is a gateway someone (maybe you) runs in front of several upstream accounts. Pulse shows the quota groups it reports for them — how much of each is left and when it resets.

## What you need

The proxy's address and the key it was started with (`PROXY_API_KEY`) — the same key your AI client uses with it.

## Steps

1. Get the proxy's address and key from whoever runs it. The address can be the proxy's root or its `/v1` base.
2. In Pulse: **Settings → LLM API Key Proxy**. Turn on **Show in panel**. Fill in **Server address** (for example `http://localhost:8000` for one on this Mac) and click **Save**. Then paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists one row per quota group, labelled with the upstream and group name.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add the server address in Settings. | Fill in "Server address" with your proxy's address. |
| The address needs https://, unless the server is on your own network. | Use an `https://` address, or `http://` only for a server on your own machine or local network. |
| Add an API key in Settings. | Paste the proxy's key into "API key". |
| That key was refused. Check it in Settings. | The key doesn't match the one the proxy was started with. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | The proxy sent something Pulse doesn't recognize, or none of its upstreams report a quota group. |

## What Pulse reads

Pulse sends the key as a bearer token to `{your address}/v1/quota-stats` and nowhere else. No model request is made. The address and key are kept encrypted on this Mac.
