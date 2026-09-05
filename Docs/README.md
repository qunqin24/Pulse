# Docs

Maintained map. Change the topic file that owns a behaviour in the same patch as the code. [CLAUDE.md](../CLAUDE.md) is a short AI entry; [CONTRIBUTING.md](../CONTRIBUTING.md) is the human process.

`Docs/` is the only docs tree. Investigation notes that are not “how it works now” stay here as historical pages rather than being folded into current architecture.

## Start here

| Doc | Owns |
|---|---|
| [architecture.md](architecture.md) | App shell, settings state, first-run / offer-once, login item, defaults domain |
| [ui/README.md](ui/README.md) | Panel geometry, input, glass/rings, settings window |
| [refresh-and-data.md](refresh-and-data.md) | Refresh loop, cache, activity, ledger, forecast, estimate |
| [development.md](development.md) | Localization, resources, layout budgets, how to add UI |
| [build-from-source.md](build-from-source.md) | Toolchain, `swift build`, `#Preview`, local run |
| [releasing.md](releasing.md) | Tag, bundle, Sparkle, DMG, CI |
| [providers/README.md](providers/README.md) | Per-provider routes, auth, cookies, extra accounts |
| [decisions/README.md](decisions/README.md) | Why / failure lessons (historical) |
| [opencode-triage.md](opencode-triage.md) | GitHub new-issue/PR triage commenter (OpenCode Go; default off) |

## Providers

Current routes and sign-in behaviour live in [providers/README.md](providers/README.md). Do not duplicate them in architecture or UI docs.

Older investigation notes that are still useful as history (not the live contract):

- [ollama-cloud.md](ollama-cloud.md) — how Ollama Cloud usage is read from a signed-in page (no quota API).
- [grok-bot-usage.md](grok-bot-usage.md) — historical Grok Bot / Cursor “Sand” investigation.

When those notes disagree with `providers/README.md` or the code, the code and the providers README win.

## Also in this folder

- [plan.md](plan.md) — working notes, not a contract.
- Screenshots and `demo.gif` used by the READMEs.

## User-facing

- [../README.md](../README.md) / [../README.zh-CN.md](../README.zh-CN.md) — product pages. Keep bilingual parity. They are not the architecture source of truth.
