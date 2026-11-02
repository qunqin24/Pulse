# Networking

Owns the proxy boundary for traffic Pulse starts. Per-provider routes and authentication still belong in [providers/README.md](providers/README.md); updates belong in [releasing.md](releasing.md).

## Setting

Settings → Network and refresh offers four modes (`NetworkProxyMode`), and the line under the picker says what the chosen one does:

- **No Proxy** (`direct`) connects directly, whatever macOS or a shell says. `URLSession` gets an empty `connectionProxyDictionary` — empty means no proxy, where nil means the system's — and helper processes get Pulse's environment with every proxy variable removed. A saved custom endpoint is kept for when the custom proxy is chosen again.
- **Follow System** (`system`) is the default and preserves the behaviour from before this setting existed. `URLSession` uses macOS's proxy configuration — so with no proxy switched on in macOS it connects directly — and helper processes inherit Pulse's environment unchanged.
- **System Proxy Only** (`systemRequired`; 「使用代理」) is Follow System that **never connects directly**. While macOS has none of its HTTP, HTTPS or SOCKS proxies or automatic configuration switched on (`SystemProxy.isOn`, read from `CFNetworkCopySystemProxySettings` at each request), every request Pulse would send is refused before it leaves — for someone whose accounts must not see this Mac's own address when the proxy app has been quit. It cannot be the default: everyone who uses no proxy would be cut off. See [Holding back](#holding-back).
- **Custom Proxy** (`manual`) accepts an HTTP CONNECT or SOCKS5 proxy without authentication. Host and port are one commit: Return or leaving either field attempts to save both, and an empty host or a port outside 1–65535 does not replace any saved endpoint. There is deliberately no per-provider override.

The stored tokens are `direct`, `system`, `systemRequired` and `manual`; an older build that reads `direct` or `systemRequired` cannot decode it and falls back to Follow System.

`AppSettings.networkProxy` is one Codable value in `UserDefaults`. A mode or type selection is saved immediately; text remains local to `NetworkPane` until the complete endpoint passes validation. Every saved change goes through `AppSettings.onChange`, so all enabled accounts are asked again rather than waiting for the next timer tick.

## URLSession boundary

`NetworkSession` owns the default session and applies the setting to every external session Pulse creates. No Proxy sets `connectionProxyDictionary` to `[:]`. Custom HTTP uses `ProxyConfiguration(httpCONNECTProxy:)`; SOCKS5 uses `ProxyConfiguration(socksv5Proxy:)`. Replacing the setting cancels the previous shared session so requests queued by the settings change cannot continue to reuse its connections.

The boundary includes:

- provider usage requests, including the isolated ephemeral sessions used for borrowed browser cookies;
- OAuth, device-code and browser-login token exchanges;
- the models.dev price download;
- the status-page reads on every provider pane that has one (44 providers), and the outage notification's ([providers/README.md](providers/README.md#service-status));
- the day's exchange rate from ExchangeRate-API's open access endpoint, only while estimates are shown in a currency other than the dollar ([refresh-and-data.md](refresh-and-data.md#currency));
- the maintainer's note after an update, once per launch while one is due ([update-message.md](update-message.md)).

Cookie storage, cache and redirect policies still belong to each caller. Applying a proxy must not turn a borrowed browser session into a process-wide cookie jar or allow its hand-written `Cookie` header across a redirect.

Antigravity is the exception: its session reaches the editor's language server at `https://127.0.0.1:<port>` and stays outside `NetworkSession`. Loopback traffic is never sent to the custom proxy. Its `agy` CLI route is a helper process (see below).

## Holding back

`ProxyGuard`, a `URLProtocol`, is the first protocol class of every session `NetworkSession.configured` makes — under every mode, because it reads the setting at each request and a session a caller kept from before a change is held to the new one. It answers only the requests `NetworkSession.refuses` names (System Proxy Only, nothing switched on in macOS, a host that is not this Mac's loopback) and fails them with `URLError(.notConnectedToInternet)`; every other request goes to URLSession untouched. A PAC file that sends a host `DIRECT` is the proxy app's own rule and is followed.

A service reports that failure as unreachable, so while the guard is refusing, `UsageStore` renames an `.unreachable` reading `.systemProxyOff` ("No proxy is switched on in macOS, so Pulse didn't connect."). The ring keeps its last reading, marked stale, by the ordinary cache rule. The alert rules class `.systemProxyOff` as neutral: quitting a proxy app would otherwise announce an outage on every account at once. The Network pane's line under the picker says "macOS has no proxy switched on, so Pulse isn't connecting.", read again every 3 seconds while the pane is open, because the switch changes in another app.

**Not held back:** helper processes and extensions (they inherit what Follow System gives them — a choice, not a gap; switching them over would mean writing macOS's proxy into their environment), sign-in pages drawn in a web view, and Sparkle. **A VPN or a proxy app's TUN mode is not a system proxy**: it switches nothing on in these settings, so under System Proxy Only nothing is sent. Choose Follow System or No Proxy with one.

## Helper processes

A custom HTTP proxy starts `codex app-server`, `arkcli` and Antigravity's `agy` with `HTTP_PROXY` and `HTTPS_PROXY`; SOCKS5 uses `ALL_PROXY`. Each also receives `NO_PROXY=localhost,127.0.0.1,::1`. Conflicting inherited upper- and lower-case proxy variables are removed first. Whether a helper supports SOCKS5 is the helper's decision.

Selecting Follow System or System Proxy Only sets no child environment. This is intentional: a helper launched from Finder or a login item inherits no shell proxy, while one launched from a terminal may. Follow System means preserving that existing behaviour, not manufacturing environment variables from macOS network settings. No Proxy is the opposite: it removes the upper- and lower-case `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY` a helper would otherwise inherit, so a proxy exported in the shell that launched Pulse does not reach it either.

Every helper CLI Pulse starts — `codex app-server`, Kiro's ACP client, `arkcli`, Alibaba's `bl`, Antigravity's `agy` — gets the folder it was found in at the front of `PATH` (`BoundedProcess.environment(leading:over:)`), because an npm-installed CLI is a Node script and a GUI app's `PATH` has no `node` ([providers/codex.md](providers/codex.md#app-server--sigpipe--path)).

Extensions do **not** inherit Pulse's environment under either setting: they get a short list of basics plus whatever proxy variables are in effect, so a custom proxy reaches them, No Proxy leaves them none, and a token exported for another tool does not. [extensions.md](extensions.md)

`UsageStore.settingsChanged` shuts down an existing Codex app server before it queues the new full pass. The next request starts a child with the new environment. `arkcli` and `agy` are already one process per request.

## Updates

Sparkle owns its network session and exposes no public session-configuration or proxy hook. Update checks therefore always follow macOS system proxy settings, regardless of Pulse's Network setting — No Proxy included. Do not imply otherwise in the READMEs or settings copy.
