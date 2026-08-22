#!/usr/bin/env python3
"""Report-first, idempotent instance health check for vv-harness projects.

Usage: doctor.py [--fix] [PROJECT_DIR]

Report mode (default) never writes anything. --fix applies only the mechanical
"upgrading an existing harness project" steps (see INSTALL.md); anything else
found is reported but left untouched.
"""
import json
import os
import re
import shutil
import subprocess
import sys

#: Every subprocess this module spawns is bounded. A health check that hangs
#: is worse than one that reports a failure: the caller is a slash command a
#: human is waiting on, and an unbounded child (a stalled git, a validator
#: from a half-installed plugin) hangs it with no diagnostic at all.
GIT_TIMEOUT_SECONDS = 5
VALIDATOR_TIMEOUT_SECONDS = 20

_CONTROL = re.compile(r"[\x00-\x1f\x7f]")


def _one_line(value, limit=200):
    """Untrusted text, flattened to one bounded line for a report.

    Feature ids and test_file paths come from .harness/features.json, which is
    written upstream of this module. A newline in one of them splits a FINDING
    across lines that read as separate findings -- a file can otherwise forge
    the doctor's own output -- and a control byte reaches the terminal raw.
    """
    text = value if isinstance(value, str) else str(value)
    text = _CONTROL.sub(" ", text)
    return text if len(text) <= limit else f"{text[:limit]}... ({len(text)} chars total)"


def _read_text_file(path):
    """(text, error). Presence is not readability: os.path.isfile passes for a
    file that is not valid UTF-8 and for one this process cannot open."""
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read(), None
    except (OSError, UnicodeDecodeError) as exc:
        return None, f"cannot be read: {_one_line(exc, 120)}"


