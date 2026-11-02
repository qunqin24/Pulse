# Message after an update

After an update Pulse can show a short window, "A note from the developer", with whatever the maintainer wants to say for that version. It is not the release notes: those are the CHANGELOG entry, which Sparkle already shows before the update. Writing one: [../Messages/README.md](../Messages/README.md).

Code: [`UpdateMessage.swift`](../Sources/Pulse/App/UpdateMessage.swift), [`UpdateMessageWindowController.swift`](../Sources/Pulse/Settings/UpdateMessageWindowController.swift).

## When it shows

- **Only after an update, on every launch, until "Don't show again".** `UpdateMessage.noteLaunch` records the version at each launch (`settings.lastLaunchedVersion`); a launch of a different version than the last one marks that version pending (`settings.updateMessagePending`). It is due while pending and not dismissed (`settings.updateMessageDismissed`, one version — the next update's message still shows). Closing the window without dismissing brings it back on the next launch: the maintainer's choice.
- **A fresh install shows nothing.** It is told apart from the first update to carry this feature, which also has no recorded version, by `settings.hasRun`. That key is written when settings are restored, even on a fresh install, so `noteLaunch` runs in `main` before the restore and after `LegacyDefaults.migrateIfNeeded()` (which decides the defaults domain).
- **Bundles only.** A `swift run` build has no version and records nothing.
- **No message, no window.** A version with no file, a reply other than 200, an empty file, or no answer within 15 seconds shows nothing and changes nothing; the version stays pending, so a message added after the release appears on the next launch.

## Where it comes from

`https://raw.githubusercontent.com/qunqin24/Pulse/main/Messages/<version>/<language>.md`, fetched once per launch off the launch path, ignoring the local cache so a corrected message is the one shown. The language is Pulse's own setting, or macOS's choice among the six when it follows the system; a language without a file falls back to `en.md`.

Through `NetworkSession`, so the Network setting applies as to any other request ([networking.md](networking.md)). It sends nothing but the request for the file: GitHub sees the address it comes from and the version in the path, as it already does for Sparkle's appcast.

## The window

A regular titled window, 440 × 360, centred, brought to the front. "Pulse <version>" as the heading, then the paragraphs (split on blank lines; inline Markdown — bold, italics, code, links — rendered, anything else shown as typed; selectable), then **Don't show again** and **Close** (the default button). Its title follows a change of language like the other windows.
