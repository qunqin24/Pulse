# Recap cards

Shareable 1080 × 1920 cards for a month or a year of Token spend: a one-page poster and a short deck. The facts are `Recap` (`Usage/Recap.swift`); this page owns how they are drawn and the window that shows and exports them. Views live in `Settings/` as `Recap*.swift` — the recap belongs to the settings side of the app, and the cards are not part of the panel.

Called **月报** in Chinese (`Monthly Recap` in English; the year is `Yearly Recap` / 年报, and Japanese and Korean have their own words, written rather than converted).

## The cards

| Card | Month | Year | Needs |
|---|---|---|---|
| Poster (`poster`) | yes | yes, with twelve month bars where the month has its calendar | any tokens |
| Opener (`opener`) | month number, headline, an agent lineup (the top agent a big ink tile, up to three more, a lime "in all" tile), a roster with each agent's days as a strip | the year, the same, the strip a cell per month | `agents` |
| Calendar (`calendar`) | the total with its change on the month before, every day a cell, three tiles (active days ring, streak chain, busiest day), the weeks, weekdays against the weekend | — | a day with tokens |
| Year calendar (`yearCalendar`) | — | the total, twelve small calendars, the same three tiles | a day with tokens |
| Months (`months`) | — | twelve rows (busiest in ink) and weekdays against the weekend | twelve months |
| Timetable (`timetable`) | peak hour, a 24-hour dial, when the day starts and ends, four parts of the day, 24 bars, seven weekdays | same | `hours` and `peakHour` |
| Payback (`payback`) | cost and multiple, a ruler (the used bar cut by model), three tiles, cache against no cache, spend by model with the maker's mark, money by day | the same, money by month | `cost` **and** a price |
| Scorecard (`scorecard`) | the total with its change, money with its daily line, days / sessions / peak hour / cache, a bar per day, tools, top model, persona | same, with a bar per month | any tokens |

The poster stands alone and is not numbered; the others carry "01 / 05", counted over the cards the deck really has.

A year calendar was drawn both as twelve month grids and as one 53-week strip. The strip is unreadable at 1080 wide (14 pt cells, no month names) and was dropped.

## Nil means left out

`RecapDeck` (`RecapDeck.swift`) returns the cards in order. **A card whose data is nil is not drawn**, and a figure inside a card whose data is nil is not drawn with a zero:

- no agents, no opener; no hour shape, no timetable; no cost, no price (`monthlyPrice`, typed by the reader, in `Recap.currency`), no payback — and, with no cost, no money figure anywhere, including the poster's tiles and the scorecard's cells;
- an empty recap has no deck;
- the poster is a stack of rows that appear only when their facts exist; the rows that remain share the height, so a thin recap is a shorter poster, not one with holes;
- the scorecard (below) drops a row, a cell or a chart it cannot fill;
- **a month still to come in a running year is not a quiet month** (`RecapInsights.isMonthToCome`): the opener's strip, the payback card's money by month and the Months card draw it as a dashed outline with no figure, as the scorecard does.

The change chip says "vs same period in August" on every card that draws it (poster, calendar, scorecard): `previousTokens` covers the same number of days of the period before, so "vs August" alone would overstate what was compared. A positive payback multiple that would round to 0.0 reads "<0.1".

Payback is `cost / (price × months)` (`RecapPayback`): one month for a month, twelve for a year. **A period still running is prorated by days**, not by whole months started: `months = (1 or 12) × elapsed days ÷ days in the month (or the year)`, so the 5th of a 31-day month is 5/31 of the price and March 1 of a 365-day year is 12 × 60/365 — and the payback card says "Figures are to date, and the plan price is prorated by the days so far." Below 1 it is shown as it is.

