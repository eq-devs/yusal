# Yusal UX plan

Date: 2026-11-09 · Follows `docs/ux-audit.md` (finding numbers in brackets).

## Direction

One product, one look. The platform's warm, Airbnb-like language is the product's face; the drafting look stays inside the design tool, where it helps. Every screen answers "what is here, what can I do next" without scrolling past decoration.

Rules for this round:

- Business logic, repositories, file formats and the editor's drawing behaviour are not touched.
- Every change is covered by a test or a screenshot; the suite stays green.
- Nothing is deployed, committed or pushed without being asked.

## Design system

Lives in `lib/platform/ui/theme.dart` (tokens) and `lib/platform/ui/components.dart` (parts).

| Token | Values |
| --- | --- |
| Space (`YSpace`) | 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 — a 4 px grid; page gutter 20 |
| Radius (`YRadius`) | 8 dense rows and inputs · 12 controls · 14 cards · 18 chat bubbles · 20 sheets and dialogs · pill |
| Type (`YFont`, `YText`) | caption 12 · small 13 · label 14 · button 15 · body 16 · heading 18 · section 20 · title 22 · display 24–28, in Onest; Lora for display and house names; tabular figures for money and sizes |
| Colour (`YTokens`) | unchanged palette, plus `onFill()` (text on an ink or status fill), `onImage` (backing of a control on a picture) and `paper` (the sheet behind a drawing); no literal colours in pages |
| Touch | 44 px minimum on pills, rows, buttons and icon buttons (the one-line demo notice is 28 px: it is information first) |
| Motion | existing `lib/motion`: ≤ 200 ms feedback, ease-out entrances, reduced motion respected |

Parts: `SearchField`, `FilterPill` (toggle, or with `menu:` a pill that opens a list — sort, region, trade), `SettingsGroup` / `SettingsRow` (inset grouped list), `SignInPrompt`, `Skeleton` / `SkeletonList`, `IconAction` (labelled round icon button on a picture), `DemoNotice`, `LiveRefresh` (pull-to-refresh for any `Live` list), `onFill()` (readable text on any fill), and the adaptive shell (bottom bar under 840 px, rail above).

## Work, in order

Status: ☐ planned · ◐ partly done (see below the tables) · ☑ done and verified · ✕ dropped (with reason)

### P0 — broken

| # | Change | Status |
| --- | --- | --- |
| A1 | Messages tab for guests: a sign-in prompt instead of an error with Retry; no "mark all read" [1] | ☑ |
| A2 | `StatusPill` and badges take their text colour from the theme; fixes the unreadable night pill [2, 21] | ☑ |
| A3 | House page app bar: icons on a solid round backing while the cover is visible [3] | ☑ |
| A4 | Workspace tabs scroll instead of truncating [4] | ☑ |
| A5 | Demand bottom bar: price gets the room, button keeps its size, nothing is cut [5] | ☑ |
| A6 | Opinion form: full-width text field, Send below it [6] | ☑ |
| A7 | Register Flutter localisations for Kazakh, Russian and Chinese; system texts and screen-reader labels follow the app language [7] | ☑ |
| A8 | Labels on every icon-only button [8] | ☑ |

### P1 — core UX and navigation

| # | Change | Status |
| --- | --- | --- |
| B1 | My houses rebuilt in the platform look: one title, my designs first, each card with its drawing and two visible actions (Continue, Find builders) and the rest in the menu; "New design" as the primary button; the example moves to the empty state and a quiet "start from an example" row [9, 11] | ☑ |
| B2 | Russian for the whole design tool [10]: the list and dialogs, all ten pages, tools, selection cards, checks, core messages, the PDF drawing set, and table texts (furniture, materials, stages, checklists) | ☑ |
| B3 | Demand cards without a drawing become text-first: type and status on one line, then title, place, trade, budget, start. The cover stays only when there is a real plan. Same on the demand page [12] | ☑ |
| B4 | Demo notice: one quiet line with an info icon that opens the explanation [13] | ☑ |
| B5 | Me tab: profile header, then grouped lists (My activity, Professional profile, Settings, Account); language and theme as rows with pickers; sign out and delete as rows [14] | ☑ |
| B6 | Adaptive shell: navigation rail from 840 px [15] | ☑ |
| B7 | Design tool header on phones: language and theme move into the "…" menu; the three-language toggle no longer skips Russian [16] | ☑ |
| B8 | One search field and one pill style across Discover; sort becomes a pill [17] | ☑ |

### P2 — visual consistency

