"""Gates suite: the plugin's mechanical enforcement surface, run adversarially.

session-start.sh only informs a session. These six scripts decide things --
they deny a write, block a push, reject a completed task, or report a project
healthy. Their failure modes are silent by construction: a guard that crashes,
mis-parses, or fails open still exits 0, and nothing downstream notices that
enforcement stopped. Each fixture below targets a specific line where that can
happen; the invariant asserted is the one the script itself claims, never a
stricter one invented here.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from harnesslib import (
    REPO_ROOT,
    Recorder,
    build_project,
    canonical_features,
    control_chars,
    feature,
    git_commit_all,
    run_hook,
)

SUITE = "gates"
TEMPLATES = REPO_ROOT / "skills" / "harness-init"
DOCTOR = REPO_ROOT / "skills" / "harness-doctor" / "doctor.py"
STATE_MODULE = TEMPLATES / "harness_state.py.template"

TRACEBACK = "Traceback (most recent call last)"

#: A fake claude CLI keeps doctor.py's version probe from making the score
#: depend on whether the machine running the eval has the real binary.
FAKE_CLI = '#!/bin/sh\necho "2.1.226 (Claude Code)"\n'


def make_bin(root: Path) -> Path:
    bindir = root / "bin"
    bindir.mkdir(parents=True, exist_ok=True)
    claude = bindir / "claude"
    claude.write_text(FAKE_CLI, encoding="utf-8")
    claude.chmod(0o755)
    return bindir


def install_gate(project: Path, name: str) -> Path:
    hooks = project / ".claude" / "hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    target = hooks / f"{name}.sh"
    shutil.copy(TEMPLATES / f"{name}.sh.template", target)
    target.chmod(0o755)
    return target


def payload(**fields) -> bytes:
    body = {"hook_event_name": "PreToolUse", "session_id": "evalsession"}
    body.update(fields)
    return json.dumps(body).encode("utf-8")


def deny_decision(text: str):
    """The parsed permissionDecision, or None when stdout is not a deny object."""
    stripped = text.strip()
    if not stripped:
        return None
    try:
        data = json.loads(stripped)
    except ValueError:
        return "unparseable"
    if not isinstance(data, dict):
        return "unparseable"
    return (data.get("hookSpecificOutput") or {}).get("permissionDecision")


def check_gate(
    rec: Recorder,
    label: str,
    run,
    allowed_rc=(0,),
    expect: str | None = None,
) -> None:
    """Invariants every gate owes its caller, whatever verdict it reaches.

    ``expect`` is "deny", "allow", or None to assert shape only.
    """
    rec.add(SUITE, f"{label} exits {'/'.join(str(c) for c in allowed_rc)}", run.rc in allowed_rc, f"rc={run.rc}")
    rec.add(SUITE, f"{label} raises no traceback", TRACEBACK not in run.stderr_text, run.stderr_text[-200:])
    rec.add(SUITE, f"{label} emits no raw control bytes on stdout", not control_chars(run.out))
    decision = deny_decision(run.text)
    rec.add(SUITE, f"{label} stdout is empty or one deny object", decision in (None, "deny"), str(decision))
    if expect == "deny":
        rec.add(SUITE, f"{label} denies", decision == "deny", f"decision={decision} stdout={run.text[:120]!r}")
    elif expect == "allow":
        rec.add(SUITE, f"{label} allows", decision is None, f"stdout={run.text[:120]!r}")


# --- enforce-scope.sh -------------------------------------------------------


def _worktree(root: Path, name: str):
    """A main checkout plus a linked worktree; the guard arms only in the latter."""
    main = build_project(root, name, features=canonical_features())
    git_commit_all(main.path)
    wt = root / f"{name}-wt"
    env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
    subprocess.run(
        ["git", "-C", str(main.path), "worktree", "add", "-q", "-b", f"{name}-branch", str(wt)],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    (wt / ".harness").mkdir(parents=True, exist_ok=True)
    install_gate(wt, "enforce-scope")
    install_gate(main.path, "enforce-scope")
    return main, wt


def run_enforce_scope(rec: Recorder, root: Path) -> None:
    main, wt = _worktree(root, "es")
    home = main.home
    hook = wt / ".claude" / "hooks" / "enforce-scope.sh"
    main_hook = main.path / ".claude" / "hooks" / "enforce-scope.sh"

    def fire(where: Path, script: Path, body: bytes, label: str, allowed_rc=(0,), expect=None):
        run = run_hook(script, where, home, stdin=body, cwd=where)
        check_gate(rec, f"enforce-scope[{label}]", run, allowed_rc, expect)
        return run

    # Arming is the single point the whole guard hangs on.
    lead_owned = payload(tool_name="Edit", tool_input={"file_path": ".harness/features.json"})
    fire(wt, hook, lead_owned, "worktree/lead-owned", expect="deny")
    fire(main.path, main_hook, lead_owned, "main-checkout/lead-owned", expect="allow")
    fire(wt, hook, payload(tool_name="Edit", tool_input={"file_path": "src/app.py"}), "worktree/ordinary", expect="allow")

    # A path that resolves to the protected file by leaving the project and
    # coming back. The prefix strip runs before normpath, so this is the
    # spelling most likely to slip past the case match.
    escape = f"{wt}/../{wt.name}/.harness/features.json"
    fire(wt, hook, payload(tool_name="Edit", tool_input={"file_path": escape}), "worktree/escape-and-return", expect="deny")

    # Absolute spelling of the same file must behave like the relative one.
    fire(
        wt,
        hook,
        payload(tool_name="Edit", tool_input={"file_path": str(wt / ".harness" / "features.json")}),
        "worktree/absolute",
        expect="deny",
    )

    # The mld prefix, written both ways. Same destination directory, so the
    # two spellings must reach the same verdict.
    fire(wt, hook, payload(tool_name="Bash", tool_input={"command": "cp x .harness/mld/"}), "bash/mld-slash", expect="deny")
    fire(wt, hook, payload(tool_name="Bash", tool_input={"command": "cp x .harness/mld"}), "bash/mld-bare", expect="deny")

    fire(
        wt,
        hook,
        payload(tool_name="Bash", tool_input={"command": "echo x > .harness/features.json"}),
        "bash/redirect",
        expect="deny",
    )
    fire(wt, hook, payload(tool_name="Bash", tool_input={"command": "echo x > src/out.txt"}), "bash/ordinary", expect="allow")

    # A real violation hidden behind a segment whose ANSI-C decoding is the
    # documented crash surface: the per-segment except must still deny.
    fire(
        wt,
        hook,
        payload(tool_name="Bash", tool_input={"command": "sed -i $'\\xdf' f ; echo x > .harness/features.json"}),
        "bash/decoder-crash-plus-violation",
        expect="deny",
    )

    # Size: the deny must survive a command large enough to stress argv limits.
    big = "echo x > .harness/features.json ; " + "echo " + ("f" * 400000)
    fire(wt, hook, payload(tool_name="Bash", tool_input={"command": big}), "bash/oversized", expect="deny")

    # Post-parse extraction failure is the documented fail-closed path: exit 2,
    # message on stderr, nothing on stdout.
    surrogate = b'{"hook_event_name":"PreToolUse","session_id":"s","tool_input":{"file_path":"src/\\ud800.txt"}}'
    run = run_hook(hook, wt, home, stdin=surrogate, cwd=wt)
    check_gate(rec, "enforce-scope[surrogate-file_path]", run, allowed_rc=(0, 2))
    rec.add(SUITE, "enforce-scope[surrogate-file_path] never silently allows", run.rc == 2 or deny_decision(run.text) == "deny", f"rc={run.rc} stdout={run.text[:80]!r}")

    # Malformed envelopes must not crash the guard.
    for label, body in [
        ("truncated", b'{"tool_input":'),
        ("array-envelope", b"[]"),
        ("null-tool-input", b'{"tool_input":null}'),
        ("empty", b""),
    ]:
        run = run_hook(hook, wt, home, stdin=body, cwd=wt)
        check_gate(rec, f"enforce-scope[{label}]", run, allowed_rc=(0, 2))

    # The dashboard log is the only file this hook writes; a hostile session_id
    # must not steer it out of .harness/dashboard/.
    hostile = json.dumps(
        {"hook_event_name": "PreToolUse", "session_id": "../../escape", "tool_input": {"file_path": "src/a.py"}}
    ).encode()
    before = _tree(wt)
    run_hook(hook, wt, home, stdin=hostile, cwd=wt, env_extra={"VV_HARNESS_DASHBOARD": "1"})
    new = _tree(wt) - before
    outside = [p for p in new if not p.startswith(".harness/dashboard/")]
    rec.add(SUITE, "enforce-scope[hostile session_id] writes only inside .harness/dashboard/", not outside, str(sorted(outside)[:4]))


def _tree(root: Path) -> set:
    out = set()
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            out.add(os.path.relpath(os.path.join(dirpath, name), root))
    return out


# --- verify-git-identity.sh -------------------------------------------------


def run_verify_git_identity(rec: Recorder, root: Path) -> None:
    def project(name, identity, configure=("Fixture User", "fixture@example.com")):
        proj = build_project(
            root,
            name,
            features=canonical_features(),
            harness_json={"version": "6.0.0", "git_identity": identity},
        )
        if configure:
            env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
            for key, value in zip(("user.name", "user.email"), configure):
                subprocess.run(
                    ["git", "-C", str(proj.path), "config", key, value],
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
        install_gate(proj.path, "verify-git-identity")
        return proj

    matching = {"user_name": "Fixture User", "user_email": "fixture@example.com"}
    good = project("vgi-match", matching)
    hook = good.path / ".claude" / "hooks" / "verify-git-identity.sh"

    run = run_hook(hook, good.path, good.home, stdin=payload(tool_input={"command": "git push"}), cwd=good.path)
    check_gate(rec, "verify-git-identity[match]", run, allowed_rc=(0,), expect="allow")

    mismatched = project("vgi-mismatch", {"user_name": "Someone Else", "user_email": "other@example.com"})
    mhook = mismatched.path / ".claude" / "hooks" / "verify-git-identity.sh"
    for label, command in [
        ("space", "git push"),
        ("tab", "git\tpush"),
        ("multi-space", "git   push"),
        ("env-prefix", "GIT_DIR=x git push"),
        ("clone", "git clone https://example.com/x.git"),
    ]:
        run = run_hook(mhook, mismatched.path, mismatched.home, stdin=payload(tool_input={"command": command}), cwd=mismatched.path)
        check_gate(rec, f"verify-git-identity[mismatch/{label}]", run, allowed_rc=(0, 2))
        rec.add(
            SUITE,
            f"verify-git-identity[mismatch/{label}] blocks the push",
            run.rc == 2,
            f"rc={run.rc}",
        )

    # A newline in user_name shifts the fixed-line-index recovery of
    # user_email, so the hook compares against a value that appears nowhere in
    # harness.json. Blocking here is correct -- git cannot store a name
    # containing a newline, so the identities genuinely differ -- but the
    # expected email it names must be the configured one.
    forged = project(
        "vgi-newline",
        {"user_name": "Fixture User\nattacker@example.com", "user_email": "fixture@example.com"},
        configure=("Fixture User\nattacker@example.com", "fixture@example.com"),
    )
    fhook = forged.path / ".claude" / "hooks" / "verify-git-identity.sh"
    run = run_hook(fhook, forged.path, forged.home, stdin=payload(tool_input={"command": "git push"}), cwd=forged.path)
    check_gate(rec, "verify-git-identity[newline-identity]", run, allowed_rc=(0, 2))
    expected_block = run.stderr_text.split("Current:")[0]
    expected_emails = re.findall(r"<([^>]*)>", expected_block)
    rec.add(
        SUITE,
        "verify-git-identity[newline-identity] expects the configured user_email",
        expected_emails == ["fixture@example.com"] or run.rc == 0,
        f"rc={run.rc} expected_emails={expected_emails} stderr={run.stderr_text[:200]!r}",
    )
    rec.add(
        SUITE,
        "verify-git-identity[newline-identity] names the configured email in its expectation",
        "fixture@example.com" in run.stderr_text.split("Current:")[0] or run.rc == 0,
        f"rc={run.rc} stderr={run.stderr_text[:200]!r}",
    )

    # Degenerate harness.json shapes are documented fail-open.
    for label, harness in [("array", "[]"), ("empty", ""), ("no-identity", '{"version":"6.0.0"}')]:
        proj = build_project(root, f"vgi-{label}", features=canonical_features(), harness_json=harness)
        install_gate(proj.path, "verify-git-identity")
        hk = proj.path / ".claude" / "hooks" / "verify-git-identity.sh"
        run = run_hook(hk, proj.path, proj.home, stdin=payload(tool_input={"command": "git push"}), cwd=proj.path)
        check_gate(rec, f"verify-git-identity[harness-{label}]", run, allowed_rc=(0,), expect="allow")


# --- verify-task-quality.sh -------------------------------------------------

INIT_SH_PASS = """#!/usr/bin/env bash
case "$1" in
  smoke_test) exit 0 ;;
  focused_test) exit 0 ;;
  full_test) exit 0 ;;
  *) exit 0 ;;
