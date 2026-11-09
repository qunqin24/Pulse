# Set up Ollama Cloud in Pulse

Pulse shows the two usage windows on your signed-in Ollama account page: session usage (a 5-hour window) and weekly usage (a 7-day window), each as a percentage.

This is the short version. For the full detail — what exactly gets read, what stays on your Mac, and how each browser is handled — see [../ollama-cloud.md](../ollama-cloud.md).

## What you need

An Ollama account, signed in to a browser (Safari, Firefox, Chrome, Edge, Brave, Arc, Vivaldi, or ego lite). Ollama has no API key for this — the reading comes from your signed-in account page, not a key.

## Steps

1. Sign in at https://ollama.com in your browser.
2. In Pulse, go to Settings → Ollama Cloud and turn on "Show in panel". Under "Read from browser", pick your browser (or leave it on Automatic — it starts with your Mac's default browser) and click "Read".
   - Chrome, Edge, Brave, Arc, Vivaldi, and ego lite keep their cookies in the login keychain, so macOS will ask once for permission.
   - Safari needs Full Disk Access, granted to Pulse in System Settings → Privacy & Security, because its cookie file is otherwise off-limits.
   - Firefox needs nothing extra.
3. Success looks like a ring for Ollama Cloud on the Pulse panel, showing session and weekly usage.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Add an Ollama session in Settings. | Sign in at ollama.com in your browser, then click "Read" again. |
| The Ollama session expired. Sign in again and add it. | Sign in again at ollama.com, then click "Read" again — Pulse can't renew a browser login on its own. |
| Ollama's page has changed and can no longer be read. | Ollama changed something about its settings page. Check for a Pulse update. |

## What Pulse reads

Pulse reads your session cookie out of your browser and keeps it encrypted on this Mac (`keys.dat`), then uses it to load your Ollama settings page and parse the two usage totals off it — there is no Ollama usage API it could call instead. See [../ollama-cloud.md](../ollama-cloud.md) for exactly which cookies are kept and how.