| # | Change | Status |
| --- | --- | --- |
| C1 | Tokens above in `theme.dart`; theme parts (buttons, inputs, chips, tabs, sheets) read them; no literal font size, corner radius or colour is left in a platform page, and a test keeps it so [18] | ☑ |
| C2 | Text buttons lose the underline and take the accent colour [19] | ☑ |
| C3 | 44 px touch targets for pills and chips [20] | ☑ |
| C4 | Placeholder covers and avatars adapt to night; remaining literal whites removed [21] | ☑ |
| C5 | Skeletons for the feed, demand list, pro list and inbox [22] | ☑ |
| C6 | Demo content follows the language chosen at launch; test accounts on the sign-in page are labelled in the app language [23] | ☑ |
| C7 | Pro page stats: labels that fit, no mid-word wraps [24] | ☑ |

### P3 — polish

| # | Change | Status |
| --- | --- | --- |
| D1 | Pull-to-refresh on feed, work, pros and inbox [25] | ☑ |
| D2 | Tabular figures wherever money or sizes are listed in a column: cards, the demand bar, pro stats, design sizes, info rows, quantity rows, the quote comparison. Amounts inside sentences («Принято X из Y») keep proportional digits on purpose [26] | ☑ |
| D3 | Fade at the edge of the design tool's page strip to show there is more [27] | ☑ |

Still inline: paddings and gaps. They sit on a 2 px grid already (4, 6, 8, 10, 12, 14, 16, 20…); renaming several hundred of them to tokens would change no pixel and was left out.

Also fixed along the way (found while testing, not in the audit):

- Own chat bubbles were white on a light bubble at night; the send icon, switch thumbs and snackbar action had the same kind of fault.
- Warning notices used orange text on a tinted box at 3.7 : 1; the text is now ink, the icon carries the colour.
- Destructive confirmations (delete design, delete account, hide a house) now have a red confirm button — `confirmDialog(danger:)` existed but did nothing.
- Dialogs stretched across a desktop window; they are capped at 460 px.
- With the demo notice shown, pages left room for the status bar a second time on notched phones.
- The budget page's bar chart overflowed by a fraction of a pixel in Kazakh. An existing test meant to catch this tapped page tabs that were off screen, so it passed without opening the pages; the page strip now scrolls the chosen tab into view, the test reaches the pages, and the row is fixed.
- The read-only plan viewer showed automatic room names in Chinese in every language.
- Plan pictures sat on a tinted gradient; they now sit on drafting paper in both themes.
- Leaving the design tool's language switch on a phone could only flip between Chinese and Kazakh; Russian was unreachable from there.
- The header menu, undo, redo and save tooltips of the design tool had no Russian; found by the coverage test below.

## Where this work lives

The round was started on the `ship` branch, which turned out to be 37 commits behind `origin/dev` (real backend for every repository, simulator tests against the real API, editor changes). The finished work was ported onto `origin/dev` in the worktree `../yusal-ux`, branch `ux/world-class-on-dev`, uncommitted. Ten files conflicted: the design list, header, pages and tests were taken from upstream and the changes re-applied (the Russian rewrite is a script and was simply re-run, with 49 new upstream strings translated); the Me tab was merged by hand and keeps upstream's reload fix and phone setting. The changes left in the `ship` checkout are the same work on the older base.

## How Russian was added to the design tool

The tool was written as Chinese / Kazakh pairs: 1,050 strings at their call (`tr(zh, kk)`) and about 330 in tables (furniture, materials, stages, checklists, core messages, check texts).

- Every string at a call now carries three languages (`tr3(zh, kk, ru)`), the same form the platform pages use. The rewrite was mechanical: a script found each call and added the third argument.
- Table rows keep two columns; `tr()` looks the Kazakh text up in `lib/app/messages_ru.dart` when the app is in Russian.
- Check texts built with numbers in them (plot distances, foundation depth, heat loss) got a third, Russian element; the core's message patterns got Russian builders.
- The translations were produced in seven parallel batches from the Kazakh with the Chinese as a second source and a shared glossary, checked mechanically (same placeholders, no Kazakh-only letters, no Chinese), then unified by hand where batches disagreed (общая площадь, Г- and П-образная лестница, в свету).
- A second, independent pass read the Chinese and the Russian only (not the Kazakh) and flagged real problems: 38 of about 1,080 strings — dropped qualifiers («Расчётная тепловая нагрузка», «с каждой стороны»), buttons phrased as nouns («Вернуть значения по умолчанию»), two wrong readings («Заселение в дом», «Кухонная столешница»). All 38 were applied. This is not a native-speaker review.
- `test/ru_coverage_test.dart` opens the example house in Russian, walks all ten pages at 1280 and 390 px, and fails on any text with a Kazakh-only letter or a Chinese character. It also fails if a two-language string is written at a call again, or a table row has no Russian.

## Verification

