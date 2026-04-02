# Installation Guide: Harness v3.4.0

## Prerequisites

- Claude Code CLI installed and working
- Git initialized in your project
- `jq` installed (used by hook scripts): `brew install jq` on macOS
- `python3` installed (used by hook scripts and the installer)
- Agent Teams enabled: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (the installer handles this)

## Quick Install

```bash
./install
```

The installer will:
1. Check prerequisites (git, jq, python3, Claude Code CLI)
2. Ask for your name (defaults to `git config user.name`)
3. Back up any existing `~/.claude/` harness files to `~/.claude/backup-<timestamp>/`
4. Copy all files to `~/.claude/`, personalizing CLAUDE.md with your name
5. Remove deprecated files from older versions
6. Add the Agent Teams environment variable to your shell profile
7. Verify the installation

### Options

```bash
./install --name "Jane"      # Non-interactive (skip name prompt)
./install --dry-run           # Preview what would happen without doing it
./install --no-backup         # Skip backup of existing files
```

## Upgrading

The installer detects your installed version and handles upgrades automatically:

```bash
./install
```

This upgrades global files (`~/.claude/CLAUDE.md`, rules, skills) and cleans up deprecated files.

### Upgrading per-project harness files

After upgrading global files, upgrade each harness project:

```bash
./install --upgrade-only ~/Projects/MyApp
```

This updates:
- `harness.json` version
- Quality gate hook scripts
- PostCompact hook in `.claude/settings.json`
- For v3.1 projects: migrates `decisions.md` to `context_summary.md` and adds new `features.json` fields

## What Gets Installed

| File | Location | Purpose |
|------|----------|---------|
| `CLAUDE.md` | `~/.claude/` | Core engineering standards (always loaded) |
| `agent-teams-protocol.md` | `~/.claude/rules/` | Agent Teams rules (loads when Claude reads .harness/ files) |
| `harness-init/SKILL.md` | `~/.claude/skills/` | `/harness-init` skill |
| `harness-init/init.sh.template` | `~/.claude/skills/` | Build/test script template |
| `harness-init/verify-task-quality.sh.template` | `~/.claude/skills/` | TaskCompleted hook template |
| `harness-init/check-remaining-tasks.sh.template` | `~/.claude/skills/` | TeammateIdle hook template |
| `harness-init/enforce-scope.sh.template` | `~/.claude/skills/` | PreToolUse scope enforcement hook template |
| `harness-init/verify-git-identity.sh.template` | `~/.claude/skills/` | PreToolUse git identity hook template |
| `harness-continue/SKILL.md` | `~/.claude/skills/` | `/harness-continue` skill |
| `harness-continue/team-spawn-prompts.md` | `~/.claude/skills/` | Spawn templates (model + plan approval) |

## Per-Project Setup

```bash
cd ~/Projects/MyApp
claude
/harness-init
```

The initializer will:
1. Detect your tech stack
2. Capture and confirm git identity
3. Create `.harness/` scaffolding (features.json, context_summary.md, init.sh, progress log)
4. Install async PostToolUse build hooks in `.claude/settings.json`
5. Install PreToolUse hooks (`enforce-scope.sh`, `verify-git-identity.sh`)
6. Install quality gate hooks (`TaskCompleted`, `TeammateIdle`, `PostCompact`)
7. Verify hooks execute correctly
8. Propose initial features with scope and dependencies
9. Commit

After initialization, verify per-project hooks:

```bash
echo '{}' | bash .claude/hooks/verify-task-quality.sh && echo "TaskCompleted hook: OK"
echo '{}' | bash .claude/hooks/check-remaining-tasks.sh && echo "TeammateIdle hook: OK"
```

## Continuing Work

At the start of every session on a harness project:

```bash
cd ~/Projects/MyApp
claude
/harness-continue
```

This orients to current state, verifies git identity, and picks single-session or Agent Teams mode.

## What Changed in v3.2.2

- `TodoWrite` replaced with `TaskCreate`/`TaskUpdate` (TodoWrite removed from Claude Code)
- "Delegate mode" renamed to "plan mode" (matching current Claude Code terminology)
- Worktree isolation added for mechanical scope enforcement
- PostCompact hook added for context recovery after compaction
- PostToolUse build hooks now async (non-blocking)
- Auto-memory vs context_summary.md guidance added

---

## Manual Install (Reference)

If you prefer to install manually or want to understand what the installer does:

<details>
<summary>Click to expand manual steps</summary>

### Fresh Install

```bash
# 1. Create target directories
mkdir -p ~/.claude/rules
mkdir -p ~/.claude/skills

# 2. Copy core engineering standards
cp claude/CLAUDE.md ~/.claude/CLAUDE.md
# Edit ~/.claude/CLAUDE.md: replace all {{USER_NAME}} with your name

# 3. Copy rules
cp claude/rules/agent-teams-protocol.md ~/.claude/rules/

# 4. Copy skills
cp -r claude/skills/harness-init ~/.claude/skills/
cp -r claude/skills/harness-continue ~/.claude/skills/

# 5. Enable Agent Teams
grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' ~/.zshrc || echo 'export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1' >> ~/.zshrc
source ~/.zshrc

# 6. Verify
ls ~/.claude/CLAUDE.md
ls ~/.claude/rules/agent-teams-protocol.md
ls ~/.claude/skills/harness-init/SKILL.md
ls ~/.claude/skills/harness-continue/SKILL.md
echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS  # Should output: 1
```

### Upgrading from v3.2.1

```bash
# 1. Back up existing files
cp -r ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak
cp -r ~/.claude/rules/ ~/.claude/rules.bak/
cp -r ~/.claude/skills/harness-init ~/.claude/skills/harness-init.bak
cp -r ~/.claude/skills/harness-continue ~/.claude/skills/harness-continue.bak

# 2. Overwrite global files
cp claude/CLAUDE.md ~/.claude/CLAUDE.md
# Edit ~/.claude/CLAUDE.md: replace all {{USER_NAME}} with your name
cp claude/rules/*.md ~/.claude/rules/
cp -r claude/skills/harness-init ~/.claude/skills/
cp -r claude/skills/harness-continue ~/.claude/skills/

# 3. Remove deprecated rules
rm -f ~/.claude/rules/non-harness-workflow.md
rm -f ~/.claude/rules/engineering-standards.md

# 4. In each existing harness project, run:
./install --upgrade-only /path/to/project
```

### Upgrading from v3.1

```bash
# Follow the v3.2.1 upgrade steps above, then in each project:
./install --upgrade-only /path/to/project
# This handles decisions.md migration and features.json schema updates
```

### Upgrading from v2.1

```bash
# Remove old files
rm -rf ~/.claude/harness/ ~/.claude/skills/context-graph/
rm -rf ~/.claude/commands/project-harness-init.md
rm -rf ~/.claude/commands/project-harness-continue.md
rm -rf ~/.claude/templates/

# Follow the Fresh Install steps above

# In each project:
rm -rf .context/
# Keep .harness/ — features.json carries forward
# Run: ./install --upgrade-only /path/to/project
```

</details>
