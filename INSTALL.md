# Installation Guide: Harness v3.2.2

## Prerequisites

- Claude Code CLI installed and working
- Git initialized in your project
- `jq` installed (used by hook scripts): `brew install jq` on macOS
- `python3` installed (used by hook scripts for JSON parsing in `verify-task-quality.sh` and `check-remaining-tasks.sh`)
- Agent Teams enabled: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

## Fresh Install (Step by Step)

### Step 1: Create target directories

```bash
mkdir -p ~/.claude/rules
mkdir -p ~/.claude/skills
```

### Step 2: Copy core engineering standards

```bash
cp claude/CLAUDE.md ~/.claude/CLAUDE.md
```

This is the global CLAUDE.md loaded in every Claude Code session. Review it before overwriting if you have an existing one — it defines TDD requirements, naming conventions, debugging process, and agent coordination rules.

### Step 3: Copy rules

```bash
cp claude/rules/agent-teams-protocol.md ~/.claude/rules/
```

- `agent-teams-protocol.md` — loaded when Claude reads `.harness/` files (team coordination, worktree isolation, quality gates)

### Step 4: Copy skills

```bash
cp -r claude/skills/harness-init ~/.claude/skills/
cp -r claude/skills/harness-continue ~/.claude/skills/
```

This installs two slash commands:
- `/harness-init` — sets up a new project with feature tracking, hooks, and scaffolding
- `/harness-continue` — orients at session start, picks single-session or Agent Teams mode

### Step 5: Enable Agent Teams

```bash
grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' ~/.zshrc || echo 'export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1' >> ~/.zshrc
source ~/.zshrc
```

### Step 6: Verify installation

```bash
# Global files exist
ls ~/.claude/CLAUDE.md
ls ~/.claude/rules/agent-teams-protocol.md
ls ~/.claude/skills/harness-init/SKILL.md
ls ~/.claude/skills/harness-continue/SKILL.md

# Agent Teams enabled
echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
# Should output: 1
```

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

## Upgrading from v3.2.1

```bash
# Step 1: Overwrite global files
cp claude/CLAUDE.md ~/.claude/CLAUDE.md
cp claude/rules/*.md ~/.claude/rules/
cp -r claude/skills/harness-init ~/.claude/skills/
cp -r claude/skills/harness-continue ~/.claude/skills/

# Step 2: Remove deprecated rules (content folded into CLAUDE.md)
rm -f ~/.claude/rules/non-harness-workflow.md
rm -f ~/.claude/rules/engineering-standards.md

# Step 3: In each existing harness project:
cd ~/Projects/MyApp

# Step 4: Update harness version in harness.json
python3 -c "
import json
with open('.harness/harness.json') as f:
    data = json.load(f)
data['version'] = '3.2.2'
with open('.harness/harness.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('harness.json version updated')
"

# Step 5: Update quality gate hook scripts
cp ~/.claude/skills/harness-init/verify-task-quality.sh.template .claude/hooks/verify-task-quality.sh
cp ~/.claude/skills/harness-init/check-remaining-tasks.sh.template .claude/hooks/check-remaining-tasks.sh
chmod +x .claude/hooks/*.sh

# Step 6: Add PostCompact hook to .claude/settings.json
python3 -c "
import json
with open('.claude/settings.json') as f:
    data = json.load(f)
hooks = data.setdefault('hooks', {})
if 'PostCompact' not in hooks:
    hooks['PostCompact'] = [{'hooks': [{'type': 'prompt', 'prompt': 'Context was just compacted. Immediately re-read .harness/context_summary.md and run TaskList to recover your current state before continuing work.'}]}]
    with open('.claude/settings.json', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print('PostCompact hook added to settings.json')
else:
    print('PostCompact hook already exists, skipping')
"

# Step 7: (Optional) Add "async": true to existing PostToolUse hooks in .claude/settings.json
#   Prevents build checks from blocking the agent between edits

# Step 8: Verify hooks
echo '{}' | bash .claude/hooks/verify-task-quality.sh
echo "verify-task-quality exit code: $?"

echo '{}' | bash .claude/hooks/check-remaining-tasks.sh
echo "check-remaining-tasks exit code: $?"

# Step 9: Commit
git add .harness/ .claude/
git commit -m "chore: upgrade harness to v3.2.2"
```