**Partly unpriced money.** `Recap.unpricedTokens` is the tokens with no published price behind them. Above zero, `cost` is only the priced part — a floor — and the poster's footer, the payback card's footnote and the scorecard say "Some work had no published price, so the money is a floor." Unpriced work does **not** take the payback card away: the multiple is then a floor too, and the card carries the same note. It once was left out from 1% of the tokens, which for a heavy month with an unpublished model (swe-2-high, 1.2% of five billion tokens) meant never, with nothing on screen saying why. Cost stays nil when nothing was priced. The poster's cost line under the total is not drawn if any day (or month) *with work* has no cost — quiet days are a real zero, unpriced ones are not drawn as one. The cache sentence and the "cache saved you" row appear only from $0.50 (`RecapDeck.minimumSavings`); "saving about $0.00" is not written.

**Streaks belong to the period.** `currentStreak` and `longestStreak` are counted over the recap's own `days` (`Recap.streaks`), never the whole history: the longest run of days with work inside the period, and the run that ends on the period's last day — a past period's final day; a running one's today, or yesterday while today is quiet ("today is not over"), counted inside the period only. Only a running period's current run is "still going": a past period's card says **Longest streak** and nothing about the run still going.

`hidesProjects` replaces project names with "Project 1", "Project 2"… (`RecapDeck.projectName`). The footer says when figures are to date (`isInProgress`) and when the total is a floor (`isPartial`), and that money is an estimate at API prices.

## The scorecard

