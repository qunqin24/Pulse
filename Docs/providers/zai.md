# Z.ai and GLM Coding Plan

One service, two providers: [`ZaiUsageService.swift`](../../Sources/Pulse/ZaiUsageService.swift).

| Provider | Ring name | Host | Icon |
|---|---|---|---|
| `.zai` | Z.ai | `https://api.z.ai` | `zai` |
| `.glmCoding` | GLM Coding Plan | `https://open.bigmodel.cn` | `zhipu` |

They are one company’s international and mainland storefronts, answering the same JSON on different hosts — **separate accounts with separate keys**. A key for one is refused by the other. CodexBar models this as one provider with a region switch; Pulse gives each a ring so someone with only the mainland plan does not have to know an international one exists.

Extra accounts are not supported. `keepsLocalTranscripts` is false.

## Route

`GET {host}/api/monitor/usage/quota/limit` with the key as a bearer token. Undocumented; can change without notice. Parsing follows CodexBar’s written account of the reply.

**The reply wraps its payload in a status of its own** — `success` and `code`, both of which must say 200 *even when HTTP did*. A refused key arrives as HTTP 200 with `success: false`. Reading only the status line would report an empty plan rather than a bad key.

An envelope refusal is not automatically a bad key: a 500 or a rate limit arrives the same way, and saying “check your key” sends the user after a credential that is fine.

Numbers are decoded as `Double` rather than `Int` on purpose: a service that starts sending `12.5` where it sent `12` would otherwise fail the whole reply and blank the ring over a usable figure.

## Percentage vs counts

A whole-number `percentage` is the **fallback**, not the answer. Where the reply also gives counts, spend is worked out from them: `remaining` is what is left so spend is the difference; `currentValue` is spend directly and wins when both are present.

**Historical evidence:** a limit stating `percentage: 7` with `usage: 1000, remaining: 247` is 75% gone, and the stated figure is simply wrong.

A limit with no figure at all is dropped, not drawn at 0%.

## Window length

A `unit` code times a `number` (1 = day, 3 = hour, 5 = minute, 6 = week). An unrecognised unit means the length cannot be read, and that window is **dropped rather than guessed at**.

Exception: the MCP lane reports its monthly allowance as “1 minute” — a marker, not a duration. Taken literally it sorts above a five-hour limit and claims to reset every minute.

`nextResetTime` is epoch **milliseconds**.

## Keys on disk (mainland only)

GLM also reads a key already on this Mac, first readable line only:

- `~/.coding-relay/glm-api-key`
- `~/.config/bigmodel/api_key`
- `~/.config/zhipu/api_key`

That is both a fallback and the first-run evidence that this Mac is set up for it.

**Never consulted for the international route.** Quietly sending a BigModel key to `api.z.ai` reports a refused key for a plan the user does not have.

## Reading a key file

Needs `whitespacesAndNewlines` and a real newline split. `split(separator: "\n")` does not cut a CRLF file at all — Swift counts `\r\n` as one Character — and `CharacterSet.whitespaces` contains neither CR nor LF. `URLRequest.setValue` then **silently discards** a header value containing a newline, so the request went out with no `Authorization`, came back 401, and was reported as a refused key: about a key that was correct, in a Settings field that was empty because it came from a file.
