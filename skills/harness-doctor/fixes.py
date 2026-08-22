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
    hooks = settings.get("hooks") if settings else None
    if not isinstance(hooks, dict) or "PostCompact" not in hooks:
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
            {"matcher": "Bash", "hooks": [
                {
                    "type": "command",
                    "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/enforce-scope.sh',
                },
                {
                    "type": "command",
                    "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/verify-git-identity.sh',
                },
                {
                    "type": "command",
                    "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/commit-gate.sh',
                },
            ]},
        ],
        "TaskCompleted": [{"hooks": [{
            "type": "command",
            "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/verify-task-quality.sh',
        }]}],
    },
}


def _add_settings_wiring(project_dir, plugin_root):
    path = os.path.join(project_dir, ".claude", "settings.json")
    settings = _load_json(path) or {}
    changed = False
    for key in ("statusLine", "permissions"):
        if key not in settings:
            settings[key] = CANONICAL_WIRING[key]
            changed = True
    # A "hooks" key holding a list or a string parses fine and then fails the
    # item assignment below. Replace it: doctor already reports the malformed
    # shape separately, and a fixer whose whole job is to install wiring cannot
    # merge into a container that cannot hold it.
    if not isinstance(settings.get("hooks"), dict):
        settings["hooks"] = {}
        changed = True
    for event, blocks in CANONICAL_WIRING["hooks"].items():
        if event not in settings["hooks"]:
            settings["hooks"][event] = blocks
            changed = True
    if not changed:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _write_json(path, settings)
    return True


# Mirrors doctor.py's REQUIRED_GITIGNORE_LINES (not imported, to keep this module
# loadable standalone via sys.path.insert -- see doctor.py's own header comment on
# why fixers stay out of the report path). Keep the two lists in sync.
REQUIRED_GITIGNORE_LINES = (
    ".harness/SESSION_INCOMPLETE",
    ".harness/features.json.lock",
    ".harness/dashboard/",
    ".harness/last_gate.json",
)


def _append_gitignore(project_dir, plugin_root):
    path = os.path.join(project_dir, ".gitignore")
    text = open(path).read() if os.path.isfile(path) else ""
    lines = [line.strip() for line in text.splitlines()]
    missing = [line for line in REQUIRED_GITIGNORE_LINES if line not in lines]
    if not missing:
        return False
    with open(path, "a") as fh:
        if text and not text.endswith("\n"):
            fh.write("\n")
        for line in missing:
            fh.write(line + "\n")
    return True


def _copy_harness_state(project_dir, plugin_root):
    if not plugin_root:
        return False
    templates_dir = os.path.join(plugin_root, "skills", "harness-init")
    dest_dir = os.path.join(project_dir, ".claude", "hooks")
    os.makedirs(dest_dir, exist_ok=True)
    copied = False
    for name in ("harness_state.py", "verify-task-quality.sh"):
        template = name + ".template"
        src = os.path.join(templates_dir, template)
        if not os.path.isfile(src):
            continue
        dest = os.path.join(dest_dir, name)
        shutil.copyfile(src, dest)
        os.chmod(dest, 0o755)
        copied = True
    return copied


def _copy_commit_gate(project_dir, plugin_root):
    if not plugin_root:
        return False
    src = os.path.join(plugin_root, "skills", "harness-init", "commit-gate.sh.template")
    if not os.path.isfile(src):
        return False
    dest_dir = os.path.join(project_dir, ".claude", "hooks")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, "commit-gate.sh")
    shutil.copyfile(src, dest)
    os.chmod(dest, 0o755)
    return True


def _update_plugin_version(project_dir, plugin_root):
    if not plugin_root:
        return False
    manifest = _load_json(os.path.join(plugin_root, ".claude-plugin", "plugin.json"))
    if manifest is None or not manifest.get("version"):
        return False
    harness_path = os.path.join(project_dir, ".harness", "harness.json")
    harness = _load_json(harness_path)
    if harness is None:
        return False
    harness["plugin_version"] = manifest["version"]
    _write_json(harness_path, harness)
    return True


# Mirrors doctor.py's constants of the same names (not imported, for the same
# standalone-loadability reason as REQUIRED_GITIGNORE_LINES above).
TEAMS_ENV_FLAG = "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
RETIRED_IDLE_HOOK = "check-remaining-tasks.sh"
RETIRED_SCOPE_FILE = "teammate-scope.txt"


def _remove_teams_settings(project_dir, plugin_root):
    """Strips both Agent Teams remnants from settings.json under a single
    backup. The .bak is written only once something is actually going to
    change, so a no-op run never clobbers a backup with an identical copy."""
    path = os.path.join(project_dir, ".claude", "settings.json")
    settings = _load_json(path)
    if settings is None:
        return False
    changed = _drop_teams_env_flag(settings)
    changed = _drop_teammateidle_hook(settings) or changed
    if not changed:
        return False
    shutil.copyfile(path, path + ".bak")
    _write_json(path, settings)
    return True


def _drop_teams_env_flag(settings):
    env = settings.get("env")
    if not isinstance(env, dict) or TEAMS_ENV_FLAG not in env:
        return False
    del env[TEAMS_ENV_FLAG]
    if not env:
        del settings["env"]  # nothing else was in there; leave no empty block
    return True


def _drop_teammateidle_hook(settings):
    """Removes only the harness's own check-remaining-tasks.sh entry. A
    user-authored hook in the same TeammateIdle array is preserved, and the
    event key itself goes only when nothing is left to run."""
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict) or not isinstance(hooks.get("TeammateIdle"), list):
        return False
    kept, changed = _strip_retired_idle_entries(hooks["TeammateIdle"])
    if not changed:
        return False
    if kept:
        hooks["TeammateIdle"] = kept
    else:
        del hooks["TeammateIdle"]
    return True


def _strip_retired_idle_entries(entries):
    """Returns (surviving entries, whether anything was removed). An entry
    left with no hooks at all drops out; one that never declared any is
    passed through untouched, since it was never ours to interpret."""
    kept = []
    changed = False
    for entry in entries:
        commands = entry.get("hooks", []) if isinstance(entry, dict) else []
        remaining = [h for h in commands if not _is_retired_idle_hook(h)]
        if len(remaining) != len(commands):
            changed = True
            entry["hooks"] = remaining
        if remaining or not commands:
            kept.append(entry)
    return kept, changed


def _is_retired_idle_hook(hook):
    return isinstance(hook, dict) and RETIRED_IDLE_HOOK in hook.get("command", "")


def _remove_retired_idle_hook(project_dir, plugin_root):
    path = os.path.join(project_dir, ".claude", "hooks", RETIRED_IDLE_HOOK)
    if not os.path.isfile(path):
        return False
    os.remove(path)
    return True


def _remove_teammate_scope(project_dir, plugin_root):
    path = os.path.join(project_dir, ".claude", RETIRED_SCOPE_FILE)
    if not os.path.isfile(path):
        return False
    os.remove(path)
    return True


def _load_json(path):
    """The document only when it is a JSON object, else None.

    Every caller mutates the result by key. json.load succeeding says nothing
    about the document being an object, and a bare array or a top-level string
    reached the fixers as a TypeError rather than as the malformed-settings
    finding doctor already reports separately.
    """
    if not os.path.isfile(path):
        return None
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


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
    "copy_commit_gate": _copy_commit_gate,
    "update_plugin_version": _update_plugin_version,
    "remove_teams_settings": _remove_teams_settings,
    "remove_retired_idle_hook": _remove_retired_idle_hook,
    "remove_teammate_scope": _remove_teammate_scope,
}
