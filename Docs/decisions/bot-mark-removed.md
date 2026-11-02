# The animated mark was replaced

**Status:** in force since 2026-11-02, on the maintainer's instruction.

Pulse 1.2.0 to 1.12.4 could draw an animated bot in a ring in place of the provider's logo ("Animated mark", off by default, per account). It was removed, with its settings, translations, tests and data.

## Rules for a robot in the ring

- **Only artwork Pulse may use.** A character and its code come from their author under a licence that covers them, are credited wherever they are offered, and are not presented as Pulse's own.
- **Written from the source it credits.** Not from the removed `Sources/Pulse/Panel/BotMark/` or its history. The behaviour is specified from what Pulse knows — idle, an agent working, a fetch, a limit spent, no reading, a reset, a finished turn — not from the old state list.
- **Kept for it:** `ResetWatch` and `AgentActivityMonitor.finishedAt` (`UsageStore.justReset`, `justFinishedWorking`), Pulse's own witnesses for a reset and a finished turn.

Stored preferences from the old feature (`settings.botMarks`, `botPersonas`, `botColours`, `botShapes`) are left in place and read by nothing; a replacement uses new keys rather than inheriting them.
