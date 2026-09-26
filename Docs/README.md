# Docs

Maintained map. Change the topic file that owns a behaviour in the same patch as the code. [CLAUDE.md](../CLAUDE.md) is a short AI entry; [CONTRIBUTING.md](../CONTRIBUTING.md) is the human process.

`Docs/` is the only docs tree. Investigation notes that are not “how it works now” stay here as historical pages rather than being folded into current architecture.

## Start here

| Doc | Owns |
|---|---|
| [architecture.md](architecture.md) | App shell, settings state, first-run / offer-once, login item, defaults domain |
| [networking.md](networking.md) | System/manual proxy boundary, URLSession coverage, helper environment, Sparkle exception |
| [ui/README.md](ui/README.md) | Panel geometry, input, rail menu, shortcuts, glass/rings, settings window |
| [refresh-and-data.md](refresh-and-data.md) | Refresh loop, cache, activity, ledger, forecast, estimate, chart hover |
| [token-spend.md](token-spend.md) | Token spend pane: agents read, model drill-down, pricing, what may be said about the figures |
| [token-spend-sources.md](token-spend-sources.md) | The complete agent/source catalog: default macOS location, format, counters reported, evidence level |
| [notifications.md](notifications.md) | When Pulse posts a notification, and what it refuses to say |
| [development.md](development.md) | Localization, resources, layout budgets, how to add UI |
| [testing.md](testing.md) | What `swift test` covers, fixtures, why the gaps are gaps |
| [json-output.md](json-output.md) | The `--json` contract for status lines and scripts |
| [integrations.md](integrations.md) | Raycast, tmux, sketchybar, shell prompt setup and account links |
| [extensions.md](extensions.md) | The extension contract: folder, manifest, how a program is run, what it prints |
| [build-from-source.md](build-from-source.md) | Toolchain, `swift build`, `#Preview`, local run |
| [releasing.md](releasing.md) | Tag, bundle, Sparkle, DMG, CI |
| [providers/README.md](providers/README.md) | Per-provider routes, auth, cookies, extra accounts |
| [setup/](setup/) | Per-provider setup pages for users — what the in-app **Setup help** link opens |
| [decisions/README.md](decisions/README.md) | Why / failure lessons (historical) |

## Providers

Current routes and sign-in behaviour live in [providers/README.md](providers/README.md). Do not duplicate them in architecture or UI docs.

Older investigation notes that are still useful as history (not the live contract):

- [ollama-cloud.md](ollama-cloud.md) — how Ollama Cloud usage is read from a signed-in page (no quota API).
- [grok-bot-usage.md](grok-bot-usage.md) — historical Grok Bot / Cursor “Sand” investigation.

When those notes disagree with `providers/README.md` or the code, the code and the providers README win.

## Also in this folder

- [entropy-audit.md](entropy-audit.md) — 2026-09-26 snapshot of structural debt. Historical, not a contract.
- [plan.md](plan.md) — working notes, not a contract.
- Screenshots, `demo.gif` and `bot-mark.gif` used by the READMEs and by [ui/rings-and-surface.md](ui/rings-and-surface.md).

## Release notes

What each release changed, and the source of both the GitHub release page and the Sparkle update text: [../CHANGELOG.md](../CHANGELOG.md). How a release is cut: [releasing.md](releasing.md).

## User-facing

- [setup/](setup/) — one page per provider: where the key or login comes from and where it goes in Pulse. **Setup help** in the app opens these (`ConnectionRemedy.helpURL`), so a new provider needs one, and a changed settings label or failure message means updating its page. English only; no internals.
- [../README.md](../README.md) with [zh-CN](../README.zh-CN.md) / [zh-Hant](../README.zh-Hant.md) / [ja](../README.ja.md) / [ko](../README.ko.md) — product pages. Keep all five in parity. They are not the architecture source of truth.
