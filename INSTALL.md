# Installation Guide: Harness v3.2.1

## Prerequisites

- Claude Code CLI installed and working
- Git initialized in your project
- Agent Teams enabled: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

## Quick Install

```bash
# 1. Copy CLAUDE.md
cp claude/CLAUDE.md ~/.claude/CLAUDE.md

# 2. Copy rules
cp -r claude/rules/*.md ~/.claude/rules/

# 3. Copy skills (includes supporting files: templates, hook scripts)
cp -r claude/skills/harness-init ~/.claude/skills/
cp -r claude/skills/harness-continue ~/.claude/skills/

# 4. Enable Agent Teams (add to your shell profile)
echo 'export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1' >> ~/.zshrc
source ~/.zshrc
```

## What Gets Installed

| File | Location | Purpose |
|------|----------|---------|
| `CLAUDE.md` | `~/.claude/` | Core engineering standards (always loaded) |
| `engineering-standards.md` | `~/.claude/rules/` | Global engineering rules (always loaded) |
| `agent-teams-protocol.md` | `~/.claude/rules/` | Agent Teams rules (loads only in harness projects) |
| `non-harness-workflow.md` | `~/.claude/rules/` | Planning workflow (loads only in non-harness projects) |
| `harness-init/SKILL.md` | `~/.claude/skills/` | `/harness-init` skill |
| `harness-init/init.sh.template` | `~/.claude/skills/` | Build/test script template |
| `harness-init/verify-task-quality.sh.template` | `~/.claude/skills/` | TaskCompleted hook template |
| `harness-init/check-remaining-tasks.sh.template` | `~/.claude/skills/` | TeammateIdle hook template |
| `harness-continue/SKILL.md` | `~/.claude/skills/` | `/harness-continue` skill |
| `harness-continue/team-spawn-prompts.md` | `~/.claude/skills/` | Spawn templates (model + plan approval) |

## Upgrading from v3.1

```bash
# Overwrite global files
cp claude/CLAUDE.md ~/.claude/CLAUDE.md
cp -r claude/rules/*.md ~/.claude/rules/
cp -r claude/skills/harness-init ~/.claude/skills/
cp -r claude/skills/harness-continue ~/.claude/skills/

# In each existing harness project, migrate:
cd ~/Projects/MyApp

# 1. Migrate decisions.md to context_summary.md
#    (or re-run /harness-init to generate fresh)
if [ -f .harness/decisions.md ]; then
    # Create context_summary.md with decisions.md content merged in
    cat > .harness/context_summary.md << 'EOF'
# Context Summary

## Active Context
- Currently working on: (migrated from v3.1, update at next session start)
- Next up: (check features.json)

## Cross-Cutting Concerns
- (review decisions.md below and extract cross-cutting items here)

EOF
    # Append old decisions content under a Domain section
    echo "## Migrated Decisions" >> .harness/context_summary.md
    echo "" >> .harness/context_summary.md
    cat .harness/decisions.md >> .harness/context_summary.md
    echo "" >> .harness/context_summary.md
    echo "---" >> .harness/context_summary.md
    echo "(Clean up this file at next session start: move items to proper sections)" >> .harness/context_summary.md
    rm .harness/decisions.md
fi

# 2. Add new fields to features.json
#    Run this Python snippet to add scope, depends_on, assigned_to to each feature:
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
data['version'] = '3.2'
with open('.harness/harness.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('harness.json version updated')
"

# 4. Update quality gate hooks
cp ~/.claude/skills/harness-init/verify-task-quality.sh.template .claude/hooks/verify-task-quality.sh
cp ~/.claude/skills/harness-init/check-remaining-tasks.sh.template .claude/hooks/check-remaining-tasks.sh
chmod +x .claude/hooks/*.sh

# 5. Verify hooks execute correctly
echo '{}' | bash .claude/hooks/verify-task-quality.sh
echo "verify-task-quality exit code: $?"

echo '{}' | bash .claude/hooks/check-remaining-tasks.sh
echo "check-remaining-tasks exit code: $?"

# 6. Update project CLAUDE.md references
#    Replace "decisions.md" with "context_summary.md" in your project's CLAUDE.md
sed -i '' 's/decisions.md/context_summary.md/g' CLAUDE.md 2>/dev/null || \
sed -i 's/decisions.md/context_summary.md/g' CLAUDE.md

# 7. Commit
git add .harness/ .claude/ CLAUDE.md
git commit -m "chore: upgrade harness to v3.2.1"
```

## Upgrading from v2.1

```bash
# Remove old files
rm -rf ~/.claude/harness/ ~/.claude/skills/context-graph/
rm -rf ~/.claude/commands/project-harness-init.md
rm -rf ~/.claude/commands/project-harness-continue.md
rm -rf ~/.claude/templates/

# Install v3.2 following Quick Install above

# In each project:
rm -rf .context/
# Keep .harness/ — features.json carries forward (will get new fields via migration)
# Run the v3.1 migration steps above to add new schema fields
```

## Per-Project Setup

```bash
cd ~/Projects/MyApp
claude
/harness-init
```

The initializer will:
1. Detect your tech stack
2. Capture git identity
3. Create `.harness/` scaffolding (with extended feature schema)
4. Install post-edit build hooks (`.claude/settings.json`)
5. Install quality gate hooks (`TaskCompleted`, `TeammateIdle`)
6. Verify hooks execute correctly
7. Propose initial features (with scope and dependencies)
8. Commit

## Continuing Work

```bash
cd ~/Projects/MyApp
claude
/harness-continue
```

## Verifying Installation

```bash
# Global files
ls ~/.claude/CLAUDE.md
# CLAUDE.md

ls ~/.claude/rules/
# engineering-standards.md, agent-teams-protocol.md, non-harness-workflow.md

ls ~/.claude/skills/harness-init/
# SKILL.md, init.sh.template, verify-task-quality.sh.template, check-remaining-tasks.sh.template

ls ~/.claude/skills/harness-continue/
# SKILL.md, team-spawn-prompts.md

echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
# 1

# Per-project hooks (after /harness-init)
echo '{}' | bash .claude/hooks/verify-task-quality.sh && echo "TaskCompleted hook: OK"
echo '{}' | bash .claude/hooks/check-remaining-tasks.sh && echo "TeammateIdle hook: OK"
```
