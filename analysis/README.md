# Analysis

Working notes behind `site/` — the teaching site for engineers new to the VV Claude Code
Harness. These files exist so the site's claims have a traceable source, and so a future
session can regenerate or correct the site without re-deriving the model from scratch.

| File | What it holds |
|------|---------------|
| [harness-model.md](./harness-model.md) | The conceptual model of the harness, each claim cited to the file it came from |
| [learner-path.md](./learner-path.md) | What a new engineer needs to learn, in order, and the misconceptions to pre-empt |
| [site-plan.md](./site-plan.md) | Information architecture, and which animation carries which idea |

## Method

Every factual claim on the site was read out of this repository, not recalled. Sources
used, in order of authority:

1. `schemas/feature.schema.json` — canonical for the `features.json` contract
2. `rules/*.md` — canonical for TDD, code quality, parallel work, completion
3. `skills/*/SKILL.md` — canonical for what each slash command actually does
4. `README.md`, `INSTALL.md`, `AGENTS.md` — canonical for install, architecture, posture
5. `skills/harness-init/init.sh.template` — canonical for the test targets

Where the repo states a limitation, the site states it too. A teaching site that only
shows the happy path teaches an engineer to be surprised later.

## Animation library

anime.js **v4.5.0**, MIT, loaded as a pinned ES module from jsDelivr:

```
https://cdn.jsdelivr.net/npm/animejs@4.5.0/dist/bundles/anime.esm.min.js
```

The version and the named exports used (`animate`, `createTimeline`, `stagger`,
`onScroll`, `svg`, `utils`) were verified against the published bundle's own export
list rather than assumed from memory. `onScroll()` is passed as the `autoplay` value of
`animate()` / `createTimeline()`, which is the documented v4 form.
