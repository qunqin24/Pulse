# Networking

Owns the proxy boundary for traffic Pulse starts. Per-provider routes and authentication still belong in [providers/README.md](providers/README.md); updates belong in [releasing.md](releasing.md).

## Setting

Settings → Network and refresh offers two modes:

- **Follow System** is the default and preserves the behaviour from before this setting existed. `URLSession` uses macOS's proxy configuration, and helper processes inherit Pulse's environment unchanged.
- **Manual** accepts an HTTP CONNECT or SOCKS5 proxy without authentication. Host and port are one commit: Return or leaving either field attempts to save both, and an empty host or a port outside 1–65535 does not replace any saved endpoint. There is deliberately no direct/no-proxy mode and no per-provider override.

`AppSettings.networkProxy` is one Codable value in `UserDefaults`. A mode or type selection is saved immediately; text remains local to `SettingsView` until the complete endpoint passes validation. Every saved proxy change goes through `AppSettings.onChange(.networkProxy)`, so all enabled accounts are asked again rather than waiting for the next timer tick.

## URLSession boundary

`NetworkSession` owns the default session and applies `URLSessionConfiguration.proxyConfigurations` to every external session Pulse creates. Manual HTTP uses `ProxyConfiguration(httpCONNECTProxy:)`; SOCKS5 uses `ProxyConfiguration(socksv5Proxy:)`. Replacing the setting cancels the previous shared session so requests queued by the settings change cannot continue to reuse its connections.

The boundary includes:

- provider usage requests, including the isolated ephemeral sessions used for borrowed browser cookies;
- OAuth, device-code and browser-login token exchanges;
- the models.dev price download.

Cookie storage, cache and redirect policies still belong to each caller. Applying a proxy must not turn a borrowed browser session into a process-wide cookie jar or allow its hand-written `Cookie` header across a redirect.

Antigravity is the exception: its session reaches the editor's language server at `https://127.0.0.1:<port>` and stays outside `NetworkSession`. Loopback traffic is never sent to the manual proxy.

## Helper processes

A manual HTTP proxy starts `codex app-server` and `arkcli` with `HTTP_PROXY` and `HTTPS_PROXY`; SOCKS5 uses `ALL_PROXY`. Both also receive `NO_PROXY=localhost,127.0.0.1,::1`. Conflicting inherited upper- and lower-case proxy variables are removed first. Whether a helper supports SOCKS5 is the helper's decision.

Selecting Follow System sets no child environment. This is intentional: a helper launched from Finder or a login item inherits no shell proxy, while one launched from a terminal may. Follow System means preserving that existing behaviour, not manufacturing environment variables from macOS network settings.

`UsageStore.settingsChanged` shuts down an existing Codex app server before it queues the new full pass. The next request starts a child with the new environment. `arkcli` is already one process per request.

## Updates

Sparkle owns its network session and exposes no public session-configuration or proxy hook. Update checks therefore always follow macOS system proxy settings, regardless of Pulse's Network setting. Do not imply otherwise in the READMEs or settings copy.
