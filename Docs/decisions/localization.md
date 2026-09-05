# Localization lookups are explicit

**Status:** still in force. **Evidence:** shipped English fallbacks; scanner design.

Implicit SwiftUI `Text("…")` resolves against `Bundle.main`. For a SwiftPM executable that is the bare binary, not the resource bundle. The key is shown verbatim — the app stays in English and nothing warns you.

Interpolating `Int` produces `%lld`; a strings file written with `%@` never matches. Shipped once in the refresh-interval labels.

A `%` next to a placeholder is a malformed printf conversion (`"%@ · %@% of tokens"`).

`check-localization.sh` used to compare only the two `.strings` files. A find-and-replace renaming `provider` to `account.provider` swept through a **string literal**; the estimate caption reverted to English while both files still agreed. The Python scanner reads literals (interpolations nest and can contain string literals), skips comments, and reduces interpolations to the `%@` that `String.LocalizationValue` produces.

**Do not put a conditional inside `Text(localized:)`.** The scanner wants a string literal immediately after `localized:` and reads `flag ? "\(x) Left" : "\(x) Used"` as the bare tail `"Left"`, which happened to match an unrelated key. The check reported order while the card fell back to English.

`Kind` and `Unavailability` as stored strings froze the language current at fetch time — the same trap as old sample data.

Current rules: [../development.md](../development.md).
