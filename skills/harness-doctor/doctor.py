#!/usr/bin/env python3
"""Report-first, idempotent instance health check for vv-harness projects.

Usage: doctor.py [--fix] [PROJECT_DIR]

Report mode (default) never writes anything. --fix applies only the mechanical
"upgrading an existing harness project" steps (see INSTALL.md); anything else
found is reported but left untouched.
"""
import json
import os
import shutil
import subprocess
import sys

HARD_REQUIRED_HOOKS = (
    "verify-task-quality.sh",
    "check-remaining-tasks.sh",
    "enforce-scope.sh",
    "verify-git-identity.sh",
    "statusline.sh",
)

REQUIRED_CONTEXT_HEADINGS = (
    "## Active Context",
    "## Cross-Cutting Concerns",
    "## Meta-Patterns",
)


class Finding:
    def __init__(self, message, repair, fix_id=None):
        self.message = message
        self.repair = repair
        self.fix_id = fix_id


def classify_drift(project_dir, rel_path):
    """Returns a short note on whether rel_path's current state traces to a
    commit or is a local, uncommitted edit. Never assumes committed drift
    without a diffable git baseline."""
    try:
        log = subprocess.run(
            ["git", "-C", project_dir, "log", "--oneline", "--", rel_path],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "no committed history available for this file; treating as local"
    if log.returncode != 0 or not log.stdout.strip():
        return "no committed history for this file; treating as local"
    diff = subprocess.run(
        ["git", "-C", project_dir, "diff", "--quiet", "HEAD", "--", rel_path],
        capture_output=True,
    )
    if diff.returncode == 0:
        return "matches the last commit; any problem here is committed, not local"
    return "differs from the last commit; uncommitted local edit"


def check_dependencies():
    findings = []
    if shutil.which("python3") is None:
        findings.append(Finding(
            "python3 not found on PATH", "install python3 -- every hook depends on it"
        ))
    if shutil.which("git") is None:
        findings.append(Finding("git not found on PATH", "install git"))
    return findings


def check_hooks(project_dir, plugin_root):
    hooks_dir = os.path.join(project_dir, ".claude", "hooks")
    findings = []
    for name in HARD_REQUIRED_HOOKS:
        path = os.path.join(hooks_dir, name)
        if not os.path.isfile(path):
            findings.append(_missing_hook_finding(name))
        elif not os.access(path, os.X_OK):
            findings.append(Finding(
                f"hook '{name}' is not executable", f"chmod +x .claude/hooks/{name}"
            ))
    findings.extend(_check_optional_v5_hooks(hooks_dir, plugin_root))
    return findings


def _missing_hook_finding(name):
    # statusline.sh is copied from the plugin's shared hooks/, not the per-project
    # skills/harness-init/*.sh.template set, and is one of INSTALL.md's 5 --fix steps.
    if name == "statusline.sh":
        return Finding(
            "hook 'statusline.sh' is missing from .claude/hooks/",
            'copy from the plugin: cp "${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh" '
            ".claude/hooks/statusline.sh && chmod +x .claude/hooks/statusline.sh",
            fix_id="copy_statusline",
        )
    return Finding(
        f"hook '{name}' is missing from .claude/hooks/",
        f'copy from the plugin: cp "${{CLAUDE_PLUGIN_ROOT}}/skills/harness-init/'
        f'{name}.template" .claude/hooks/{name} && chmod +x .claude/hooks/{name}',
    )


def _check_optional_v5_hooks(hooks_dir, plugin_root):
    findings = []
    state_path = os.path.join(hooks_dir, "harness_state.py")
    if not os.path.isfile(state_path):
        findings.append(Finding(
            "upgrade available: harness_state.py not present (post-OVI-50)",
            "copy skills/harness-init/harness_state.py.template to "
            ".claude/hooks/harness_state.py and chmod +x; re-copy verify-task-quality.sh/"
            "check-remaining-tasks.sh too, since older per-project copies may carry "
            "pre-OVI-50 inline logic",
            fix_id="copy_harness_state",
        ))
    elif not os.access(state_path, os.X_OK):
        findings.append(Finding(
            "harness_state.py is not executable", "chmod +x .claude/hooks/harness_state.py"
        ))
    if not plugin_root:
        return findings
    commit_gate_template = os.path.join(
        plugin_root, "skills", "harness-init", "commit-gate.sh.template"
    )
    if not os.path.isfile(commit_gate_template):
        return findings  # not-yet-applicable: F011/OVI-64 hasn't shipped a template yet
    if not os.path.isfile(os.path.join(hooks_dir, "commit-gate.sh")):
        findings.append(Finding(
            "upgrade available: commit-gate.sh not present (post-S4/OVI-64)",
            'copy from the plugin: cp "${CLAUDE_PLUGIN_ROOT}/skills/harness-init/'
            'commit-gate.sh.template" .claude/hooks/commit-gate.sh && '
            "chmod +x .claude/hooks/commit-gate.sh",
        ))
    return findings


SETTINGS_WIRING_CHECKS = (
    ("statusLine", lambda s: "statusLine" in s, "statusLine wiring"),
    (
        "env",
        lambda s: s.get("env", {}).get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") is not None,
        "env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS wiring",
    ),
    (
        "permissions",
        lambda s: bool(s.get("permissions", {}).get("allow")),
        "permissions.allow wiring",
    ),
    (
        "PreToolUse",
        lambda s: _hook_wired(s, "PreToolUse", "enforce-scope.sh")
        and _hook_wired(s, "PreToolUse", "verify-git-identity.sh"),
        "PreToolUse wiring for enforce-scope.sh and verify-git-identity.sh",
    ),
    (
        "TaskCompleted",
        lambda s: _hook_wired(s, "TaskCompleted", "verify-task-quality.sh"),
        "TaskCompleted wiring for verify-task-quality.sh",
    ),
    (
        "TeammateIdle",
        lambda s: _hook_wired(s, "TeammateIdle", "check-remaining-tasks.sh"),
        "TeammateIdle wiring for check-remaining-tasks.sh",
    ),
)


def _hook_wired(settings, event, script_name):
    for entry in settings.get("hooks", {}).get(event, []):
        for hook in entry.get("hooks", []):
            if script_name in hook.get("command", ""):
                return True
    return False


def check_settings(project_dir):
    path = os.path.join(project_dir, ".claude", "settings.json")
    if not os.path.isfile(path):
        return [Finding(".claude/settings.json is missing", "run /harness-init to generate it")]
    try:
        with open(path) as fh:
            settings = json.load(fh)
    except (OSError, ValueError) as exc:
        return [Finding(
            f".claude/settings.json does not parse: {exc}", "fix the JSON syntax error"
        )]
    findings = []
    for _, present, label in SETTINGS_WIRING_CHECKS:
        if not present(settings):
            findings.append(_with_drift(project_dir, ".claude/settings.json", Finding(
                f".claude/settings.json is missing {label}",
                "see skills/harness-init/SKILL.md Step 3.6 for the exact block to add",
                fix_id="add_settings_wiring",
            )))
    if "PostCompact" in settings.get("hooks", {}):
        findings.append(_with_drift(project_dir, ".claude/settings.json", Finding(
            ".claude/settings.json still has a PostCompact hook block (stale, pre-v5)",
            "remove it -- the plugin's SessionStart hook (compact source) already covers "
            "post-compaction recovery",
            fix_id="remove_postcompact",
        )))
    return findings


def _with_drift(project_dir, rel_path, finding):
    finding.message = f"{finding.message} ({classify_drift(project_dir, rel_path)})"
    return finding


def _gitignore_lines(text):
    return [line.strip() for line in text.splitlines()]


def check_gitignore(project_dir):
    path = os.path.join(project_dir, ".gitignore")
    if not os.path.isfile(path):
        return [Finding(
            ".gitignore is missing", "create one; see INSTALL.md's Per-Project Setup section"
        )]
    lines = _gitignore_lines(open(path).read())
    findings = []
    if any(line in (".claude/", ".claude/*", ".claude") for line in lines):
        if not any(line in ("!.claude/hooks/", "!.claude/settings.json") for line in lines):
            findings.append(Finding(
                ".gitignore appears to exclude .claude/ without un-ignoring the shared "
                "hooks/settings",
                "add !.claude/hooks/ and !.claude/settings.json exceptions, or stop "
                "excluding .claude/ entirely",
            ))
    if ".harness/SESSION_INCOMPLETE" not in lines:
        findings.append(_with_drift(project_dir, ".gitignore", Finding(
            ".gitignore is missing .harness/SESSION_INCOMPLETE",
            "append '.harness/SESSION_INCOMPLETE' to .gitignore",
            fix_id="append_gitignore",
        )))
    return findings


def check_harness_state_files(project_dir, plugin_root):
    findings = []
    harness_dir = os.path.join(project_dir, ".harness")
    findings.extend(_check_json_file(harness_dir, "harness.json"))
    findings.extend(_check_json_file(harness_dir, "features.json"))
    features_path = os.path.join(harness_dir, "features.json")
    if plugin_root and os.path.isfile(features_path):
        findings.extend(_run_features_validator(plugin_root, features_path))
    findings.extend(_check_context_summary(harness_dir))
    return findings


def _check_json_file(harness_dir, name):
    path = os.path.join(harness_dir, name)
    if not os.path.isfile(path):
        return [Finding(f".harness/{name} is missing", "run /harness-init to generate it")]
    try:
        with open(path) as fh:
            json.load(fh)
    except (OSError, ValueError) as exc:
        return [Finding(f".harness/{name} does not parse: {exc}", "fix the JSON syntax error")]
    return []


def _run_features_validator(plugin_root, features_path):
    validator = os.path.join(plugin_root, "scripts", "validate-features.py")
    if not os.path.isfile(validator):
        return []
    result = subprocess.run(
        ["python3", validator, features_path], capture_output=True, text=True
    )
    if result.returncode == 0:
        return []
    return [Finding(
        f".harness/features.json fails validation: {result.stderr.strip()}",
        "fix the reported field(s); see schemas/feature.schema.json",
    )]


def _check_context_summary(harness_dir):
    path = os.path.join(harness_dir, "context_summary.md")
    if not os.path.isfile(path):
        return [Finding(
            ".harness/context_summary.md is missing", "run /harness-init to generate it"
        )]
    text = open(path).read()
    missing = [h for h in REQUIRED_CONTEXT_HEADINGS if h not in text]
    if "## Domain: " not in text and "## Domain:" not in text:
        missing.append("## Domain: <name>")
    if not missing:
        return []
    return [Finding(
        f".harness/context_summary.md is missing required section(s): {', '.join(missing)}",
        "see rules/context-summary.md for the canonical template",
    )]


def check_mld_non_injection(project_dir, plugin_root):
    mld_dir = os.path.join(project_dir, ".harness", "mld")
    if not os.path.isdir(mld_dir):
        return []  # not-yet-applicable: nothing to guard if the directory doesn't exist
    if not plugin_root:
        return []  # can't check the plugin's own session-start.sh without its root
    # session-start.sh is never copied into a project's .claude/hooks/ -- it is a
    # plugin-level file invoked directly from CLAUDE_PLUGIN_ROOT, so the guarantee
    # to check is the currently running plugin's copy, not anything per-project.
    session_start = os.path.join(plugin_root, "hooks", "session-start.sh")
    if not os.path.isfile(session_start):
        return []
    if "mld" in open(session_start).read():
        return [Finding(
            "the plugin's session-start.sh references .harness/mld/ "
            "(non-injection guarantee broken)",
            "remove the reference -- .harness/mld/ must never be read into model context",
        )]
    return []


def run_checks(project_dir, plugin_root):
    findings = []
    findings.extend(check_dependencies())
    findings.extend(check_hooks(project_dir, plugin_root))
    findings.extend(check_settings(project_dir))
    findings.extend(check_gitignore(project_dir))
    findings.extend(check_harness_state_files(project_dir, plugin_root))
    findings.extend(check_mld_non_injection(project_dir, plugin_root))
    return findings


def apply_fixes(project_dir, plugin_root, findings):
    from fixes import apply_fix  # local import: keeps fixers out of the report path

    fix_ids = {f.fix_id for f in findings if f.fix_id}
    for fix_id in fix_ids:
        apply_fix(project_dir, plugin_root, fix_id)
    # Re-run fresh rather than trusting each fixer's per-call return value: a single
    # fixer invocation (e.g. add_settings_wiring) can resolve several findings that
    # share its fix_id at once, so a stale per-finding "did I just change something"
    # check would misreport the others as still-open.
    return run_checks(project_dir, plugin_root)


def report(findings):
    if not findings:
        print("healthy")
        return 0
    for finding in findings:
        print(f"FINDING: {finding.message}")
        print(f"  fix: {finding.repair}")
    return 1


def main(argv):
    args = argv[1:]
    fix = "--fix" in args
    positional = [a for a in args if a != "--fix"]
    project_dir = os.path.abspath(positional[0]) if positional else os.getcwd()

    if not os.path.isdir(os.path.join(project_dir, ".harness")):
        print("not a harness project (no .harness/ directory) -- run /harness-init")
        return 2

    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    findings = run_checks(project_dir, plugin_root)
    if fix:
        findings = apply_fixes(project_dir, plugin_root, findings)
    return report(findings)


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    sys.exit(main(sys.argv))
