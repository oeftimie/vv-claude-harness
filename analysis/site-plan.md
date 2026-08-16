# Site plan

Static site under `site/`, deployed to GitHub Pages by `.github/workflows/pages.yml`.
No build step, no framework — plain HTML/CSS/ES modules, matching this repo's
"no build system" posture (`AGENTS.md`).

## Information architecture

| Page | Carries | Corresponds to |
|------|---------|----------------|
| `index.html` | Why this exists; the shift problem; files-not-memory; the two install halves; where to go next | learner-path stop 1 |
| `quickstart.html` | Prerequisites, install, `/harness-init`, first session, what got written | stop 2 |
| `lifecycle.html` | The `/harness-continue` loop step by step; the three memory files; compaction | stop 3 |
| `gates.html` | Four hooks, three tiers, the tiered task gate, the stated limits | stop 4 |
| `parallel.html` | Independence, worktrees, model tiers, the fallback, when not to | stop 5 |
| `reference.html` | Commands, feature object, statuses, test targets, completion checklist, glossary | stop 6 |

Shared: `assets/site.css`, `assets/anim.js` (single module, imported by every page),
`assets/nav` markup inlined per page (no client-side routing, no fetch — Pages serves
files, and inlined nav keeps every page independently viewable from `file://` during
development).

## Animation policy

anime.js v4.5.0, pinned ES module from jsDelivr. Rules the implementation follows:

1. **Every animation carries an idea.** If a motion would work equally well on a
   different page, it is decoration and gets cut.
2. **Reduced motion is honored globally.** `matchMedia('(prefers-reduced-motion:
   reduce)')` short-circuits `anim.js` into a no-op that sets final states directly, so
   content is never hidden behind an animation that will not run.
3. **Content is visible without JS.** Elements animate *from* a CSS-declared visible
   state where possible; where an entrance requires starting hidden, JS sets the hidden
   state itself (`utils.set`) so a JS failure leaves the page readable rather than blank.
4. **Scroll triggers use `onScroll` as `autoplay`**, the documented v4 form —
   `animate(el, { …, autoplay: onScroll({ enter: 'bottom-=80', repeat: false }) })`.
   `repeat` defaults to `true` in `ScrollObserver`, so playing once is an explicit
   `repeat: false` — verified against the bundle, not assumed.

## Animation ↔ idea map

| # | Where | Motion | The idea it carries |
|---|-------|--------|---------------------|
| A1 | index hero | Timeline: title words stagger up, subtitle fades, three stat chips pop | Entry; establishes the motion vocabulary |
| A2 | index, shift problem | Two side-by-side session columns. Left ("no harness"): three memory blocks fill during session 1, then **drain to empty** at the session boundary, and session 2 starts blank. Right ("harness"): blocks fill, a file icon absorbs them at the boundary, session 2 starts pre-filled | The single most important claim on the site — state does not survive a session boundary unless something writes it down |
| A3 | index, install split | Two trees stagger in: plugin cache (global) and project root (per-project), with a connecting line drawn last | The two halves are different things in different places |
| A4 | lifecycle | An SVG loop path; a marker travels it via `svg.createMotionPath`, pausing at each of the eight steps while that step's card highlights. Scroll-synced so the reader drives it | The session loop is a cycle, not a checklist, and each session re-enters it |
| A5 | lifecycle, compaction | A context bar fills to red; `/compact` collapses it; the SessionStart hook re-injects three labeled chips (features, Active Context, handoff) | Compaction is a planned event with a recovery path, not a crash |
| A6 | gates | A "commit" token slides toward `main`; the gate bar flashes and the token bounces back; then tests go green and the token passes through | Mechanical enforcement blocks the action rather than advising against it |
| A7 | gates, tiers | Four reliability bars grow to different widths, labeled mechanical / prompted / structural / instructional | Reliability is a spectrum and the tier a rule lives in is a design decision |
| A8 | gates, task gate | Three lanes light in sequence — `smoke_test` ✓, `focused_test` ✓, full suite greyed with "runs at commit / session end" | Why the per-task gate is not the full suite |
| A9 | parallel | A lead node fans to three worktree nodes (`stagger` from center), each runs an implementer→reviewer pair, then branches converge back into the lead | Worktree isolation and the implement→review pipeline |
| A10 | parallel, independence | Two feature cards; overlapping `scope` rectangles collide and turn red, then separate and turn green | The mechanical definition of "independent" |
| A11 | quickstart | Terminal blocks type out line by line; the resulting file tree staggers in beneath | Cause and effect: this command produced these files |
| A12 | all pages | A top scroll-progress bar driven by `onScroll` in `sync` mode | Orientation on long pages; also demonstrates scroll-synced (not just triggered) animation |

## Verification

Site is served locally and loaded in a real browser before shipping: every page checked
for console errors, animations confirmed to run, and scroll triggers confirmed to fire.
A page that renders is not evidence that its module loaded.
