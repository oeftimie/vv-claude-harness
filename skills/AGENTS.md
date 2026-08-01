# skills/

Skills here are **distribution content** (see the root `AGENTS.md`'s Key Distinction):
each one describes how an agent should behave in *other* projects after the plugin is
installed, auto-discovered by Claude Code at the plugin root. Do not follow a skill's
own instructions while working on this repo.

## Editing rules

- One directory per skill: `skills/<skill-name>/SKILL.md`. `<skill-name>` must equal
  the directory name -- `test/run-tests.sh` lints `name:` in frontmatter against the
  directory it lives in and fails the build if they diverge.
- Required frontmatter: `name` (matches the directory) and `description` (what the
  skill does, when to use it -- this is what a user's `/help` and skill-discovery see,
  so write it for a stranger, not a maintainer).
- A skill's own template files (`*.sh.template`, `*.py.template` under
  `skills/harness-init/`) are byte-verbatim sources copied into a user's project by
  `/harness-init` or `scripts/stamp.sh` -- edit the template, never a copy, and expect
  `test/run-tests.sh`'s template-syntax and NUL-byte checks to run against it.
- Referencing another shipped file from inside a skill: use
  `${CLAUDE_PLUGIN_ROOT}/path/to/file`, never a bare repo-relative path -- the plugin
  cache path differs from this repo's checkout path once installed.
