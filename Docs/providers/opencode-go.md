# OpenCode Go

Service: [`OpenCodeGoUsageService.swift`](../../Sources/Pulse/OpenCodeGoUsageService.swift).

Extra accounts are not supported. `keepsLocalTranscripts` is false today.

The file header still says this is the only provider Pulse holds a key for. That is **stale**. Several providers paste keys; Copilot’s token lives in the same store. See [README.md](README.md).

## Credential

Two places, in this order:

1. A key pasted into Settings (`keys.dat`). It wins — otherwise a stale key left behind by OpenCode would quietly override a deliberate choice.
2. What OpenCode saved for itself in `~/.local/share/opencode/auth.json`. Anyone already signed in there configures nothing.

A key the service refuses reports `.apiKeyRefused`, **not** `.signInRequired` (that message names Codex). There is no `.openCodeKeyRefused` case.

## Route

`GET https://opencode.ai/zen/go/v1/usage` with `Authorization: Bearer …`.

OpenCode’s own docs cover model endpoints; this usage path is **not documented** there, so it can change without notice. Do not call it an official quota API.

Reply: `usage.{rolling,weekly,monthly}`, each with `status`, `percent` (how much is **gone**), and `resetsAt`. A `status` other than `ok` is treated as spent.

**The window the reply calls `rolling` is the five-hour one** — the reset lands five hours out — so it is shown as “5-hour limit”. Only its *id* keeps the provider’s key, which is what a pinned window is matched on. `Kind.monthly` exists because a billing period had nowhere to map. `windowSeconds` orders the rows; only the reset stamp is displayed.

## Transcripts later

`opencode stats` proves the CLI keeps sessions with token counts and cost, so a spending history is possible later, unlike Antigravity. It lives in OpenCode’s own store rather than the JSONL both other CLIs write, which is why `keepsLocalTranscripts` is false for now.

## First run

A key OpenCode already saved counts as installed. Without this, someone whose only agent is OpenCode Go detects nothing and gets the everything-on fallback. With no key, it stays off until switched on in Settings (`canReportWithoutSetup`).
