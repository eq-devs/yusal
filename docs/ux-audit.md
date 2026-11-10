# Yusal UX audit

Date: 2026-11-09 · Branch: `ship` · Baseline: `843a6ac`

## How this was done

- Read the architecture: `lib/platform/ui` (platform pages, 15k lines), `lib/features` (design tool, 6.7k lines of UI), `lib/app` (settings, drafting tokens), `lib/motion`.
- Built the web release and drove it in headless Chrome with Playwright (390 × 844 phone, 1280 × 800 desktop; Russian, Kazakh, Chinese; day and night). Walked as a guest and as the demo owner: the four tabs, sign-in, a house page, a demand, a pro profile, a house workspace, a chat, the design tool, publish a house, find builders from a design, post a demand, and the settings pages.
- Baseline before any change: `flutter analyze` 0 issues, `flutter test` 365 passed.
- Screenshots: `docs/screenshots/ux-2026-11-09/before/`.

Not covered by the audit itself: physical iOS / Android devices (none attached), the real Go backend (audited on the in-memory demo backend), screen readers by ear (the accessibility tree was read through Flutter's web semantics instead). After the fixes, the app and both device test suites were run on an iOS simulator; see `ux-plan.md`, Verification.

## What the product is

Design your own house → show it → get opinions → find people to build it. Four tabs: Discover (houses, work, pros), My houses, Messages, Me. The design tool is a full drafting app (2D, 3D, walk-through, construction, heat, budget, schedule) that predates the platform and has its own look.

## What already works well

- Clear visual identity on the platform side: warm paper, walnut accent, Lora titles, Onest UI text.
- House cards and the house page read well; the plan drawing as the cover is distinctive.
- Motion is centralised (`lib/motion`) and respects reduced motion.
- Destructive actions confirm; forms guard unsaved changes; lists have empty and retry states.
- Three languages on the platform side; day / night / auto themes.

## Findings

Severity: **P0** broken or unusable · **P1** core flow or navigation friction · **P2** inconsistency · **P3** polish.

### P0 — broken

| # | Where | What happens | Evidence |
| --- | --- | --- | --- |
| 1 | Messages tab, signed out | Shows an error, "Sign in first", with a **Retry** button that can never succeed, plus a "Mark all read" action. A guest has no way forward from this tab. | `before/01-guest-tabs.png` |
| 2 | Night theme, feed | The "asking for opinions" pill is white text on a near-white pill: unreadable. `StatusPill(filled: true)` always paints white text, but the fill is `ink`, which is light at night. | `before/10-night.png` (explore) |
| 3 | Night theme, house page | Back, share and menu icons are light on the light plan drawing: invisible until the page is scrolled. | `before/10-night.png` (post) |
| 4 | House workspace | The four tabs do not fit a phone in Russian: "Предлож…", "Соглаше…" are cut. | `before/06-workspace-chat-editor.png` |
| 5 | Demand page | The price in the bottom bar is cut ("Ждём предло…") beside the action button. | `before/04-houses-inbox-demand.png` |
| 6 | House page, opinion form | The text field is squeezed into a narrow column beside the Send button; the hint wraps to three lines. | `before/03-pros-house-page.png` |
| 7 | Whole app | No Flutter localisations are registered, so system texts are English in every language: "Back", "Dismiss", "Show menu", text-selection menus, and what screen readers announce. | accessibility tree dumps |
| 8 | Icon buttons | Like and "more" on the house page and "clear search" have no label for screen readers. | `post_page.dart:258,271`, `discover_page.dart:151` |

### P1 — core UX and navigation

| # | Where | What happens |
| --- | --- | --- |
| 9 | My houses tab | Two products in one screen. A warm header ("Мои дома") sits on a cool grey drafting page with a second title ("Жобаларым"), different cards, buttons and fonts. The user's own designs — the reason to open the tab — come after a marketing hero and are pushed below the fold; with no designs, a full-screen example card comes first. |
| 10 | My houses tab, Russian | Every string of the design list is Kazakh when the app is in Russian ("Жаңа жоба", "Үлгіден бастау"). The design tool was written in Chinese and Kazakh only (1,103 two-language strings); the list is the first thing a Russian speaker sees there. |
| 11 | Project actions | Continue, publish, find builders, export, back up and delete are all behind one "…" menu. The two actions the product exists for (publish, find builders) are invisible. Flagged in the 2026-11-04 review, not done. |
| 12 | Demand cards and demand page | A demand without a drawing gets a 96–150 px gradient block with a faint icon. It carries no information and pushes trade, place, budget and start date down. Flagged as P0 in the 2026-11-04 review, not done. |
| 13 | Demo notice | Two lines of grey text above every tab, permanently. It costs 40 px of every screen and reads as a warning. |
| 14 | Me tab | A flat list mixing account, published houses, pro sign-up, settings and destructive actions. A fixed 300 px row for "my houses" leaves a large blank gap under the card. Sign out and delete account are underlined links. |
| 15 | Wide screens | The phone bottom bar stretches across a 1280 px window; four icons sit 300 px apart. |
| 16 | Design tool header on phones | Language and theme switches live in a sideways-scrolling row and are cut at the edge ("Ру"). They duplicate Me → Settings. |
| 17 | Discover, houses | Sort ("Новые ⌄") is plain text beside pill filters, so it does not look tappable. Two different search fields exist (houses vs. work/pros). |

### P2 — visual consistency

| # | What |
| --- | --- |
| 18 | No shared scale. 12 font sizes, 8 corner radii and free-hand paddings (7, 10, 14, 18, 22…) are written inline across 60 files. |
| 19 | Text buttons are underlined everywhere — a web convention; on iOS and Android it reads as a hyperlink, not a button. |
| 20 | Touch targets: filter pills are 35 px tall, opinion chips 30 px. Apple and Material both ask for 44–48 px. |
| 21 | Hardcoded colours: 45 `Color(0x…)` and 12 `Colors.white` in platform pages, several of which are the night-theme bugs above. Placeholder covers use day colours at night. |
| 22 | Loading is a centred spinner on every list; the feed jumps when content arrives. |
| 23 | Demo content is Chinese in every language (titles, pro names "Болат · 瓦工", places "Есик · 伊塞克"), and the sign-in page's test accounts are headed "测试账号". It makes the Russian and Kazakh app look unfinished. |
| 24 | Stat labels wrap mid-word on the pro page ("Подтверждённы / х работ"). |

### P3 — polish

| # | What |
| --- | --- |
| 25 | No pull-to-refresh on lists. |
| 26 | Numbers in prices and sizes are not tabular everywhere, so columns shimmer. |
| 27 | The design tool's ten page tabs scroll sideways with no hint that more exist. |

## Design skills applied

Installed from `ihlamury/design-skills` into `.claude/skills/`: apple, airbnb, linear, stripe, notion, mobbin.

These six files are machine-extracted from each company's web page. Their shared rules are sound and are applied here; much of the per-brand detail is extraction noise and is not.

**Applied (all six agree):**

- 4 px spacing grid; spacing and radius from a fixed scale, never free-hand.
- Text contrast at least 4.5 : 1.
- 1 px hairline borders for separation.
- Tabular numerals for numeric data.
- Respect safe areas for fixed bars.
- Alert dialog before destructive or irreversible actions.
- Skeletons for loading, not spinners.
- Errors shown next to where the action happens.
- A label on every icon-only button.
- Visible focus indicator, never removed.
- Disabled = 50 % opacity.
- Interaction feedback ≤ 200 ms, entrance ease-out, animate transform and opacity only, respect reduced motion.

**Taken per reference, by product need:**

- *Airbnb* (consumer browsing): warm off-white page, raised warm surface, 11–14 px card radius with 28 px pills, text-heavy cards with a clear hierarchy. Yusal's palette already sits here; the radius scale is aligned to it.
- *Apple* (native feel): large title, grouped inset lists for settings, one accent for actions, pill radius for controls.
- *Linear / Notion* (calm, minimal): few weights, small radius on dense rows, muted secondary text, no decoration that carries no information — the basis for removing the empty demand covers and the hero block.
- *Stripe* (polish): tabular money, consistent state colours for success / warning / destructive.
- *Mobbin* (mobile patterns): bottom bar on phones, rail on wide screens; sticky single primary action; scrollable tabs when labels do not fit.

**Deliberately not applied:**

- "MUST use Inter": Yusal ships Onest and Lora because they cover Kazakh Cyrillic (ә, ғ, қ, ң, ө, ұ, ү, һ, і) and were chosen for the brand. Replacing them would be a regression.
- Brand colours (`#155BD0`, `#517BDF`, Linear's dark page) and the extracted text colours (e.g. `text-primary #808080`, which fails the same file's own 4.5 : 1 rule).
- Web-only rules: 1920 px base viewport, `h-dvh`, `size-*`, `useEffect`, `cursor: not-allowed`.
- Extraction artefacts: "input height 0px", 51–75 px marketing headlines as "primary heading", spacing scales such as "1, 2, 3, 5, 6, 9, 10, 41".

## Other tools considered

- **Playwright** (drives the installed Chrome): used for the walkthroughs, the before / after screenshots and, after the fixes, eleven end-to-end flow checks (`tool/ux/e2e.mjs`).
- **Flutter widget tests**: the existing 365 are the regression net; new tests are added for each fixed state.
- **Mobbin connector and Figma plugin** are available in this environment. Not needed for the audit; the product already has a visual direction and the problems found are consistency and flow, not a missing concept.
- **Integration tests on a device**: written in earlier rounds and stale. They were repaired after the fixes and pass on an iOS simulator.
