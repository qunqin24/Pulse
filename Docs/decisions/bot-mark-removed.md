# The animated mark was replaced

**Status:** in force since 2026-11-02, on the maintainer's instruction. **Replaced** the same day by CX ArtLab's robot (below).

Pulse 1.2.0 to 1.12.4 could draw an animated bot in a ring in place of the provider's logo ("Animated mark", off by default, per account). It was removed, with its settings, translations, tests and data.

## Rules for a robot in the ring

- **Only artwork Pulse may use.** A character and its code come from their author under a licence that covers them, are credited wherever they are offered, and are not presented as Pulse's own.
- **Written from the source it credits.** Not from the removed `Sources/Pulse/Panel/BotMark/` or its history. The behaviour is specified from what Pulse knows — idle, an agent working, a fetch, a limit spent, no reading, a reset, a finished turn — not from the old state list.
- **Kept for it:** `ResetWatch` and `AgentActivityMonitor.finishedAt` (`UsageStore.justReset`, `justFinishedWorking`), Pulse's own witnesses for a reset and a finished turn.

Stored preferences from the old feature (`settings.botMarks`, `botPersonas`, `botColours`, `botShapes`) are left in place and read by nothing; a replacement uses new keys rather than inheriting them.

## The replacement

**[Agent Robot Avatar](https://github.com/CX-ArtLab/agent-robot-avatar) by CX ArtLab**, MIT-licensed, ported to Swift in `Sources/Pulse/Panel/Robot` ([../ui/rings-and-surface.md](../ui/rings-and-surface.md#robot)).

- **Why this one meets the rules above.** Checked before it was used: the character is the author's original design and the code is theirs under MIT. Its README says so in "Character design and visual identity", which also limits what the licence grants: Pulse may use and modify the avatar, and may not present the character as its own or as a brand. So it is credited wherever it is offered — the switch's subtitle, Settings › About › Credits, `THIRD_PARTY_NOTICES.md` with the licence text — and nothing calls it Pulse's.
- **Written from the source it credits.** The port was made from the CX ArtLab repository alone (v0.7.1, commit `7e637d1`); the removed implementation and its history were not consulted.
- **Specified from Pulse's facts, in the original's vocabulary.** Idle, working, refreshing, spent and no reading each pick one of the avatar's own actions; the two witnesses kept above drive its `success` and `affirm`. Nothing near a limit gets a face: the ring's colour says it.
- **Colour, personality and shape** came back as options on 2026-11-02, at the maintainer's request, designed afresh from what the original offers: its `color` attribute, its idle actions (`bored`, `inspect`, `surprise`) and its `setHeadRoundness`. Nothing is invented beyond them. Automatic colour is each product's own brand colour, from a table Pulse compiled for this (`Provider.brandColour`), with Pulse's own wheel for black-and-white marks.
- **New keys:** `settings.robotAccounts`, `robotColours`, `robotPersonalities`, `robotShapes`.