esac
"""


def run_verify_task_quality(rec: Recorder, root: Path) -> None:
    def project(name, features, init=INIT_SH_PASS):
        proj = build_project(root, name, features=features)
        (proj.path / ".harness" / "init.sh").write_text(init, encoding="utf-8")
        (proj.path / ".harness" / "init.sh").chmod(0o755)
        install_gate(proj.path, "verify-task-quality")
        shutil.copy(STATE_MODULE, proj.path / ".claude" / "hooks" / "harness_state.py")
        return proj

    def task_payload(feature_id="F002"):
        return json.dumps(
            {
                "hook_event_name": "TaskCompleted",
                "session_id": "evalsession",
                "task": {"subject": f"{feature_id}: do the thing", "metadata": {"feature_id": feature_id}},
            }
        ).encode()

    healthy = project("vtq-healthy", canonical_features())
    hook = healthy.path / ".claude" / "hooks" / "verify-task-quality.sh"
    run = run_hook(hook, healthy.path, healthy.home, stdin=task_payload(), cwd=healthy.path)
    check_gate(rec, "verify-task-quality[healthy]", run, allowed_rc=(0, 2))
    rec.add(SUITE, "verify-task-quality[healthy] accepts a passing task", run.rc == 0, f"rc={run.rc} stderr={run.stderr_text[-160:]!r}")

    # A gate that crashes is a gate that stopped enforcing: exit 1 is neither
    # accept nor block, and Claude Code reads it as "not a block".
    for label, features in [
        ("corrupt-features", "{ not json"),
        ("array-features", "[]"),
        ("null-features", "null"),
        ("non-dict-entries", '{"features": ["F001", 42, null]}'),
    ]:
        proj = project(f"vtq-{label}", features)
        hk = proj.path / ".claude" / "hooks" / "verify-task-quality.sh"
        run = run_hook(hk, proj.path, proj.home, stdin=task_payload(), cwd=proj.path)
        rec.add(SUITE, f"verify-task-quality[{label}] never exits 1", run.rc in (0, 2), f"rc={run.rc}")
        rec.add(SUITE, f"verify-task-quality[{label}] raises no traceback", TRACEBACK not in run.stderr_text, run.stderr_text[-200:])
        rec.add(
            SUITE,
            f"verify-task-quality[{label}] still runs the smoke stage",
            "Stage 1" in run.stderr_text,
            run.stderr_text[:160],
        )

    # Feature text must not be able to forge a verdict. These fields are
    # recovered by fixed line index, so an embedded newline shifts them.
    newline_feats = canonical_features()
    newline_feats[1]["qa_binding"] = "unit\ntest"
    newline_feats[1]["proof"] = {"evidence_type": "log\nfile"}
    proj = project("vtq-newline-fields", newline_feats)
    hk = proj.path / ".claude" / "hooks" / "verify-task-quality.sh"
    run = run_hook(hk, proj.path, proj.home, stdin=task_payload(), cwd=proj.path)
    rec.add(SUITE, "verify-task-quality[newline-fields] never exits 1", run.rc in (0, 2), f"rc={run.rc}")
    rec.add(
        SUITE,
        "verify-task-quality[newline-fields] is not flipped to a rejection by feature text",
        run.rc == 0,
        f"rc={run.rc} stderr={run.stderr_text[-200:]!r}",
    )

    # A hostile feature id reaches last_gate.json keys and harness_state argv.
    hostile = project("vtq-hostile-id", canonical_features())
    hk = hostile.path / ".claude" / "hooks" / "verify-task-quality.sh"
    before = _tree(hostile.path)
    body = json.dumps(
        {
            "hook_event_name": "TaskCompleted",
            "session_id": "evalsession",
            "task": {"subject": "x", "metadata": {"feature_id": "../../../etc/passwd"}},
        }
    ).encode()
    run = run_hook(hk, hostile.path, hostile.home, stdin=body, cwd=hostile.path)
    rec.add(SUITE, "verify-task-quality[hostile-id] never exits 1", run.rc in (0, 2), f"rc={run.rc}")
    new = _tree(hostile.path) - before
    outside = [p for p in new if not p.startswith(".harness/")]
    rec.add(SUITE, "verify-task-quality[hostile-id] writes nothing outside .harness/", not outside, str(sorted(outside)[:4]))
    gate_file = hostile.path / ".harness" / "last_gate.json"
    if gate_file.is_file():
        try:
            json.loads(gate_file.read_text())
            ok = True
        except ValueError:
            ok = False
        rec.add(SUITE, "verify-task-quality[hostile-id] leaves last_gate.json valid JSON", ok)

    # Malformed stdin is documented fail-open, and must not crash.
    for label, body in [("garbage", b"not json"), ("array", b"[]"), ("empty", b"")]:
        run = run_hook(hook, healthy.path, healthy.home, stdin=body, cwd=healthy.path)
        rec.add(SUITE, f"verify-task-quality[stdin-{label}] never exits 1", run.rc in (0, 2), f"rc={run.rc}")
        rec.add(
            SUITE,
            f"verify-task-quality[stdin-{label}] raises no traceback",
            TRACEBACK not in run.stderr_text,
            run.stderr_text[-160:],
        )


# --- commit-gate.sh ---------------------------------------------------------


def run_commit_gate(rec: Recorder, root: Path) -> None:
    def project(name, staged: dict):
        proj = build_project(root, name, features=canonical_features())
        git_commit_all(proj.path)
        env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
        for rel, content in staged.items():
            target = proj.path / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            subprocess.run(
                ["git", "-C", str(proj.path), "add", rel],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        install_gate(proj.path, "commit-gate")
        return proj

    clean = project("cg-clean", {"src/app.py": "print('hello')\n"})
    hook = clean.path / ".claude" / "hooks" / "commit-gate.sh"

    def fire(proj, label, command, expect=None):
        hk = proj.path / ".claude" / "hooks" / "commit-gate.sh"
        run = run_hook(hk, proj.path, proj.home, stdin=payload(tool_input={"command": command}), cwd=proj.path)
        check_gate(rec, f"commit-gate[{label}]", run, allowed_rc=(0,), expect=expect)
        return run

    fire(clean, "plain-commit", 'git commit -m "add app"', expect="allow")
    fire(clean, "non-git", "ls -la", expect="allow")
    # F109: a redirection after the subcommand is not a pathspec.
    fire(clean, "no-edit-redirect", "git commit --no-edit 2>&1", expect="allow")
    # Staging inside the commit is the gate's core rule.
    fire(clean, "compound-stage-commit", 'git add . && git commit -m "x"', expect="deny")
    fire(clean, "commit-dash-a", 'git commit -a -m "x"', expect="deny")

    secret = project(
        "cg-secret",
        {"src/config.py": 'API_KEY = "AKIAIOSFODNN7EXAMPLEKEY123"\n'},
    )
    fire(secret, "staged-secret", 'git commit -m "config"', expect="deny")

    exempt = project("cg-exempt", {"prod.env.example": 'API_KEY = "AKIAIOSFODNN7EXAMPLEKEY123"\n'})
    fire(exempt, "env-example-exempt", 'git commit -m "sample"', expect="allow")

    url_creds = project("cg-url", {"docs/setup.md": "clone https://user:hunter2pass@example.com/x.git\n"})
    fire(url_creds, "url-credentials", 'git commit -m "docs"', expect="deny")

    # Malformed envelopes: two neighbouring shapes reach opposite verdicts by
    # design (rc 2 fails open, rc 1 fails closed). Both must be crash-free and
    # well-formed, which is what pins the split.
    for label, body in [
        ("truncated", b'{"tool_input":'),
        ("array-envelope", b"[]"),
        ("null-tool-input", b'{"tool_input":null}'),
        ("empty", b""),
    ]:
        run = run_hook(hook, clean.path, clean.home, stdin=body, cwd=clean.path)
        check_gate(rec, f"commit-gate[{label}]", run, allowed_rc=(0,))

    # A lone surrogate in the command is the documented fail-closed path.
    surrogate = b'{"hook_event_name":"PreToolUse","session_id":"s","tool_input":{"command":"git commit -a -m \\"wip\\ud800\\""}}'
    run = run_hook(hook, clean.path, clean.home, stdin=surrogate, cwd=clean.path)
    check_gate(rec, "commit-gate[surrogate-command]", run, allowed_rc=(0,), expect="deny")

    # A degenerate timeout must not silently disable secret scanning without
    # some visible signal; at minimum it must not crash.
    hk = secret.path / ".claude" / "hooks" / "commit-gate.sh"
    for label, value in [("zero", "0"), ("negative", "-1"), ("non-numeric", "abc")]:
        run = run_hook(
            hk,
            secret.path,
            secret.home,
            stdin=payload(tool_input={"command": 'git commit -m "x"'}),
            cwd=secret.path,
            env_extra={"COMMIT_GATE_DIFF_TIMEOUT": value},
        )
        check_gate(rec, f"commit-gate[timeout-{label}]", run, allowed_rc=(0,))

    # The dashboard log must stay inside .harness/dashboard/.
    before = _tree(clean.path)
    run_hook(
        hook,
        clean.path,
        clean.home,
        stdin=json.dumps(
            {"hook_event_name": "PreToolUse", "session_id": "../../escape", "tool_input": {"command": "git status"}}
        ).encode(),
        cwd=clean.path,
        env_extra={"VV_HARNESS_DASHBOARD": "1"},
    )
    outside = [p for p in _tree(clean.path) - before if not p.startswith(".harness/dashboard/")]
    rec.add(SUITE, "commit-gate[hostile session_id] writes only inside .harness/dashboard/", not outside, str(sorted(outside)[:4]))


# --- doctor.py --------------------------------------------------------------


def run_doctor(rec: Recorder, root: Path) -> None:
    bindir = make_bin(root)

    def doctor(project: Path, home: Path, args=(), timeout=60, plugin_root=str(REPO_ROOT)):
        env = {
            "PATH": f"{bindir}:{os.environ.get('PATH', '/usr/bin:/bin')}",
            "HOME": str(home),
            "LC_ALL": "C",
            "LANG": "C",
            "TZ": "UTC",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
        }
        if plugin_root:
            env["CLAUDE_PLUGIN_ROOT"] = plugin_root
        try:
            proc = subprocess.run(
                ["python3", str(DOCTOR), *args, str(project)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=str(project),
                env=env,
                timeout=timeout,
            )
            return proc.returncode, proc.stdout, proc.stderr
        except subprocess.TimeoutExpired:
            return 124, b"", b"timeout"

    def check(label, project: Path, home: Path, args=(), plugin_root=str(REPO_ROOT)):
        rc, out, err = doctor(project, home, args, plugin_root=plugin_root)
        text = out.decode("utf-8", "replace")
        errtext = err.decode("utf-8", "replace")
        rec.add(SUITE, f"doctor[{label}] exits 0/1/2", rc in (0, 1, 2), f"rc={rc}")
        rec.add(SUITE, f"doctor[{label}] raises no traceback", TRACEBACK not in errtext, errtext[-220:])
        rec.add(SUITE, f"doctor[{label}] emits no raw control bytes", not control_chars(out))
        lines = [l for l in text.split("\n") if l.strip()]
        well_formed = not lines or all(
            l.startswith(("FINDING: ", "  fix: ", "INFO: ", "WARN: ")) or l.strip() == "healthy" for l in lines
        )
        rec.add(SUITE, f"doctor[{label}] prints a well-formed report", well_formed, text[:200])
        return rc, text

    healthy = build_project(root, "dr-healthy", features=canonical_features())
    git_commit_all(healthy.path)
    check("healthy-project", healthy.path, healthy.home)

    # json.load succeeding is not proof the document is a dict. Each of these
    # parses cleanly and then meets a .get() on a list or a string.
    shapes = {
        "features-array": ("features.json", "[]"),
        "features-null": ("features.json", "null"),
        "features-string": ("features.json", '{"features": "F001"}'),
        "features-non-dict-entries": ("features.json", '{"features": ["F001", 42, null]}'),
        "harness-array": ("harness.json", "[]"),
        "harness-string": ("harness.json", '"6.0.0"'),
    }
    for label, (name, content) in shapes.items():
        proj = build_project(root, f"dr-{label}", features=canonical_features())
        (proj.path / ".harness" / name).write_text(content, encoding="utf-8")
        git_commit_all(proj.path)
        check(label, proj.path, proj.home)

    # settings.json parses but 'hooks' is not a dict.
    for label, settings in [("settings-hooks-list", '{"hooks": []}'), ("settings-hooks-string", '{"hooks": "none"}')]:
        proj = build_project(root, f"dr-{label}", features=canonical_features())
        (proj.path / ".claude").mkdir(parents=True, exist_ok=True)
        (proj.path / ".claude" / "settings.json").write_text(settings, encoding="utf-8")
        git_commit_all(proj.path)
        check(label, proj.path, proj.home)

    # Presence is not readability: these are all guarded by isfile() only.
    proj = build_project(root, "dr-unreadable", features=canonical_features())
    (proj.path / ".gitignore").write_bytes(b"\xff\xfe not utf-8 \x00\n")
    (proj.path / ".harness" / "context_summary.md").write_bytes(b"\xff\xfe\x00 binary\n")
    git_commit_all(proj.path)
    check("unreadable-files", proj.path, proj.home)

    # Untrusted feature text reaching the report.
    hostile = canonical_features()
    hostile[0]["test_file"] = "tests/\x1b[2Jpwned\nFINDING: forged\n.py"
    hostile[0]["id"] = "F001\nFINDING: forged"
    proj = build_project(root, "dr-hostile-text", features=hostile, make_test_files=False)
    git_commit_all(proj.path)
    rc, text = check("hostile-feature-text", proj.path, proj.home)
    forged = [l for l in text.split("\n") if l.startswith("FINDING: forged")]
    rec.add(SUITE, "doctor[hostile-feature-text] cannot be made to forge a FINDING line", not forged, str(forged[:2]))

    # --fix must be safe and idempotent.
    fixable = build_project(root, "dr-fixable", features=canonical_features())
    git_commit_all(fixable.path)
    check("fix-first-pass", fixable.path, fixable.home, args=("--fix",))
    rc_second, text_second = check("fix-idempotent", fixable.path, fixable.home, args=("--fix",))
    rc_report, text_report = check("fix-then-report", fixable.path, fixable.home)
    rec.add(
        SUITE,
        "doctor[--fix] converges: a second --fix reports the same state as a plain run",
        text_second.strip() == text_report.strip(),
        f"second={text_second[:120]!r} report={text_report[:120]!r}",
    )

    # A fixer that cannot write is the case doctor.py never handles: apply_fix's
    # return value is discarded and the call is not wrapped, so a PermissionError
    # from a read-only target propagates out of a health check whose entire
    # contract is to report problems rather than become one.
    readonly = build_project(root, "dr-fix-readonly", features=canonical_features())
    (readonly.path / ".gitignore").write_text("build/\n", encoding="utf-8")
    (readonly.path / ".gitignore").chmod(0o444)
    git_commit_all(readonly.path)
    try:
        check("fix-readonly-gitignore", readonly.path, readonly.home, args=("--fix",))
    finally:
        (readonly.path / ".gitignore").chmod(0o644)

    readonly_dir = build_project(root, "dr-fix-readonly-dir", features=canonical_features())
    claude_dir = readonly_dir.path / ".claude"
    claude_dir.mkdir(parents=True, exist_ok=True)
    (claude_dir / "settings.json").write_text("{}", encoding="utf-8")
    git_commit_all(readonly_dir.path)
    claude_dir.chmod(0o555)
    try:
        check("fix-readonly-claude-dir", readonly_dir.path, readonly_dir.home, args=("--fix",))
    finally:
        claude_dir.chmod(0o755)

    # --fix with no plugin root: the fixers that copy shipped files have no
    # source to copy from, which must be reported, not raised.
    rootless = build_project(root, "dr-fix-no-plugin-root", features=canonical_features())
    git_commit_all(rootless.path)
    check("fix-no-plugin-root", rootless.path, rootless.home, args=("--fix",), plugin_root="")

    # A plugin root that exists but is empty: every source path a fixer wants is
    # missing, so shutil.copy has nothing to open.
    empty_plugin = root / "empty-plugin"
    empty_plugin.mkdir(parents=True, exist_ok=True)
    hollow = build_project(root, "dr-fix-empty-plugin", features=canonical_features())
    git_commit_all(hollow.path)
    check("fix-empty-plugin-root", hollow.path, hollow.home, args=("--fix",), plugin_root=str(empty_plugin))

    # A plugin whose validator hangs must not hang the health check.
    slow_plugin = root / "slow-plugin"
    (slow_plugin / "scripts").mkdir(parents=True, exist_ok=True)
    (slow_plugin / "scripts" / "validate-features.py").write_text(
        "import time\ntime.sleep(600)\n", encoding="utf-8"
    )
    proj = build_project(root, "dr-slow-validator", features=canonical_features())
    git_commit_all(proj.path)
    env = {
        "PATH": f"{bindir}:{os.environ.get('PATH', '/usr/bin:/bin')}",
        "HOME": str(proj.home),
        "LC_ALL": "C",
        "TZ": "UTC",
        "CLAUDE_PLUGIN_ROOT": str(slow_plugin),
    }
    try:
        proc = subprocess.run(
            ["python3", str(DOCTOR), str(proj.path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=str(proj.path),
            env=env,
            timeout=25,
        )
        terminated, rc = True, proc.returncode
    except subprocess.TimeoutExpired:
        terminated, rc = False, 124
    rec.add(SUITE, "doctor[hanging-validator] terminates within 25s", terminated, f"rc={rc}")


# --- harness_state.py concurrency ------------------------------------------


def run_state_concurrency(rec: Recorder, root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)

    def increment(path: str, cwd: Path):
        return subprocess.run(
            ["python3", str(STATE_MODULE), "increment-correction-cycles", path, "F001"],
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )

    def cycles(features_path: Path) -> int:
        data = json.loads(features_path.read_text())
        return data["features"][0].get("correction_cycles", 0)

    # Same spelling from every caller: the lock's baseline guarantee.
    proj = build_project(root, "hs-same-spelling", features=[feature("F001", status="in-progress")])
    features_path = proj.path / ".harness" / "features.json"
    n = 12
    with ThreadPoolExecutor(max_workers=n) as pool:
        results = [f.result() for f in [pool.submit(increment, str(features_path), proj.path) for _ in range(n)]]
    rec.add(
        SUITE,
        f"harness_state: {n} concurrent increments all report success",
        all(r.returncode == 0 for r in results),
        str(sorted({r.returncode for r in results})),
    )
    rec.add(
        SUITE,
        f"harness_state: {n} concurrent increments produce exactly {n}",
        cycles(features_path) == n,
        f"got {cycles(features_path)}",
    )

    # Mixed spellings of the same file. flock is keyed on the inode, not on the
    # path string, so every spelling here shares one lock and this must hold --
    # it is a regression guard against a future lock keyed on the argv string
    # (or on an in-process table), not a probe for a defect present today.
    proj = build_project(root, "hs-mixed-spelling", features=[feature("F001", status="in-progress")])
    features_path = proj.path / ".harness" / "features.json"
    spellings = [
        str(features_path),
        ".harness/features.json",
        "./.harness/features.json",
        str(proj.path / "." / ".harness" / "features.json"),
    ]
    calls = [spellings[i % len(spellings)] for i in range(n)]
    with ThreadPoolExecutor(max_workers=n) as pool:
        results = [f.result() for f in [pool.submit(increment, spelling, proj.path) for spelling in calls]]
    rec.add(
        SUITE,
        f"harness_state: {n} concurrent increments via mixed path spellings all report success",
        all(r.returncode == 0 for r in results),
        str(sorted({r.returncode for r in results})),
    )
    rec.add(
        SUITE,
        f"harness_state: {n} concurrent increments via mixed path spellings produce exactly {n}",
        cycles(features_path) == n,
        f"got {cycles(features_path)} -- a shortfall means the lock stopped being inode-keyed",
    )

    # A hand-edited correction_cycles must produce a diagnostic, not a traceback.
    proj = build_project(
        root,
        "hs-string-cycles",
        features=[feature("F001", status="in-progress", correction_cycles="3")],
    )
    result = increment(str(proj.path / ".harness" / "features.json"), proj.path)
    rec.add(
        SUITE,
        "harness_state: a non-numeric correction_cycles raises no traceback",
        TRACEBACK not in result.stderr.decode("utf-8", "replace"),
        result.stderr.decode("utf-8", "replace")[-200:],
    )
    rec.add(
        SUITE,
        "harness_state: a non-numeric correction_cycles exits non-zero",
        result.returncode != 0,
        f"rc={result.returncode}",
    )


def run(rec: Recorder, root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    run_enforce_scope(rec, root / "enforce-scope")
    run_verify_git_identity(rec, root / "verify-git-identity")
    run_verify_task_quality(rec, root / "verify-task-quality")
    run_commit_gate(rec, root / "commit-gate")
    run_doctor(rec, root / "doctor")
    run_state_concurrency(rec, root / "state")