| Check | Result on the last build |
| --- | --- |
| `flutter analyze` | 0 issues |
| `flutter test` | 430 passed in `../yusal-ux` on current dev — upstream's suite plus 19 in `test/platform/ux_round_test.dart`, 4 in `test/ru_coverage_test.dart`, 3 in `test/platform/design_system_test.dart` |
| `flutter build web --release` | succeeded |
| End-to-end in Chrome, `tool/ux/e2e.mjs` | 11 of 11 flows pass on the ported build, no console errors: guest browsing and sign-in gate · sign-in, language, theme, sign-out · create a design by size · example house and editor pages · publish a house · find builders from a design · a pro sends a quote · chat · write an opinion · owner's workspace · desktop rail |
| Screenshots in Chrome, `tool/ux/r1.mjs`, `r2.mjs` | 390 px day and night, 1280 px day; reviewed by eye; `docs/screenshots/ux-2026-11-09/after/` |
| iOS simulator (iOS 26.4, "Yusal E2E") | `platform_smoke_test.dart` 1 of 1 and `app_test.dart` 5 of 5 pass on the ported code. Upstream's `app_test.dart` tapped tools that the phone toolbar keeps behind "more"; the test now opens "more" when needed. `screens_tour_test.dart` captures: `after/12-ios-simulator.png` |
| Android emulator (`yusal_e2e_26`, Android 8.0, created for this) | `platform_smoke_test.dart` 1 of 1 and `app_test.dart` 5 of 5 pass on the ported code, including native file saves and WebP previews. The simulated keyboard did not reach the publish form's title field on this emulator, so the smoke test sets that draft through the field's controller. Tour captures: `after/13-android-emulator.png`. The existing `Pixel_2` emulator had 360 MB free and could not take the 105 MB debug build |
| Real phone: Pixel 8 Pro, Android 16 | `platform_smoke_test.dart` 1 of 1 and `app_test.dart` 5 of 5 pass on hardware. The smoke test now looks for the card's button inside its own card, since a phone may hold other designs |

Both device suites had gone stale before this round (they assumed the design list was the first screen, typed into "the first text field", did not wait for the native preview to be saved, and tapped tools the phone toolbar hides). They were brought up to date; no product fault was behind any of their failures.

Not run: the device tests against the real `yusal-api` (`backend_flow_test.dart`, `market_flow_test.dart`, …). The local server writes to a remote MongoDB, so running them would create test data there; that needs the owner's go-ahead. Their finders were checked statically against the changed screens.

## Not in this round

- **Redesigning the editor.** Its tool rail, selection cards and ten pages were tuned over five earlier rounds with their own tests; this round changed its header, page strip and language.
- **Real photos, follow, payments, the remaining backend modules** — product scope, listed in `PRODUCT_REPOSITION.md`.

## Progress log

- 2026-11-09 — Audit and plan written. Baseline: analyze 0 issues, 365 tests passing.
- 2026-11-09 — Round 1 (P0 and the My houses rebuild) implemented; reviewed on screen at 390 px, day.
- 2026-11-09 — Round 2 (Me tab, Discover, shell, editor header, demo content, skeletons, refresh) implemented; reviewed at 390 px day and night and at 1280 px.
- 2026-11-09 — Round 3: radii moved onto the scale, pull-to-refresh in Messages, single-word room labels no longer break mid-word in the plan viewer.
- 2026-11-09 — Round 4: Russian for the whole design tool with a coverage test; type sizes and colours moved onto the system with a guard test; end-to-end flow checks; both device suites repaired and run on the iOS simulator.
- 2026-11-10 — Both device suites run and pass on a real Pixel 8 Pro (Android 16).
- 2026-11-10 — Round 5: the work ported onto current `origin/dev` in `../yusal-ux`; an independent review pass over the Russian (38 corrections applied); tabular figures in quantity rows, info values and the quote comparison; both device suites run on Android as well. Final check on the ported code: analyze 0 · 430 tests · web build · 11 of 11 browser flows · iOS 1 + 5 · Android 1 + 5.

## Known limits of the verification

- **Hardware: Android only.** Both device suites pass on a Pixel 8 Pro; iOS was checked on a simulator only. Haptics, the share sheet into WhatsApp or Telegram, and performance on a slow phone were not checked.
- **Translations had two machine passes, no native speaker.** The Russian of the design tool (about 1,400 strings) was translated with a glossary and consistency checks and then reviewed independently (38 corrections); the Kazakh and Russian demo content had one pass. A Russian-speaking builder should still read the construction terms before release; `lib/app/messages_ru.dart` and the third argument of `tr3` are where to correct them.
- **Text drawn on the plan and in the PDF** is translated but is not covered by the coverage test, which reads widgets, not canvases.
- **The real backend** (`YUSAL_API`) was not exercised; everything ran on the in-memory demo backend.
