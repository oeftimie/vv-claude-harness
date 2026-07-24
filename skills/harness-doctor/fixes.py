"""Mechanical --fix actions for doctor.py, mirroring INSTALL.md's "Upgrading an
existing harness project" steps. Each fixer applies exactly one of those steps
and returns True on success, False if it could not act (e.g. missing plugin_root)."""
import json
import os
import shutil


def apply_fix(project_dir, plugin_root, fix_id):
    fixer = _FIXERS.get(fix_id)
    if fixer is None:
        return False
    return fixer(project_dir, plugin_root)


def _remove_postcompact(project_dir, plugin_root):
    path = os.path.join(project_dir, ".claude", "settings.json")
    settings = _load_json(path)
    if settings is None or "PostCompact" not in settings.get("hooks", {}):
        return False
    del settings["hooks"]["PostCompact"]
    _write_json(path, settings)
    return True


def _copy_statusline(project_dir, plugin_root):
    if not plugin_root:
        return False
    src = os.path.join(plugin_root, "hooks", "statusline.sh")
    if not os.path.isfile(src):
        return False
    dest_dir = os.path.join(project_dir, ".claude", "hooks")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, "statusline.sh")
    shutil.copyfile(src, dest)
    os.chmod(dest, 0o755)
    return True


CANONICAL_WIRING = {
    "statusLine": {
        "type": "command",
        "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/statusline.sh',
    },
    "env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"},
    "permissions": {
        "allow": [
            "Bash(bash .harness/init.sh*)",
            'Bash("$CLAUDE_PROJECT_DIR"/.claude/hooks/*.sh*)',
            "Bash(git config user.name)",
            "Bash(git config user.email)",
            "Bash(git rev-parse*)",
            "Bash(git log*)",
            "Bash(git status*)",
            "Read(./.harness/**)",
        ]
    },
    "hooks": {
        "PreToolUse": [
            {"matcher": "Edit|Write|MultiEdit", "hooks": [{
                "type": "command",
                "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/enforce-scope.sh',
            }]},
            {"matcher": "Bash", "hooks": [{
                "type": "command",
                "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/verify-git-identity.sh',
            }]},
        ],
        "TaskCompleted": [{"hooks": [{
            "type": "command",
            "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/verify-task-quality.sh',
        }]}],
        "TeammateIdle": [{"hooks": [{
            "type": "command",
            "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/check-remaining-tasks.sh',
        }]}],
    },
}


def _add_settings_wiring(project_dir, plugin_root):
    path = os.path.join(project_dir, ".claude", "settings.json")
    settings = _load_json(path) or {}
    changed = False
    for key in ("statusLine", "env", "permissions"):
        if key not in settings:
            settings[key] = CANONICAL_WIRING[key]
            changed = True
    settings.setdefault("hooks", {})
    for event, blocks in CANONICAL_WIRING["hooks"].items():
        if event not in settings["hooks"]:
            settings["hooks"][event] = blocks
            changed = True
    if not changed:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _write_json(path, settings)
    return True


def _append_gitignore(project_dir, plugin_root):
    path = os.path.join(project_dir, ".gitignore")
    text = open(path).read() if os.path.isfile(path) else ""
    lines = [line.strip() for line in text.splitlines()]
    if ".harness/SESSION_INCOMPLETE" in lines:
        return False
    with open(path, "a") as fh:
        if text and not text.endswith("\n"):
            fh.write("\n")
        fh.write(".harness/SESSION_INCOMPLETE\n")
    return True


def _copy_harness_state(project_dir, plugin_root):
    if not plugin_root:
        return False
    templates_dir = os.path.join(plugin_root, "skills", "harness-init")
    dest_dir = os.path.join(project_dir, ".claude", "hooks")
    os.makedirs(dest_dir, exist_ok=True)
    copied = False
    for name in ("harness_state.py", "verify-task-quality.sh", "check-remaining-tasks.sh"):
        template = name + ".template"
        src = os.path.join(templates_dir, template)
        if not os.path.isfile(src):
            continue
        dest = os.path.join(dest_dir, name)
        shutil.copyfile(src, dest)
        os.chmod(dest, 0o755)
        copied = True
    return copied


def _load_json(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def _write_json(path, data):
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")


_FIXERS = {
    "remove_postcompact": _remove_postcompact,
    "copy_statusline": _copy_statusline,
    "add_settings_wiring": _add_settings_wiring,
    "append_gitignore": _append_gitignore,
    "copy_harness_state": _copy_harness_state,
}
