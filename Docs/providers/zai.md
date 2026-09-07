# Z.ai and GLM Coding Plan

One service, two providers: [`ZaiUsageService.swift`](../../Sources/Pulse/ZaiUsageService.swift).

| Provider | Ring name | Host | Icon |
|---|---|---|---|
| `.zai` | z.ai | `https://api.z.ai` | `zai` |
| `.glmCoding` | 智谱 | `https://open.bigmodel.cn` | `zhipu` |

They are one company’s international and mainland storefronts, answering the same JSON on different hosts — **separate accounts with separate keys**. A key for one is refused by the other. CodexBar models this as one provider with a region switch; Pulse gives each a ring so someone with only the mainland plan does not have to know an international one exists.

**The rings are named for the two shops, not for the product** — that is issue #13. They were `Z.ai` and `GLM Coding Plan`; but **z.ai sells its plan under the name "GLM Coding Plan" too**, so an international subscriber picked the row literally called that, pasted a z.ai key, and had it sent to BigModel. The company is the one thing that differs and the one thing a buyer knows, so it is the whole name — and neither row keeps the ambiguous one.

## Refusals arrive as HTTP 200

The verdict is in the envelope, so the status line says nothing and `problem(_:)` is the whole of what the user is told. Measured against both live hosts on 2026-09-07:

| Sent | Envelope |
|---|---|
| A key of the wrong shape | `401` · `令牌已过期或验证不正确` |
| A well-formed key the host does not know | `1000` · `身份验证失败。` |
| No `Authorization` header | `1001` · `Header中未收到Authorization参数…` |
| Any of the above, on `api.z.ai` | the same codes, in English |
| A **working** key with no Coding Plan running on the account | `500` · `当前用户不存在coding plan` |

That last row was measured with a real Coding Plan key whose subscription had lapsed — one that still answers a `glm-4-flash` completion perfectly well — on all three hosts. **The plan is a subscription on the account, not a property of the key**: authentication succeeds and the quota endpoint still has nothing to report. So a refused key and an unsubscribed account are different problems with different remedies, and only the sentence tells them apart. It is checked before the code test, since `500` is this vendor's generic number and on its own would say the service broke — which sends somebody to look for an outage instead of at their subscription. The phrase is embedded in English on both hosts, so one test covers both wordings.

The success path is measured too, as of 2026-09-07: a freshly bought Lite plan on `open.bigmodel.cn` answers

```
limits[0]  CREDIT_LIMIT  unit 3, number 5   usage 2000   remaining 2000   (no reset)
limits[1]  CREDIT_LIMIT  unit 6, number 1   usage 10000  remaining 10000  nextResetTime 1789373585999
level      "lite"
```

`unit` 3 is hours and 6 is weeks, so those are a real five-hour and a real seven-day window — stated lengths, which the window clock and the forecast may divide by. `nextResetTime` is epoch **milliseconds** and only the weekly one carries it. The tier arrives under `level`, the fifth of the five keys `planLabel` accepts. `usage` equalling `remaining` is a spend of zero, which is a *reading* — distinct from a missing figure, which stays nil rather than drawing a full green ring. Committed as `Tests/PulseTests/Fixtures/glm-coding-plan-quota.json`; it carries no secret. The keyword list was **English only** while the mainland host answers in Chinese, so nothing matched and everything fell through to a code test that knew only HTTP's numbers. `1000` — the shape a key from the *other region* produces, which is the common mistake — came out as "the service returned an error" and sent people looking for an outage. Chinese wording is matched now, and Zhipu's 1000-series is treated as authentication. The words matter more than the numbers: the numbering is this vendor's own and is not published in full.

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
