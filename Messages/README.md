# Messages after an update

What Pulse shows in its "A note from the developer" window after an update. Not the release notes — those are in [CHANGELOG.md](../CHANGELOG.md) and Sparkle's update window — but whatever the maintainer wants to say to people who just updated.

- One folder per version, named exactly as `VERSION`: `Messages/1.12.5/`.
- One file per language: `en.md`, `zh-Hans.md`, `zh-Hant.md`, `ja.md`, `ko.md`, `ru.md`. A reader whose language has no file gets `en.md`; with no `en.md` either, nothing is shown.
- Paragraphs are separated by a blank line. `**bold**`, `*italics*`, `` `code` `` and `[links](https://example.com)` work; anything else is shown as typed.
- Pulse reads these from `main` on GitHub at launch, so a message can be added or corrected after the release and is picked up on the next launch.
- It is shown on every launch after the update until the reader picks "Don't show again". A version with no folder shows nothing.

The text is user-visible and held to the same standard as everything else a user reads: [Docs/development.md](../Docs/development.md#writing-users-can-read). How it works: [Docs/update-message.md](../Docs/update-message.md).
