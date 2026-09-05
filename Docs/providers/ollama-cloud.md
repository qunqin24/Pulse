# Ollama Cloud (index)

Authoritative setup, cookie filter, page parser, storage, and security notes:

**[`../ollama-cloud.md`](../ollama-cloud.md)**

Do not duplicate that document here. This page only places Ollama in the provider matrix.

## Place in Pulse

- `Provider.ollamaCloud`. Icon `ollama`. Extra accounts: no. Transcripts: no. First-run: none (`canReportWithoutSetup` is false until a session is stored).
- `usesAPIKey` is true so Settings has a credential row; `usesSessionCookie` is true so that row is a **browser session**, not an API-key paste. Ollama publishes no quota API. The [usage API](https://docs.ollama.com/api/usage) is token/duration metrics from model responses, not account windows.
- Session is stored in `keys.dat` like other secrets Pulse keeps. Missing/expired/changed page are three unavailability cases (`.ollamaSessionMissing`, `.ollamaSessionExpired`, `.ollamaPageChanged`).
- Browser cookie reading: [`BrowserCookies.swift`](../../Sources/Pulse/BrowserCookies.swift) and [authentication.md](authentication.md). Only this provider uses that path.
- Service: [`OllamaCloudUsageService.swift`](../../Sources/Pulse/OllamaCloudUsageService.swift).
