# Frontend clone — complete plan (Phase 17)

**Source of truth:** `c:/Users/test/Downloads/chat-tool-handoff/chat-tool/project/`
**Target:** `c:/Users/test/Downloads/qwriter/copyai_remote/templates/` + `static/app.css`
**Decisions locked:**
- Cowork & Code → UI-only mock surfaces (mock data, 2 new route handlers)
- Existing extras (Billing, Settings, Sources, Documents, Templates, Onboarding) → repaint in new palette
- No DB / model / migration changes; existing `agents.yaml` + `experts.ts` data layer stays
- No Anthropic in the model dropdown
- "OllaSuper" stays in titles (not "Workbench")

---

## Phase 17.1 — Design tokens & fonts (foundation)

The current `static/app.css` is 456 lines of Linear-style tokens — it gets a near-complete rewrite.

1. **Replace `<link>` to fonts in [base.html.tera](copyai_remote/templates/layouts/base.html.tera)** — swap Lato + Geist Mono for Newsreader (opsz 6..72, wght 400/500/600), Hanken Grotesk (400/500/600/700), JetBrains Mono (400/500/600).
2. **Rewrite `:root` in `static/app.css`** — port every token from [styles.css:6-61](chat-tool-handoff/chat-tool/project/app/styles.css#L6-L61): paper/paper-2/surface/surface-sunk, ink/ink-2/muted/faint, line/line-2/line-strong, clay/clay-deep/clay-soft/clay-tint, the 5 category accents (blue/amber/green/purple/rose) + their `-soft` variants, live green, three font families, four radii, four shadows, ease tokens.
3. **Add the keyframes** — `fadeUp`, `popIn`, `overlayIn`, `shimmer`, `dotPulse`, `blink` + the `prefers-reduced-motion` guard.
4. **Add the global utility classes** — `.mono`, `.serif`, `.uppercase-label` (the JetBrains 11px / .14em / uppercase / faint label that brands every section).
5. **Port hover/interaction utility selectors** — `.nav-item:hover`, `.icon-btn-sm`, `.agent-row:hover`, `.recent-row:hover`, `.expert-chip:hover`, `.composer-shell:focus-within` (clay 4px ring), `.generate-btn`, `.composer-tool`, `.agent-card:hover`, `.file-row`, `.follow-row`, `.msg-act-btn`, `.assistant-turn:hover .msg-actions`, `.hover-line`, `.dash-new-agent`, `.tk-tag/.tk-str/.tk-key` (code colors), `.live-dot` (pulsing).
6. **Custom scrollbar** — 10px thumb on `line-2`.
7. **Delete the old Linear `--accent: #0066ff`-based block** — keep nothing that fights the new palette.

## Phase 17.2 — Primitives as Tera macros + Stimulus

The new design leans heavily on a small set of reusable pieces. Put them in a new `partials/primitives.html.tera` macro file so every page imports the same components.

8. **Icon macro `m::icon(name, size, stroke)`** — port all 35 SVG paths from [components.jsx:10-50](chat-tool-handoff/chat-tool/project/app/components.jsx#L10-L50). One macro that emits stroke-only SVG with `stroke-linecap: round`.
9. **Avatar macro `m::avatar(initials, size, color, glyph?)`** — 30% radius, inset highlight shadow.
10. **GlyphTile macro `m::glyph_tile(glyph, color, size, soft)`** — 28% radius, soft variant uses `colorSoft(color)`, hard variant uses `var(--surface)` + `1px line`.
11. **ExpertChip macro `m::expert_chip(expert, active)`** — 99px radius pill with 7px color dot, ink/inverse when active.
12. **Pill macro `m::pill(text, tone)`** — uppercase mono 10.5px, tones: neutral / clay / live.
13. **Kbd macro `m::kbd(text)`** — Linear-ish keycap with `1px 0 var(--line)` bottom shadow.
14. **ModeSwitch macro `m::mode_switch(current)`** — segmented Chat/Cowork/Code with link routing (`/chat`, `/cowork`, `/code`) — replaces the React-state version since we're server-rendering.

## Phase 17.3 — Shell (sidebar + topbar + right rail)

15. **Rewrite [partials/sidebar.html.tera](copyai_remote/templates/partials/sidebar.html.tera)** — 252px paper-2 column with:
    - workspace header (avatar gradient `linear-gradient(135deg,#2C66E0,#7150D4)` + `{first}` + chev)
    - New chat button (ink, full width)
    - Search button (ghost, opens ⌘K palette → reuses existing `palette_controller.js`)
    - Primary nav: Home / Agents / Sources (badge counts)
    - "Your agents" section header + plus-button → New Agent modal
    - Scrollable agent list (port from `AGENTS` data — pulls from existing `agents.yaml` via current expert/agent loader)
    - Footer: Settings / Help & guides
16. **Rewrite [partials/topbar.html.tera](copyai_remote/templates/partials/topbar.html.tera)** — 58px paper bar:
    - sidebar-collapse toggle (icon-btn-sm)
    - Breadcrumb `{workspace} › {crumb}`
    - **Centered** ModeSwitch (only when view ∈ chat/cowork/code)
    - Right: Experts pill (opens picker), credit meter (70px bar + `{pct}% credits` mono), avatar
    - Reuse current [partials/credits_chip.html.tera](copyai_remote/templates/partials/credits_chip.html.tera) data binding (the Tera 1.x parse-error fix from Phase 16.5 stays)
17. **Rewrite [partials/chat_right_rail.html.tera](copyai_remote/templates/partials/chat_right_rail.html.tera)** — context rail shown in Chat surface only: "This conversation" + agent badge, "Sources in context" + Add source button, "Turn into" actions (Cowork doc / Code changes / saved Agent).
18. **Rewrite [layouts/app_shell.html.tera](copyai_remote/templates/layouts/app_shell.html.tera)** — `display:flex; height:100vh` with sidebar + main + (chat-only) right rail.
19. **Add sidebar-collapse state** — persist to `localStorage` key `qw.sidebarCollapsed`. Stimulus controller `sidebar_controller.js` (new, tiny — toggles a class on `.qw-app`).

## Phase 17.4 — Home (Dashboard)

20. **Rewrite [pages/dashboard.html.tera](copyai_remote/templates/pages/dashboard.html.tera)** — 1180px max-width 2-col grid (1fr 320px):
    - Greeting: uppercase-label "Good afternoon · {weekday}" + serif 40px "Ready when you are, {first}." + 17px muted intro paragraph (with strong Expert/Agent inline)
    - Composer (large mode, clay focus ring) — new partial `partials/composer.html.tera`
    - "Start with an Expert" section — popular chips + "Browse all" dashed chip → opens picker. Reuse current 80-expert data layer.
    - "Recent work" list — port from `RECENT_WORK`, link each row to open Agent modal
    - Right rail: CreditMeter card + Agents card (top 4 + "Build a new Agent" dashed CTA) + Sources card (top 3)
21. **Compose `partials/composer.html.tera`** — single source-of-truth composer used by Home + Chat:
    - composer-shell wrapper (clay focus ring on focus-within)
    - Optional expert chip slot (with X to clear)
    - Auto-grow textarea (`composer_controller.js` already handles this — extend to honor 220px max on `large` variant)
    - Bottom row: Attach (dashed tool button) + ModelDropdown + Generate (ink → clay on hover)
22. **Update [composer_controller.js](copyai_remote/web/src/controllers/composer_controller.js)** — auto-grow + ⌘↵ submit; clay focus ring is pure CSS.
23. **Add `model_dropdown_controller.js`** — bottom-anchored popover, click-outside-closes, selection state. Pulls allowed-model list from `data-models` attr (Gemini Flash, Gemini Pro, GPT Mini, Tongyi — **no Claude**).

## Phase 17.5 — Chat surface + streams

24. **Rewrite [pages/chat.html.tera](copyai_remote/templates/pages/chat.html.tera)** — 760px conversation column + 290px context rail. Day divider (`uppercase-label` between hairlines). Bottom composer with gradient-to-paper fade-out background.
25. **Rewrite user-message bubble** — 76% max-width, paper-2 background, `border-radius: 18px 18px 6px 18px`, 13px/17px font.
26. **Rewrite assistant message turn** — left GlyphTile + name + "expert" pill + rich markdown body + citations row + MsgActions (hover-reveal Copy/Retry/Save) + follow-up suggestions (rotated arrow icons, border-bottom rows).
27. **Streaming caret** — 9×17 clay block, `blink 1s step-start infinite`. Replaces the current Phase-15 caret.
28. **Citations** — pill row: numbered mono square + globe icon + source name. Pull citation data from existing chat response payload (don't change the server contract — just re-render).
29. **Follow-up suggestions** — three rows, border-bottom hairlines, 45°-rotated arrowUp icon on right. Wire to existing prompt-suggest mechanism.
30. **Rewrite [streams/chat_append.html.tera](copyai_remote/templates/streams/chat_append.html.tera)** — match new bubble markup. Keep `data-testid="chat-ai-msg"` + `data-msg-pid` + `data-msg-md` (Phase 16.2 chat regression fix preserved).
31. **Rewrite [streams/chat_regenerate.html.tera](copyai_remote/templates/streams/chat_regenerate.html.tera)** — same.
32. **Rewrite [streams/chat_pending.html.tera](copyai_remote/templates/streams/chat_pending.html.tera)** — three pulsing clay dots (`Typing` component).
33. **Update `chat_poll_controller.js`** — no behavior change; ensure 180s timeout, test-ids still emitted. Repaint only.

## Phase 17.6 — Cowork (NEW surface, UI-only)

34. **Add route handler `GET /cowork`** — render a new `pages/cowork.html.tera` with seed `DOC_TITLE` + `DOC_SECTIONS` + `COWORK_THREAD` from [cowork.jsx:6-16](chat-tool-handoff/chat-tool/project/app/cowork.jsx#L6-L16). Single existing controller file, single new function — no model/DB touch.
35. **Build pages/cowork.html.tera** — 360px agent thread (left) + paper-2 doc canvas (right):
    - Thread header with Brief Writer GlyphTile + live-dot "co-writing with you"
    - Scrollable thread (user bubbles + agent paragraphs with strong-bold support)
    - Bottom composer (mini, surface-sunk shell, arrowUp send button)
    - Toolbar over canvas: doc icon + title + clay "draft v3" pill | History / Preview tool buttons + ink Share button
    - Doc sheet: 720px white card, 56/64 padding, uppercase eyebrow + serif H1 + agent ownership line, three sections, an **inline AI suggestion card** (clay-tint background, "Accept" → ink button, "Dismiss" → ghost), highlighted green-soft `<mark>` after accept
    - Bottom "Ask the agent to draft the next section" follow-row
36. **Add `cowork_controller.js`** — local-only Stimulus: Accept/Dismiss the suggestion, append the highlighted sentence, push agent message into thread. Pure DOM, no fetch.

## Phase 17.7 — Code (NEW surface, UI-only)

37. **Add route handler `GET /code`** — render `pages/code.html.tera` with seed `FILE_TREE` + `DIFF` from [code.jsx:7-32](chat-tool-handoff/chat-tool/project/app/code.jsx#L7-L32).
38. **Build pages/code.html.tera** — 232px file tree (left) + diff editor + 300px reviewer rail:
    - File tree with collapse/expand chevrons + amber folder icons + active file with clay left-border + M badge
    - Bottom "fix/seo-courses-page" branch chip
    - Tab bar: `courses.html` tab with `M` mono badge + Diff/Editor segmented control
    - Diff body: 50px right-aligned line numbers + 20px mark column (`+`/`−`/space) + content (green-soft / clay-soft / transparent backgrounds; line-through on delete)
    - Tiny in-template syntax highlighter — port the regex stash from [code.jsx:60-71](chat-tool-handoff/chat-tool/project/app/code.jsx#L60-L71) into a Tera filter or pre-bake the highlighted HTML server-side
    - **Inline reviewer comment card** after line 50: blue GlyphTile + Code Reviewer name + live "approves" pill + body + Apply fix / Reply buttons
    - Action bar: +8 additions / −1 deletion + Discard / Commit & open PR (ink)
    - Reviewer rail: agent GlyphTile + "Ready to merge" green card + Review checklist (5 items, green check / amber plus, hairline rows)
39. **Add `code_controller.js`** — Stimulus for tab switch (Diff ↔ Editor) + folder collapse + Apply fix button (no-op visual).

## Phase 17.8 — Agents gallery + Sources

40. **Build/rewrite `pages/agents.html.tera`** — 1080px max-width, 32px serif title "Your agents" + muted subtitle + ink "New agent" button + 300px-min auto-fill card grid. Each card: GlyphTile + "Active" live-dot + name (16px bold) + 40px-min desc + footer with skill dots + run-count mono. Card hover: line-strong border + sh-md + -1px translate.
41. **Build/rewrite `pages/sources.html.tera`** — repaint of current sources page in new palette. Reuse existing source-picker controller. Add Add-source dashed chip primitive.

## Phase 17.9 — Modals (Expert Picker, Agent Detail, New Agent Builder)

42. **Build modal infra** — `Overlay` partial macro: fixed inset, `rgba(27,24,19,.34)` + `backdrop-filter: blur(3px)`, ESC + outside-click closes. Two align modes: top (picker) / center (others).
43. **Build `partials/expert_picker.html.tera`** — 680px modal:
    - Search row with magnifying glass + autofocus input + ESC chip
    - Horizontal category chip row (All + 8 cats, scrollable, active = ink)
    - 2-col results grid: 34px color-soft tile + dot + name + popular pill + desc
    - Footer: `{n} of 80 experts` + ↑↓ navigate / ↵ route prompt chips
    - Reuse existing palette_controller to bind ⌘K — but swap its rendering for this modal markup
44. **Build `partials/agent_detail.html.tera`** — 560px modal:
    - Colored header band (`colorSoft(a.color)`), 56px ink-glyph tile, name + Active live-dot + cat · runs mono
    - Body: 15px desc + Skills & experts chip row + 3-stat grid (Runs / Avg time / Last used) + Open in {kind} (ink) + settings icon-btn
    - "Open in Chat" links to `/chat?agent={id}` — uses existing chat route; no new backend
45. **Build `partials/new_agent_modal.html.tera`** — 600px tall scrollable modal:
    - Sticky header: clay-tint bolt tile + "Build a new Agent" + close
    - Name input (surface-sunk background)
    - Skills picker — ink-inverted chips when selected, check icon when on
    - Default model 2-col grid — clay border + clay-tint background when on, radio dot
    - Sources checklist — clay-tint when on, ink check in clay box
    - Sticky footer: Cancel + Create agent (ink when name present, line-2 when empty)
46. **Update `palette_controller.js`** — render the new expert-picker markup, keep ⌘K binding + categories, wire result rows to the existing chat-route mechanism.

## Phase 17.10 — Repaint existing extras

These keep their behavior — only the visual layer changes. One PR per file, no logic touches.

47. **Repaint `pages/billing.html.tera`** — Dodo Payments plans + credit meter + invoice history in new paper/clay palette. Plan cards become the same 16px-radius surface cards used in Agents grid.
48. **Repaint `pages/settings.html.tera`** — tabs nav + form rows in new palette. The Phase 12 C+ shell stays, just re-skinned.
49. **Repaint `pages/documents.html.tera` + `pages/editor_compare.html.tera`** — Trix editor toolbar re-styled with new buttons; canvas matches Cowork doc-sheet spec.
50. **Repaint `pages/templates.html.tera`** — template gallery → same card style as Agents.
51. **Repaint `pages/onboarding.html.tera` + `pages/onboarding_progress.html.tera`** — serif H1, paper background, clay progress.
52. **Repaint `pages/catalog.html.tera` + `pages/project.html.tera`** — paint pass only.
53. **Repaint `pages/auth.html.tera`** — unauthenticated screen gets the warm paper background + Newsreader display.
54. **Update `static/vendor/trix.css`** — restyle Trix toolbar in new palette.

## Phase 17.11 — Stimulus + JS adjustments

55. **`composer_controller.js`** — extend auto-grow max to 220px in large mode, ⌘↵ submit.
56. **`dropdown_controller.js`** — pop-in animation + bottom-anchor variant.
57. **`palette_controller.js`** — new markup for expert picker.
58. **`source_picker_controller.js`** — match new tool-button style.
59. **`copy_controller.js`** — check→Copied state in `MsgActions`.
60. **`dialog_controller.js`** — reuse for agent/new-agent modals.
61. **New `sidebar_controller.js`** (toggle), `mode_switch_controller.js` (route), `cowork_controller.js` (suggest accept), `code_controller.js` (tabs).

## Phase 17.12 — QA + verification

62. **Snapshot every surface** at 1440×900 — Home, Chat (empty + with one round-trip), Cowork (suggestion open + accepted), Code (diff + reviewer), Agents, Sources, Billing, Settings, all 3 modals (Expert Picker / Agent Detail / New Agent), sidebar collapsed state, hover states on Composer / agent-card / recent-row.
63. **Diff each snapshot against the reference** — Workbench.html rendered side-by-side. Anything off by more than a hairline gets a fix-up commit before sign-off.
64. **Modal interaction matrix**:
    - ESC closes
    - Outside-click closes
    - ⌘K opens Expert Picker from any surface
    - Picker categories filter
    - Picker search filters
    - Agent modal "Open in Chat" lands on /chat with right agent
    - New Agent Create button gated by name presence
65. **Keyboard shortcuts**:
    - ⌘K = picker
    - ⌘\ = sidebar toggle
    - ⌘↵ = composer submit
    - ESC = close modal
66. **A11y check** — `:focus-visible` clay ring lands on every interactive element. `aria-label` on all icon-only buttons. `prefers-reduced-motion` honored.
67. **Cross-browser** — Chrome + Edge + Firefox latest. Backdrop-filter falls back gracefully.
68. **Persona test regression** — re-run a Smoke pass on the 86-persona suite to confirm the chat repaint didn't break stream parsing.
69. **Memory updates** — replace `feedback_linear_aesthetic.md` with a new `feedback_warm_editorial.md` once shipped + sign-off. Add a `reference_design_tokens.md` listing the warm-paper palette so future sessions don't drift back to blue/Lato.

---

## File-by-file change manifest

| File | Action |
|---|---|
| `static/app.css` | rewrite tokens, keep some utility layer rules |
| `templates/layouts/base.html.tera` | swap font links, keep palette wiring |
| `templates/layouts/app_shell.html.tera` | repaint shell flex/grid |
| `templates/layouts/chat_shell.html.tera` | repaint, add ModeSwitch slot |
| `templates/partials/sidebar.html.tera` | rewrite |
| `templates/partials/topbar.html.tera` | rewrite |
| `templates/partials/chat_right_rail.html.tera` | rewrite |
| `templates/partials/credits_chip.html.tera` | repaint (parse-error fix stays) |
| `templates/partials/macros.html.tera` | add icon/avatar/glyph_tile/expert_chip/pill/kbd/mode_switch macros |
| `templates/partials/primitives.html.tera` | NEW |
| `templates/partials/composer.html.tera` | NEW |
| `templates/partials/expert_picker.html.tera` | NEW (replaces palette overlay) |
| `templates/partials/agent_detail.html.tera` | NEW |
| `templates/partials/new_agent_modal.html.tera` | NEW |
| `templates/pages/dashboard.html.tera` | rewrite |
| `templates/pages/chat.html.tera` | rewrite |
| `templates/pages/cowork.html.tera` | NEW |
| `templates/pages/code.html.tera` | NEW |
| `templates/pages/agents.html.tera` | rewrite (new file) |
| `templates/pages/sources.html.tera` | repaint |
| `templates/pages/billing.html.tera` | repaint |
| `templates/pages/settings.html.tera` | repaint |
| `templates/pages/documents.html.tera` | repaint |
| `templates/pages/editor_compare.html.tera` | repaint |
| `templates/pages/templates.html.tera` | repaint |
| `templates/pages/onboarding.html.tera` | repaint |
| `templates/pages/onboarding_progress.html.tera` | repaint |
| `templates/pages/catalog.html.tera` | repaint |
| `templates/pages/project.html.tera` | repaint |
| `templates/pages/auth.html.tera` | repaint |
| `templates/streams/chat_append.html.tera` | rewrite bubble, keep test-ids |
| `templates/streams/chat_regenerate.html.tera` | rewrite bubble, keep test-ids |
| `templates/streams/chat_pending.html.tera` | rewrite (clay typing dots) |
| `static/vendor/trix.css` | repaint toolbar |
| `web/src/controllers/composer_controller.js` | extend auto-grow + ⌘↵ |
| `web/src/controllers/model_dropdown_controller.js` | NEW |
| `web/src/controllers/sidebar_controller.js` | NEW (collapse toggle + persist) |
| `web/src/controllers/mode_switch_controller.js` | NEW (route Chat/Cowork/Code) |
| `web/src/controllers/cowork_controller.js` | NEW (suggest accept/dismiss) |
| `web/src/controllers/code_controller.js` | NEW (tab + folder + apply fix) |
| `web/src/controllers/palette_controller.js` | rewrite render path |
| `web/src/controllers/copy_controller.js` | tiny — Copied state |
| `web/src/controllers/dropdown_controller.js` | pop-in + bottom-anchor |
| `src/controllers/*.rs` | add `GET /cowork` + `GET /code` handlers (template render only) |

**Counted:** 12 rewrites, 14 NEW files, 11 repaints, 6 Stimulus updates, 2 small Rust route additions, 3 stream rewrites = **~48 file touches**.

---

## Execution order

1. 17.1 tokens + fonts (one commit — visible everywhere, foundation for the rest)
2. 17.2 primitives (macros) + 17.3 shell (sidebar/topbar/rail) — one commit; now every page can use them
3. 17.4 Home — first "real" surface; iteration target for the design language
4. 17.5 Chat + streams — most-used surface; protects persona tests
5. 17.9 Modals — overlay infrastructure used by Home + Chat + Agents
6. 17.6 Cowork (NEW), 17.7 Code (NEW), 17.8 Agents gallery + Sources — parallel-safe trio
7. 17.10 repaint extras — sweep, one commit per page bundle
8. 17.11 Stimulus polish — only as needed during the above
9. 17.12 QA pass — pixel diff, modal matrix, kbd shortcuts, a11y, persona regression, memory updates

Estimated total: **6–8 commits**, ~one phase each in the 17.x series.