**What changed in v3.2.2:**
- `TodoWrite` replaced with `TaskCreate`/`TaskUpdate` (TodoWrite removed from Claude Code)
- "Delegate mode" renamed to "plan mode" (matching current Claude Code terminology)
- Worktree isolation added for mechanical scope enforcement
- PostCompact hook added for context recovery after compaction
- PostToolUse build hooks now async (non-blocking)
- Auto-memory vs context_summary.md guidance added

## Upgrading from v3.1

```bash
# Overwrite global files
cp claude/CLAUDE.md ~/.claude/CLAUDE.md
cp claude/rules/*.md ~/.claude/rules/
cp -r claude/skills/harness-init ~/.claude/skills/
cp -r claude/skills/harness-continue ~/.claude/skills/

# In each existing harness project, migrate:
cd ~/Projects/MyApp

# 1. Migrate decisions.md to context_summary.md
if [ -f .harness/decisions.md ]; then
    cat > .harness/context_summary.md << 'EOF'
# Context Summary

## Active Context
- Currently working on: (migrated from v3.1, update at next session start)
- Next up: (check features.json)

## Cross-Cutting Concerns
- (review decisions.md below and extract cross-cutting items here)

EOF
    echo "## Migrated Decisions" >> .harness/context_summary.md
    echo "" >> .harness/context_summary.md
    cat .harness/decisions.md >> .harness/context_summary.md
    echo "" >> .harness/context_summary.md
    echo "---" >> .harness/context_summary.md
    echo "(Clean up this file at next session start: move items to proper sections)" >> .harness/context_summary.md
    rm .harness/decisions.md
fi

# 2. Add new fields to features.json
python3 -c "
import json
with open('.harness/features.json') as f:
    data = json.load(f)
for feat in data.get('features', []):
    feat.setdefault('scope', [])
    feat.setdefault('depends_on', [])
    feat.setdefault('assigned_to', None)
with open('.harness/features.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('features.json migrated')
"

# 3. Update harness version
python3 -c "
import json
with open('.harness/harness.json') as f:
    data = json.load(f)
data['version'] = '3.2.2'
with open('.harness/harness.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('harness.json version updated')
"

# 4. Update quality gate hooks
cp ~/.claude/skills/harness-init/verify-task-quality.sh.template .claude/hooks/verify-task-quality.sh
cp ~/.claude/skills/harness-init/check-remaining-tasks.sh.template .claude/hooks/check-remaining-tasks.sh
chmod +x .claude/hooks/*.sh

# 5. Verify hooks
echo '{}' | bash .claude/hooks/verify-task-quality.sh
echo "verify-task-quality exit code: $?"

echo '{}' | bash .claude/hooks/check-remaining-tasks.sh
echo "check-remaining-tasks exit code: $?"

# 6. Update project CLAUDE.md references
sed -i '' 's/decisions.md/context_summary.md/g' CLAUDE.md 2>/dev/null || \
sed -i 's/decisions.md/context_summary.md/g' CLAUDE.md

# 7. Commit
git add .harness/ .claude/ CLAUDE.md
git commit -m "chore: upgrade harness to v3.2.2"
```

## Upgrading from v2.1

```bash
# Remove old files
rm -rf ~/.claude/harness/ ~/.claude/skills/context-graph/
rm -rf ~/.claude/commands/project-harness-init.md
rm -rf ~/.claude/commands/project-harness-continue.md
rm -rf ~/.claude/templates/

# Follow the Fresh Install steps above

# In each project:
rm -rf .context/
# Keep .harness/ — features.json carries forward (will get new fields via v3.1 migration)
# Run the v3.1 migration steps above to add new schema fields
```
