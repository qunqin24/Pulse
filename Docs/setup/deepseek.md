# Set up DeepSeek in Pulse

Pulse shows your prepaid DeepSeek balance — how much money is left on your account. DeepSeek doesn't report a plan, an allowance, or a reset date, so unlike other providers there's a choice to make about what (if anything) the ring measures.

## What you need

A DeepSeek API Platform account with credit topped up. DeepSeek isn't a subscription plan here — it's pay-as-you-go balance.

## Steps

1. Open [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys), sign in, add a payment method and top up your balance if you haven't, then click **Create new API key** and copy it.
2. In Pulse: **Settings → Accounts → DeepSeek**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Your balance shows right away. Whether Pulse also draws a ring — and what it means — depends on the **Ring measures** choice described next.

## Choosing what the ring means

DeepSeek's own reply says only how much money is left; it never states an allowance to divide by. Pulse won't invent a percentage, so you choose the denominator yourself in **Settings → Accounts → DeepSeek → Connection → Ring measures**:

- **Since top-up** (default) — Pulse remembers the highest balance it has ever seen on this account and shows how much of that is gone. Nothing to type, but on a Mac that has never watched this account before, the very first reading becomes the mark, so the ring can start empty until you've actually spent something since then.
- **Balance only** — no ring at all; the panel just shows the money left.
- **My budget** — a **Full tank** field appears where you type your own figure (what you consider a full balance), and the ring shows how much of that figure is gone.

You can also set **Settings → Accounts → DeepSeek → Notifications → Warn below** to a money figure to get a one-time notification when your balance drops under it. Leave it blank for no notification.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from platform.deepseek.com/api_keys. |
| That key was refused. Check it in Settings. | The key isn't valid — create a fresh one and paste it again. |
| Checking too often — easing off. / The service returned an error. | A temporary problem on DeepSeek's side. Wait a moment and try again. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to DeepSeek's own balance endpoint. Pulse never shows a made-up percentage — it only ever measures against a number it actually watched (Since top-up) or one you typed yourself (My budget); with neither, it shows the balance alone.