def _load_json_object(path):
    """(document, error) where document is a dict.

    json.load succeeding is not proof the document is an object. Every caller
    below immediately does .get() on the result, so a bare array, a literal
    null, or a top-level string turns a health report into an AttributeError.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError, UnicodeDecodeError) as exc:
        return None, f"does not parse: {_one_line(exc, 120)}"
    if not isinstance(data, dict):
        return None, f"is not a JSON object (found {type(data).__name__})"
    return data, None


HARD_REQUIRED_HOOKS = (
    "verify-task-quality.sh",
    "enforce-scope.sh",
    "verify-git-identity.sh",
    "statusline.sh",
)

# Agent Teams was retired in v6 (v5.7.0 made worktree-isolated workflows primary).
# These three artifacts are what a project initialized under v5.x still carries.
TEAMS_ENV_FLAG = "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
RETIRED_IDLE_HOOK = "check-remaining-tasks.sh"
RETIRED_SCOPE_FILE = "teammate-scope.txt"

# Workflow mode's floor, per the OVI-140 spike (evals/workflow-gate-verification.md,
# Q8): below this the single-session fallback applies.
WORKFLOW_MIN_CLI_VERSION = (2, 1, 154)

REQUIRED_CONTEXT_HEADINGS = (
    "## Active Context",
    "## Cross-Cutting Concerns",
    "## Meta-Patterns",
)

# F077/OVI-107 follow-up: two lines, not one -- .harness/features.json.lock joined
# SESSION_INCOMPLETE post-OVI-107. _append_gitignore below must append whichever of
# these are missing, not early-return on the presence of just the first.
REQUIRED_GITIGNORE_LINES = (
    ".harness/SESSION_INCOMPLETE",
    ".harness/features.json.lock",
    ".harness/dashboard/",
    ".harness/last_gate.json",
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
        capture_output=True, timeout=GIT_TIMEOUT_SECONDS,
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
            ".claude/hooks/harness_state.py and chmod +x; re-copy verify-task-quality.sh "
            "too, since older per-project copies may carry pre-OVI-50 inline logic",
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
            fix_id="copy_commit_gate",
        ))
    return findings


SETTINGS_WIRING_CHECKS = (
    ("statusLine", lambda s: "statusLine" in s, "statusLine wiring"),
    (
        "permissions",
        lambda s: bool(s.get("permissions", {}).get("allow")),
        "permissions.allow wiring",
    ),
    (
        "PreToolUse",
        lambda s: _hook_wired(s, "PreToolUse", "enforce-scope.sh", matcher="Edit|Write|MultiEdit")
        and _hook_wired(s, "PreToolUse", "enforce-scope.sh", matcher="Bash")
        and _hook_wired(s, "PreToolUse", "verify-git-identity.sh", matcher="Bash")
        and _hook_wired(s, "PreToolUse", "commit-gate.sh", matcher="Bash"),
        "PreToolUse wiring for enforce-scope.sh (Edit|Write|MultiEdit and Bash "
        "matchers), verify-git-identity.sh, and commit-gate.sh (Bash matcher)",
    ),
    (
        "TaskCompleted",
        lambda s: _hook_wired(s, "TaskCompleted", "verify-task-quality.sh"),
        "TaskCompleted wiring for verify-task-quality.sh",
    ),
)


def _hook_wired(settings, event, script_name, matcher=None):
    # Every level of this structure is user-editable JSON, so every level is
    # shape-checked: a "hooks" key holding a list parses fine and then fails
    # the .get() below, which used to crash all four wiring checks at once.
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return False
    entries = hooks.get(event)
    if not isinstance(entries, list):
        return False
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if matcher is not None and entry.get("matcher") != matcher:
            continue
        inner = entry.get("hooks")
        if not isinstance(inner, list):
            continue
        for hook in inner:
            if not isinstance(hook, dict):
                continue
            command = hook.get("command")
            if isinstance(command, str) and script_name in command:
                return True
    return False


def _read_settings(project_dir):
    """Loads .claude/settings.json, or None when it is missing, unparseable, or
    not a JSON object. check_settings reports all of those cases with their own
    messages, so every other reader just declines to run rather than
    duplicating them."""
    path = os.path.join(project_dir, ".claude", "settings.json")
    if not os.path.isfile(path):
        return None
    settings, _error = _load_json_object(path)
    return settings


def check_settings(project_dir):
    path = os.path.join(project_dir, ".claude", "settings.json")
    if not os.path.isfile(path):
        return [Finding(".claude/settings.json is missing", "run /harness-init to generate it")]
    settings, error = _load_json_object(path)
    if error:
        return [Finding(
            f".claude/settings.json {error}", "fix the JSON syntax error"
        )]
    findings = []
    for _, present, label in SETTINGS_WIRING_CHECKS:
        if not present(settings):
            findings.append(_with_drift(project_dir, ".claude/settings.json", Finding(
                f".claude/settings.json is missing {label}",
                "see skills/harness-init/templates/settings.json.tmpl for the canonical "
                "wiring (a template, not pasteable JSON), or run scripts/stamp.sh with "
                "mode=upgrade",
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


def check_teams_migration(project_dir):
    """Agent Teams was retired in v6. A project initialized under v5.x
    still carries its wiring -- a TeammateIdle route to a hook that no longer
    ships, the experimental env flag, the orphaned hook file, and whatever
    teammate-scope.txt the last team left behind. None of it does anything
    now, and the scope file actively gates edits, so each is reported as a
    migration step with a fixer behind the same --fix approval as every other
    repair here."""
    findings = _check_stale_teams_settings(project_dir)
    hook_path = os.path.join(project_dir, ".claude", "hooks", RETIRED_IDLE_HOOK)
    if os.path.isfile(hook_path):
        findings.append(Finding(
            f".claude/hooks/{RETIRED_IDLE_HOOK} is left over from the retired "
            "TeammateIdle nudge (Agent Teams, retired in v6)",
            "nothing invokes it any more -- run doctor --fix to delete it",
            fix_id="remove_retired_idle_hook",
        ))
    scope_path = os.path.join(project_dir, ".claude", RETIRED_SCOPE_FILE)
    if os.path.isfile(scope_path):
        findings.append(Finding(
            f".claude/{RETIRED_SCOPE_FILE} is stale Agent Teams state "
            "(retired in v6)",
            "workflow mode isolates each agent in its own worktree instead -- run "
            "doctor --fix to delete it",
            fix_id="remove_teammate_scope",
        ))
    return findings


def _check_stale_teams_settings(project_dir):
    """The two settings.json halves of the migration. They share one fix_id so
    a single fixer makes both edits under one settings.json.bak -- two fixers
    would have the second overwrite the first's backup with already-mutated
    content."""
    settings = _read_settings(project_dir)
    if settings is None:
        return []
    findings = []
    if _hook_wired(settings, "TeammateIdle", RETIRED_IDLE_HOOK):
        findings.append(_with_drift(project_dir, ".claude/settings.json", Finding(
            f".claude/settings.json still wires TeammateIdle to {RETIRED_IDLE_HOOK} "
            "(Agent Teams, retired in v6)",
            "run doctor --fix to drop that hook entry -- a user-authored TeammateIdle "
            "hook alongside it is preserved, and the event key is removed only if "
            "nothing is left",
            fix_id="remove_teams_settings",
        )))
    if TEAMS_ENV_FLAG in settings.get("env", {}):
        findings.append(_with_drift(project_dir, ".claude/settings.json", Finding(
            f".claude/settings.json still sets env.{TEAMS_ENV_FLAG} "
            "(Agent Teams, retired in v6)",
            "run doctor --fix to remove it -- the flag gates nothing now",
            fix_id="remove_teams_settings",
        )))
    return findings


def _probe_cli_version():
    """The claude CLI's version as an (int, int, int) tuple, or None when the
    CLI is absent, errors, or prints anything this can't parse. Defensive by
    construction: the output format is not a contract, and no version probe
    may ever fail a health report."""
    if shutil.which("claude") is None:
        return None
    try:
        result = subprocess.run(
            ["claude", "--version"], capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    parts = result.stdout.strip().split(" ")[0].split(".")
    if len(parts) < 3:
        return None
    try:
        return tuple(int(part) for part in parts[:3])
    except ValueError:
        return None


def _workflow_tool_disabled(project_dir):
    """True when the settings explicitly turn the Workflow tool off. Two
    literal forms are recognized, deliberately no more: a permissions.deny
    entry naming Workflow, and the org-level disableWorkflows switch named in
    evals/workflow-gate-verification.md Q8. Anything subtler is detected at
    runtime by the skill, which falls back on the tool simply being absent."""
    settings = _read_settings(project_dir)
    if settings is None:
        return False
    if settings.get("disableWorkflows") is True:
        return True
    for entry in settings.get("permissions", {}).get("deny", []):
        if entry == "Workflow" or (
            isinstance(entry, str) and entry.startswith("Workflow(")
        ):
            return True
    return False


def check_workflow_support(project_dir):
    """Workflow mode needs a recent CLI and an enabled Workflow tool. Neither
    is a health defect: without them the single-session fallback applies and
    the project is fine. So this returns notice lines, never Findings -- they
    are printed alongside the report but never change its exit code."""
    version = _probe_cli_version()
    if version is None:
        return ["INFO: claude CLI version undetectable -- skipping workflow-support check"]
    notices = []
    if version < WORKFLOW_MIN_CLI_VERSION:
        detected = ".".join(str(part) for part in version)
        floor = ".".join(str(part) for part in WORKFLOW_MIN_CLI_VERSION)
        notices.append(
            f"WARN: claude CLI {detected} < {floor} -- workflow mode unavailable, "
            "single-session fallback applies"
        )
    if _workflow_tool_disabled(project_dir):
        notices.append(
            "WARN: Workflow tool disabled in settings -- workflow mode unavailable"
        )
    return notices


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
    text, error = _read_text_file(path)
    if error:
        return [Finding(f".gitignore {error}", "make it a readable UTF-8 text file")]
    lines = _gitignore_lines(text)
    findings = []
    if any(line in (".claude/", ".claude/*", ".claude") for line in lines):
        if not any(line in ("!.claude/hooks/", "!.claude/settings.json") for line in lines):
            findings.append(Finding(
                ".gitignore appears to exclude .claude/ without un-ignoring the shared "
                "hooks/settings",
                "add !.claude/hooks/ and !.claude/settings.json exceptions, or stop "
                "excluding .claude/ entirely",
            ))
    for required_line in REQUIRED_GITIGNORE_LINES:
        if required_line not in lines:
            findings.append(_with_drift(project_dir, ".gitignore", Finding(
                f".gitignore is missing {required_line}",
                f"append '{required_line}' to .gitignore",
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
    _document, error = _load_json_object(path)
    if error:
        return [Finding(f".harness/{name} {error}", "fix the JSON syntax error")]
    return []


def _run_features_validator(plugin_root, features_path):
    validator = os.path.join(plugin_root, "scripts", "validate-features.py")
    if not os.path.isfile(validator):
        return []
    try:
        result = subprocess.run(
            ["python3", validator, features_path],
            capture_output=True, text=True, timeout=VALIDATOR_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return [Finding(
            f".harness/features.json could not be validated: the validator did not "
            f"finish within {VALIDATOR_TIMEOUT_SECONDS}s",
            "check the plugin install at CLAUDE_PLUGIN_ROOT/scripts/validate-features.py",
        )]
    except OSError as exc:
        return [Finding(
            f".harness/features.json could not be validated: {_one_line(exc, 120)}",
            "check the plugin install at CLAUDE_PLUGIN_ROOT/scripts/validate-features.py",
        )]
    if result.returncode == 0:
        return []
    return [Finding(
        f".harness/features.json fails validation: {_one_line(result.stderr.strip(), 400)}",
        "fix the reported field(s); see schemas/feature.schema.json",
    )]


def _check_context_summary(harness_dir):
    path = os.path.join(harness_dir, "context_summary.md")
    if not os.path.isfile(path):
        return [Finding(
            ".harness/context_summary.md is missing", "run /harness-init to generate it"
        )]
    text, error = _read_text_file(path)
    if error:
        return [Finding(
            f".harness/context_summary.md {error}", "make it a readable UTF-8 text file"
        )]
    missing = [h for h in REQUIRED_CONTEXT_HEADINGS if h not in text]
    if "## Domain: " not in text and "## Domain:" not in text:
        missing.append("## Domain: <name>")
    if not missing:
        return []
    return [Finding(
        f".harness/context_summary.md is missing required section(s): {', '.join(missing)}",
        "see rules/context-summary.md for the canonical template",
    )]


TEST_FILE_CHECK_STATUSES = ("passing", "in-progress")


def check_feature_test_files(project_dir):
    """F066: a passing/in-progress feature's test_file is a claim, not a fact --
    session-start.sh faithfully reports whatever features.json says, and nothing
    validates that the referenced path actually resolves. This closes that gap as
    a report-only structural check (there is no fixer: doctor can't invent a
    missing test file, only surface that the claim doesn't hold)."""
    features_path = os.path.join(project_dir, ".harness", "features.json")
    if not os.path.isfile(features_path):
        return []  # already reported by check_harness_state_files
    data, error = _load_json_object(features_path)
    if error:
        return []  # already reported by check_harness_state_files
    features = data.get("features")
    if not isinstance(features, list):
        return []  # already reported by the features validator
    findings = []
    for feature in features:
        if not isinstance(feature, dict):
            continue  # reported by the features validator, not walkable here
        status = feature.get("status")
        if status not in TEST_FILE_CHECK_STATUSES:
            continue
        test_file = feature.get("test_file")
        if not test_file or not isinstance(test_file, str):
            continue
        if not os.path.isfile(os.path.join(project_dir, test_file)):
            findings.append(Finding(
                f"{_one_line(feature.get('id', '?'), 60)} is {_one_line(status, 30)} but its "
                f"test_file '{_one_line(test_file, 120)}' does not exist in the working tree",
                "correct test_file to the real path, or reset the feature's status "
                "if the work it claims was never actually committed",
            ))
    return findings


def check_version_drift(project_dir, plugin_root):
    """F068: harness.json's optional plugin_version field records the plugin
    version a project was last synced against. Round-1 review (PR #113) found
    that treating absence as silently valid (mirroring the F016 worker block)
    left the check permanently inert for every pre-existing project: nothing
    but this check's own --fix ever writes plugin_version, and a check that
    never fires never fires its fixer either. Absence is instead classified
    like the harness_state.py "upgrade available" case (see
    _check_optional_v5_hooks): reported, fixable, not a hard error -- a
    project that has simply never run doctor --fix since F068 shipped is not
    broken, just behind."""
    if not plugin_root:
        return []  # can't compare without knowing the running plugin's version
    manifest_path = os.path.join(plugin_root, ".claude-plugin", "plugin.json")
    if not os.path.isfile(manifest_path):
        return []
    manifest, error = _load_json_object(manifest_path)
    if error:
        return []
    current = manifest.get("version")
    if not current:
        return []
    harness_path = os.path.join(project_dir, ".harness", "harness.json")
    if not os.path.isfile(harness_path):
        return []  # already reported by check_harness_state_files
    harness_document, error = _load_json_object(harness_path)
    if error:
        return []  # already reported by check_harness_state_files
    recorded = harness_document.get("plugin_version")
    if recorded == current:
        return []
    if not recorded:
        return [Finding(
            f"upgrade available: .harness/harness.json has no plugin_version "
            f"recorded (currently installed plugin is '{current}')",
            "run doctor --fix to record it",
            fix_id="update_plugin_version",
        )]
    return [Finding(
        f".harness/harness.json records plugin_version '{recorded}', but the "
        f"currently installed plugin is '{current}'",
        "review CHANGELOG.md between the two versions for hook/skill changes, "
        "then re-run doctor --fix to update the recorded version",
        fix_id="update_plugin_version",
    )]


def check_focused_test_skip_contract(project_dir):
    """F108: .harness/init.sh is a per-project copy made at init time, so
    v5.5.0's focused_test exit-code contract (F106 -- exit 3 reserved for
    skips, a runner's own exit 3 remapped to 1, missing test files skipped
    rather than faked green) never reaches a project that adopted
    focused_test before F106 shipped. That project's init.sh still has the
    old exit-0 skip arms, and the pre-F106 fake-green persists silently.
    init.sh is the one genuinely decision-shaped per-project file (it mixes
    in project-specific stack logic), so this is report-only, same as
    check_feature_test_files: there is no fixer, only a hand-apply repair."""
    init_path = os.path.join(project_dir, ".harness", "init.sh")
    if not os.path.isfile(init_path):
        return []  # already reported by verify-task-quality's own missing-init.sh gate
    text, error = _read_text_file(init_path)
    if error:
        return [Finding(
            f".harness/init.sh {error}",
            "make it a readable UTF-8 shell script",
        )]
    non_comment = "\n".join(
        line for line in text.splitlines() if not line.strip().startswith("#")
    )
    if "focused_test" not in non_comment:
        return []  # doesn't support focused_test at all -- nothing to check
    # Both tests run against non_comment: a comment quoting the markers (a TODO
    # note, or the doctor's own finding text pasted as a reminder) must not
    # satisfy the contract, and the pre-F106 fake-green wording is checked
    # positively so a partially hand-applied repair (some arms upgraded, some
    # still 'treating as pass') is still flagged, not cleared by the first
    # upgraded arm's markers.
    # run_focused is deliberately NOT required: a stack with no per-file runner
    # skips every focused_test invocation with the exit-3 marker and has no
    # runner exit code to remap (the v5.7.0 initializer generates exactly this
    # always-skip shape for stdlib-unittest Python projects; requiring
    # run_focused false-positived on it -- OVI-147 field validation). The
    # trade-off: a runner-invoking init.sh missing only the remap goes
    # undetected; both fake-green signatures (missing marker, 'treating as
    # pass') remain fully detected.
    has_marker = "skipped (exit 3)" in non_comment
    has_fake_green = "treating as pass" in non_comment
    if has_marker and not has_fake_green:
        return []
    return [Finding(
        "upgrade available: .harness/init.sh supports focused_test but is missing "
        "the v5.5.0 exit-3 skip contract (F106) -- no 'skipped (exit 3)' marker "
        "on a non-comment line and/or a leftover pre-F106 'treating as "
        "pass' arm, so a skip can be reported as a fake green",
        "hand-apply: compare .harness/init.sh's focused_test block against "
        "skills/harness-init/init.sh.template's and add the missing skip markers "
        "and remap by hand -- init.sh is never auto-refreshed by doctor --fix "
        "since it carries project-specific stack logic (see INSTALL.md's "
        "'Upgrading an existing harness project' section)",
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
    session_start_text, error = _read_text_file(session_start)
    if error:
        return [Finding(
            f"the plugin's session-start.sh {error}, so the non-injection guarantee "
            "could not be verified",
            "reinstall the plugin",
        )]
    if "mld" in session_start_text:
        return [Finding(
            "the plugin's session-start.sh references .harness/mld/ "
            "(non-injection guarantee broken)",
            "remove the reference -- .harness/mld/ must never be read into model context",
        )]
    return []


# OVI-104: commit-gate.sh presence (_check_optional_v5_hooks), features.json
# cross-validation (_run_features_validator via check_harness_state_files),
# plugin_version drift (check_version_drift), and -- when applicable, see
# MLD_CHECK_NAME below -- the .harness/mld/ non-injection guarantee
# (check_mld_non_injection) all silently return no findings when plugin_root
# is falsy -- each one individually correct (none can compare against a
# plugin it can't locate), but several independent silent skips add up to a
# "healthy" report that quietly verified less than it looks like it did. One
# consolidated Finding here, instead of teaching each check to also
# self-report, keeps the skip visible without repeating the same "set
# CLAUDE_PLUGIN_ROOT" advice once per check.
PLUGIN_ROOT_GATED_CHECKS = (
    "commit-gate.sh presence",
    "features.json cross-validation against the plugin's validator",
    "plugin_version drift",
)

# The mld non-injection guarantee is only listed above when it's actually
# applicable (round-1 review of PR #123): check_mld_non_injection already
# no-ops when .harness/mld/ doesn't exist, before it even looks at
# plugin_root -- for the common case of a project with no mld/ directory,
# that check was never going to run regardless of CLAUDE_PLUGIN_ROOT, so
# blaming the unset variable for it would overstate what's actually skipped.
MLD_CHECK_NAME = "the .harness/mld/ non-injection guarantee"


def check_plugin_root_unset(project_dir, plugin_root):
    if plugin_root:
        return []
    checks = list(PLUGIN_ROOT_GATED_CHECKS)
    if os.path.isdir(os.path.join(project_dir, ".harness", "mld")):
        checks.append(MLD_CHECK_NAME)
    joined = ", ".join(checks)
    return [Finding(
        f"CLAUDE_PLUGIN_ROOT is not set -- {len(checks)} checks could not "
        f"run and were silently skipped: {joined}",
        "set CLAUDE_PLUGIN_ROOT to the plugin's install directory and re-run doctor for a "
        "complete report (Claude Code sets it automatically when the plugin is active; a "
        "manual or CI invocation of doctor.py must set it explicitly)",
    )]


def run_checks(project_dir, plugin_root):
    findings = []
    findings.extend(check_dependencies())
    findings.extend(check_hooks(project_dir, plugin_root))
    findings.extend(check_settings(project_dir))
    findings.extend(check_teams_migration(project_dir))
    findings.extend(check_gitignore(project_dir))
    findings.extend(check_harness_state_files(project_dir, plugin_root))
    findings.extend(check_feature_test_files(project_dir))
    findings.extend(check_version_drift(project_dir, plugin_root))
    findings.extend(check_focused_test_skip_contract(project_dir))
    findings.extend(check_mld_non_injection(project_dir, plugin_root))
    findings.extend(check_plugin_root_unset(project_dir, plugin_root))
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
    for notice in check_workflow_support(project_dir):
        print(notice)
    findings = run_checks(project_dir, plugin_root)
    if fix:
        findings = apply_fixes(project_dir, plugin_root, findings)
    return report(findings)


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    sys.exit(main(sys.argv))
