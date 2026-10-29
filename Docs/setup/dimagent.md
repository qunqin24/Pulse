# DimAgent

1. Install the Dim CLI and sign in with `dim auth login`.
2. Run `dim usage --json` once to confirm your subscription is readable. Pulse was checked against dimcode 0.5.21.
3. Open Pulse Settings, choose **DimAgent** under subscriptions, and enable **Show in panel**.

Pulse uses the CLI's saved login. No API key or cookie needs to be pasted into Pulse. The CLI must remain installed and available; mise users should keep the Node and Dim shims available to GUI applications as well as terminals.

The card shows plan credits, reported token windows and the web-search allowance separately. A full token window can pause consumption even when plan credits remain; its reported reset time tells you when that window ends. Enable the detailed card's amounts to see used or remaining units alongside the percentage. Pin the plan-credit limit if you want that allowance to drive the ring regardless of token-window or search usage.

Credit expiry is shown as expiry, not automatic renewal. Add-on packs appear separately when reported. Credits are not a cash balance and local token logs are not used to estimate the subscription.

If the CLI is missing, install it through your existing tool manager. If the login expires, run `dim auth login`, confirm `dim usage --json` works, then refresh Pulse. A connection failure retains the usual stale-reading behaviour.