`RecapScorecardView` (`RecapScorecardView.swift`; what its charts are built from is `RecapScoreData.swift`, tested in `RecapScoreDataTests`). Top to bottom: the running head with an outlined stamp for the period (`NO. 2026·10`, a year `NO. 2026`) and the page counter; the headline; **the total** huge on a lime bar, with a dark chip for the change on the same stretch of the period before and the label (`Tokens · to Oct 5` only while the period runs); **the money** and a mini line of cost per day (per month in a year); a **2 × 2** of active days (one pip per day — ink for work, grey for a quiet day that is over, hollow for a day to come; a year's twelve months in two rows), sessions (with the average per day *with work*, rounded, left out where it rounds to nothing), peak hour (24 bars, the peak in ink, hours with work lime) and cache hit (a thin meter); **a bar per day** of the month (a bar per month in a year) with a grey slot behind each, the busiest in ink, a day to come a dashed outline, the busiest named on the right; **tools** as one segmented bar (top lime, second ink, third grey, and past three everything after the second grouped as "Other") with a legend of shares; the **top model** with its share and the **persona** as a dark chip; the footnotes; the footer.

Nothing here is invented. **The chip** is `Recap.previousTokens`, which is counted over the *same number of days* of the period before, so "same period" is literal; it is left out without it. **A day to come is not a quiet day**: in a running month the days after today (and in a running year the months that have not begun) are `future`, are drawn hollow or dashed, and are not points on the cost line. The cost line follows the poster's rule (`RecapDeck.costSeries`): none where any point with work has no price. Heights in the strip are tokens over the busiest slot's, each against a grey slot of full height, so a quiet day reads as an empty slot, not a short bar. A cell whose fact is nil (no hour shape, no cache) is not drawn, and an odd one out takes the whole row. The payback and the streak have their own card and the poster, and are not repeated here.

Every picture shrinks before a figure does, and a figure before it is dropped (`ViewThatFits`), so a long English chip, a four-digit session count or a 6,240万 total never run into their neighbours.

## The four redesigned cards

The opener, calendar, timetable and payback follow the approved mockups (a lineup, a dial, tiles and rulers rather than rows of text). Each has its own file (`RecapOpenerView`, `RecapCalendarView`, `RecapTimetableView`, `RecapPaybackView`); the pieces they share — tiles, section heads, the segment ring, the streak chain, brand marks — are in `RecapTiles.swift`, and every figure they read that `Recap` does not carry is worked out in **`RecapInsights`** (`Usage/RecapInsights.swift`, tested in `RecapInsightsTests`), never in a view:

- **Weekdays and weeks.** `weekdayTokens` (Monday first; **nil for a weekday the period never had a day of**, which is unknown and not quiet), `workSplit` (weekday against weekend tokens, the days the period has had of each and the days used — Saturday and Sunday are the weekend), `weeks` (Monday to Sunday, **clipped to the period**, the first and last may be short), `busiestWeek` / `busiestWeekday` (the earliest of a tie).
- **The streak.** `longestRun` is the earliest of equal runs; `streakChain` is a window of nine days around it, kept inside the period (against the edge where it cannot be centred), with the run's days marked. A run of nine or more shows its first nine and the label names where the run really ends.
- **Time of day.** `firstHour` is the earliest hour from 05:00 with any work (the after-midnight tail belongs to the night before; nil when only that tail has work), `quarters` the four six-hour shares of the hour shape and `leadingQuarter` its largest. "Under one" is `RecapFormat.percent`'s `<1%`, never a zero.
- **Money.** `costPerMillion` is the cost over the **priced** tokens (a floor over every token would understate the rate); `costPerActiveDay`; `costliestDay` and `costBars` (money by day, or by month for a year) exist **only when every day or month with work has a cost** — the dearest might be the unpriced one, and a bar for it would be a zero. A quiet day is a real zero. The cache tile and the cache against no-cache bars appear from $0.50 (`RecapDeck.cacheSavings`), and the "N× what you spent" line only when the saving is more than the spend.
- **Who worked when.** `Recap.AgentShare.activeDates` (the agent's own days; also `days` in `--recap`) feed `dayMarks` (used / another agent / quiet weekend / quiet weekday) for a month and `monthMarks` (used / another agent / quiet) for a year. An agent with no dates gets no strip.

**Brand marks.** An agent's mark is `SpendAgent.iconResource` through `LobeIconView` (a template image, tinted ink or lime); a model's is `RecapVendorMark.resource(forModel:)`, a table of name fragments (claude, gpt and the o-series, gemini, glm, kimi, deepseek, qwen, mistral, minimax, grok, and a few more). **No mark is guessed**: a name that matches nothing, or an agent with no mark, gets a tile with its first letter. Every resource the table names is checked to ship (`RecapVendorMarkTests`).

**A scaled label is never squeezed vertically.** A `Text` with a scale floor inside a stack that is a few points short gives up its size, all the way to the floor, for no visible reason (it happened on the weekday headings, a tile's caption, the timetable's figures and the model names all at once). `View.recapFit(_:)` is `lineLimit(1)` + `minimumScaleFactor` + `fixedSize(horizontal: false, vertical: true)`; use it for any label that may shrink.

## Drawing

Flat colour and type only — paper `#F5F5F1`, white cards with a hairline, ink `#1B1B1E`, lime `#C8F03C` (the icon's accent). **Lime is a fill, never text on paper.** No gradient, blur, shadow, material or emoji, and nothing `ImageRenderer` cannot draw. Type is the system face and its CJK fallback; labels and digits use the monospaced design. The Pulse mark is drawn from `AppIcon/pulse-mark.svg`'s path.

Hero numbers are set tight and trimmed to their digits (`RecapFigureText.trimmed`; the ascender and descender fractions are measured against the system font). **Tight numbers go through `Text(tight:tracking:)`, never `.tracking` with a negative value**: SwiftUI takes tracking after the last glyph too, which pulls the frame in past the last digit's ink, and the text is drawn inside its frame — the right of a 9 or a 5 came out cut off flat. `Text(tight:)` tracks every character but the last. `minimumScaleFactor` on a `Text` inside an `HStack` with a `Spacer` can be shrunk to its floor for no visible reason; give such a row a fixed frame or leave the factor off.

`RecapRenderer.png(of:in:)` renders a card at scale 1.

## One calendar

Recaps are built, offered and named in `Recap.calendar` — Gregorian, weeks from Monday, the system's time zone — **not** `Calendar.current`: a Buddhist or Japanese system calendar numbers the year 2569 or Reiwa 8 while the cards print the Gregorian year, so a recap asked for as "2026" would be built over another span than the one it names. `Recap.build`, `RecapPeriods`, `RecapNoticeRule` and `--recap` all default to it, `RecapFormat.calendar(locale:)` is it with a locale, and a `Recap` carries the calendar it was built with: the year calendar derives its twelve months from `start` by month offsets in it (`Recap.monthStarts`) rather than from the year number. Every busiest-day highlight (poster and month calendar) marks only `recap.busiestDay`, the earliest of a tie.

## Language

Copy goes through `String.localized` like the rest of the app ([development.md](development.md)); the cards add four rules.

- **Figures inside a sentence are marked, not split.** A translation puts a number where its language wants it, so the card hands the value to the key wrapped in `RecapEmphasis.mark`, and `RecapRichText` finds it again to set it bold (on a lime bar where the card asks for one).
- **Numbers, hours and dates come from the locale** (`RecapFormat`). A token count is a big number and a small unit: 万/亿 in Simplified Chinese, 萬/億 in Traditional Chinese, 万/億 in Japanese, 만/억 in Korean, K/M/B otherwise — by `TokenCount.parts`, the same rule as `TokenCount.short`, so the panel and the cards never disagree about where 亿 begins. Weekdays start on Monday; headings are one character in Chinese, Japanese and Korean and the short name elsewhere. Hours are 24-hour except in English, where they read "11 PM" (the other three put the half-day before the hour, which a number with a unit cannot say). Dollars are "$" in every language.
- **Cards say "AI tools"; the pane says "Agent".** The Token spend pane's word for a Claude Code, Codex or Grok is *Agent* (エージェント, 에이전트, an `Agent` column); a recap card is an image someone else reads, and the people reading it do not use that word, so the cards use the plainer 工具 / ツール / 도구 ("AI tools", "Tools", "Worked beside you"). It is deliberate and not to be "fixed" back to the pane's term. The same goes for an active day, which the pane calls a day with records (有记录的天数): each language's recap keys use one term for it — 活跃日 (Simplified), 活躍日 (Traditional), 活動日 (Japanese), 활동일 (Korean).
- **Longer copy must survive.** Headlines wrap or scale; every label that can be long is a single line with a scale floor or two lines. Look at all five languages after changing any copy.

Persona names are written per language (`Recap.Persona.title`), not translated from one another.

## Reviewing

```bash
PULSE_RECAP_PREVIEW=/tmp/recap swift test --filter RecapRenderTests
```

writes every card of the sample month and year in all five languages to `/tmp/recap/<language>/<deck>-<n>-<card>.png`, one `sheet.png` contact sheet per language, and `/tmp/recap/edge/` for recaps with a field missing (no price, unpriced, bare, in progress, a year in progress, no hours, no cache, a floor, mostly unpriced). The samples are `RecapSamples` (`#if DEBUG`), which the `#Preview` blocks in `RecapRenderer.swift` share. The test pins nothing about pixels: a card either fits its language or it does not, and the only judge is reading it.

`RecapInsightsTests` pins everything in "The four redesigned cards" (weekday and week totals and their nil cases, the chain at the middle, the edge and in a short or long run, the first hour and the quarters, money per million over priced tokens, the dearest day and the daily and monthly bars with one unpriced day, the strips); `RecapVendorMarkTests` the model-to-mark table; the render also draws `edge/one-agent`, `two-agents`, `three-agents` (the lineup's other shapes) and `six-weeks` (August 2026, six rows of days and six weeks).

`RecapTests` pins the streaks of a past and a running month, `unpricedTokens`, and a Buddhist-calendar build whose year months follow the calendar; `RecapWindowTests` the price grammar, `RecapPeriods.earliest`, the read-generation race and `takesArrows`; `RecapDeckTests` the payback rules (unpriced share, proration), the cost line, the savings floor and the streak wording; `RecapScoreDataTests` the stamp, which slots are quiet, future or busiest in a running month and year, the per-day session average and the tools' grouping. The edge renders are in English and, for `in-progress`, `floor` and `mostly-unpriced`, also in `edge-zh-Hans`, `edge-ja` and `edge-ko`.

`RecapFormatTests` and `RecapDeckTests` pin the number split per locale, the date and hour formats, the ruler, and which cards each recap gets.

## The window

`RecapWindowController` (`Settings/RecapWindowController.swift`) owns an AppKit window, as the settings window is owned, for the same reason: Pulse is an `.accessory` app and has to activate itself or the window opens behind everything. `RecapWindowModel` is its state, `RecapWindowView` its SwiftUI, `RecapExport` its way out.

**Entry points** — both open the same window, and neither menu carries one (the rail's and the menu bar's menus stay to the panel, Settings and Quit):

- the Token spend pane's **Monthly and Yearly Recap** row, with two buttons side by side so the yearly recap is not found only inside the window: **View September recap** opens on that month (`TokenSpendPane.recapPeriod`, the window's own default rule) and **View 2026 recap** on the year by the same rule (`RecapPeriods.defaultYear`: January 1–7 opens the year that just ended, any other day this one, in progress; the year is a plain string, never "2,026");
- a clicked "recap is ready" notification, on the month it names ([notifications.md](notifications.md#the-monthly-recap)).

**Layout.** The deck on the left, one card at a time, drawn live and scaled to fit (`RecapCardView` at 1080 × 1920, `scaleEffect`), with previous / next buttons beside it and dots with a "1 / 5" counter under it; **← and →** turn the page. On the right: the period, the price, the privacy switch and four buttons. The window follows the system's light or dark; only the cards are paper.

**Keys are the window's own.** `RecapWindow.sendEvent` takes a bare ← or → while this window is key, **no text field is being edited** (the price field keeps its caret keys) and the first responder is not a control that uses the arrows itself — the Month / Year segments, a popup, a slider, a stepper, a text view (`RecapWindow.takesArrows`). No global monitor and no `NSEvent.addLocalMonitorForEvents`. The same method ends field editing on a click outside the field (`NSWindow.endFieldEditing(ifOutside:)`, shared with the settings window).

### Which period

- **Offered:** every month, and every year, from the earliest record on this Mac to now, newest first (`RecapPeriods.months` / `years`; the earliest is the earliest of the `earliest` of the ledgers the Token spend pane may show — `Origin.supportsTokenSpend`, so a provider's own statistics do not decide it — and never before 2020-01-01 (`RecapPeriods.floor`), so a bogus timestamp cannot produce hundreds of empty months). Nothing before the first record, nothing after today. Until the read has finished only the default is offered.
- **Opened on:** the month that **just ended during the first seven days of a month** (October 1–7 opens on September), **the running month from the 8th**. For years the same rule with January 1–7. If that falls before the earliest record it moves up to it; until the read has said where records begin (the Token spend button's label, a window still reading) the rule stands alone, so the button can read "View September recap" first and move to October if records only begin then. `RecapPeriods.defaultMonth` / `defaultYear`; a period asked for (the notification's, the Token spend button's) is kept over the default.
- **Month / Year** is a segmented control; switching keeps the year (a month becomes its year, a year becomes its last offered month). The window title follows it.

### The price and the privacy switch

- **Monthly price**, in US dollars, typed into the window (a "$" before the field and one line saying it is only used for the payback card). Stored as `AppSettings.recapMonthlyPrice` (`Double?`): **empty and 0 both mean no price**, and no payback card is drawn — never a guess, never a zero. **Parsing is strict and does not guess the locale** (`RecapPrice.entry`): after trimming whitespace and one leading "$", either plain digits with an optional "." or "," and one or two decimals (`20`, `12.5`, `12,5` = 12.5), or digits grouped by "," in valid groups of three with an optional ".dd" (`1,200`, `1,200.50`). Anything else — `abc`, `free`, a lone `$`, `1e3`, `20 USD`, `-5`, `1,2,3`, `12.345`, `>10000` — and anything over `RecapPrice.maximum` (10,000) is refused and the field goes back to what was kept. It is taken on Return, when the field loses focus, and before any export — so a price typed and a button pressed straight away exports the payback card.
- **Hide project names** (`AppSettings.recapHidesProjects`, **off**: names are shown) is `RecapDeck.hidesProjects`.
- Both are stored and read back whole-app, like every setting, and both change the deck live.

### States

| State | What the left side shows | Right side |
|---|---|---|
| Token spend reading **off** (`needsReading`) | An icon, "The recap needs Token spend", one sentence saying it is built from this Mac's usage records and read only while reading is on, and an **Open Token spend** button that opens Settings on that pane. **Nothing is switched on for the person**; if they switch it on while the window is up, it starts reading. | Controls visible, export disabled |
| Reading (`loading`) | A bar through the agents (`Reading Claude Code…`, `4/12`, as the pane's own row) once there is progress, a spinner before; and "The first read of a long history can take a minute or two." The first read is long (about forty seconds on a large history); a kept fresh scan (`SpendWarmer`) skips it. | export disabled |
| Working out a period (`isBuilding`) | A small spinner. Off the main actor; cached per period while the window is open. The records are read again when the window is shown, or a period chosen, half an hour after the last read or on another day (`RecapWindowModel.isStale`), so a running month's "to date" does not stop where the first read did. | |
| **No records** | "No records for September 2026" and a line saying nothing in this Mac's records falls in the period. | export disabled |
| Could not read (`failed`) | A message and **Retry**. | |
| Ready | The card. | all four buttons |

**Cancellation.** Each read carries a generation (`RecapWindowModel.loadGeneration`): a cancelled read that finishes after a newer one has started — close and reopen, or reading switched off and on — neither clears the newer read's reference nor hands over its result. The read is one read for every period, so changing period never restarts it — a month change only rebuilds a `Recap`, and a rebuild for a period no longer on screen is dropped. **Closing the window cancels a read in progress** and drops the ledgers and every recap built from them (`RecapWindowModel.windowDidClose`); nothing is read while it is closed. Switching Token spend reading off under an open window drops them too.

### The ledgers

`RecapSource.load` (`Usage/RecapSource.swift`) is the one path to them, shared with `--recap`: the scan `SpendWarmer` keeps while Token spend is on if it is younger than `SpendWarmer.paneFreshness`, otherwise `AgentLedgers.scan` with progress, and the price table. It does not check the setting; the callers do.

### Export

All of it renders the card again at full size with `RecapRenderer` — never a screenshot of the preview. `ImageRenderer` is main-actor, so rendering stays on main (one card is well under a second; **Save all** yields between cards).

| Button | Does |
|---|---|
| **Save image** | The card on screen → `NSSavePanel` (a sheet on the window), `pulse-recap-2026-09-02-opener.png` |
| **Save all** | `NSOpenPanel` for a folder, then every card including the poster, `pulse-recap-<period>-<nn>-<card>.png` in deck order. **It overwrites** a file of the same name in that folder (a second save of the same recap lands on the first); nothing else in the folder is touched |
| **Copy image** | PNG (and TIFF, for apps that read only that) on `NSPasteboard.general`; "Copied" |
| **Share image** | One PNG written to its own folder, `…/Pulse Recap/<UUID>/`, in the temporary folder — a later share never removes an earlier one's, since the app it went to may still be reading it — and handed to `NSSharingServicePicker`, anchored to the button. The whole `Pulse Recap` folder is deleted when the recap window closes (`RecapExport.removeShareFolder`) |

A line under the buttons says "Saved", "Copied" or "Couldn't make the image." for three seconds; cancelling a panel and opening the share sheet say nothing.

### The Dock icon

The window shares the Dock-icon-while-open rule with Settings, through one owner, `DockPresence` (`App/DockPresence.swift`): Pulse is a regular app (Dock icon, ⌘-Tab) while **any** of its windows is on screen and `AppSettings.showsDockIconInSettings` allows it, and a menu bar app again when the last closes. With one controller per window, closing Settings under an open recap took the icon from the recap. Its label says so: "Show Dock icon while Settings or a recap is open".

