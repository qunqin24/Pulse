# Set up sub2api in Pulse

[sub2api](https://github.com/Wei-Shaw/sub2api) is a gateway someone (maybe you) runs on their own server, sharing a Claude/Codex/Gemini/Grok subscription out as an OpenAI-style API. Pulse reads the usage a group key can see. Depending on how your group is set up, Pulse shows either a money balance, or a percentage-based quota, subscription, or rate-limit window.

## What you need

Access to a running sub2api deployment (its web address) and an API key for a group on it. If nobody has set one up for you, you — or whoever administers it — creates a group and a key in the deployment's admin dashboard.

## Steps

1. Get your key: sign in to your sub2api deployment's web console (the address your operator gave you) and open your API keys page — usually reachable from a "Use Key" or "API Keys" button on your dashboard. Copy the key for the group you were assigned. If you administer the deployment yourself, create a group under the Admin Dashboard first, then generate a key for it.
   <!-- unverified: exact on-screen button/page label for the end-user API key page. sub2api's own README calls it "the user API-key page" and mentions a "Use Key" button, but no screenshot or live deployment was checked, and the label is admin-configurable per deployment. -->
2. In Pulse, go to Settings → sub2api and turn on "Show in panel". Fill in "Server address" with your deployment's address (for example `https://gateway.example.com`) and click Save — if you don't type a scheme, Pulse assumes `https://`; plain `http://` is only accepted for an address on your own network, such as `localhost` or a `192.168.x.x` address. Then paste your group key into "API key" and click Save.
3. Success looks like a ring (or a balance, if your group is a prepaid wallet) for sub2api on the Pulse panel.
4. To add another deployment or another group's key, click "Add" next to "Add another account" in the sub2api pane's Accounts group. A new account opens with its own "Server address" and "API key" fields; fill them in as in step 2, and type a name for it under "Name" so you can tell the rings apart. "Remove account" on that pane deletes its address and key.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Add the server address in Settings. | Fill in "Server address" with your deployment's URL. |
| That address can't be used. It needs https://, unless the server is on your own network. | Use an `https://` address, or an `http://` address only if the server is on your own machine or local network. |
| Add an API key in Settings. | Paste the group key into "API key". |
| That key was refused. Check it in Settings. | The key is wrong, revoked, or for a different deployment. Get a fresh one from the console and paste it in again. |

## What Pulse reads

Pulse sends your group key as a bearer token to `{your address}/v1/usage` on the deployment you typed, and reads back whatever balance or quota figures that reply carries. Nothing is sent anywhere else, and no model request is ever made through it. The key is kept encrypted on this Mac (`keys.dat`); the address is kept in Pulse's settings. Each added account has its own of both.
