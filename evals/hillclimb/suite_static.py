"""Static suite: the shipped plugin's own contracts.

A harness ships instructions, not a program: its failure mode is a pointer to a
file that does not exist, a skill the model cannot load because its frontmatter
is malformed, or a rule no shipped file ever names. Those are as fatal to an
agent as a syntax error is to a compiler, and are checked here mechanically.
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

from harnesslib import REPO_ROOT, Recorder

SUITE = "static"

SHIPPED_DIRS = ["rules", "skills", "agents", "hooks", "schemas", "scripts", "workflows", "templates"]
CONTENT_GLOBS = [
    "rules/*.md",
    "agents/*.md",
    "skills/*/*.md",
    "hooks/*.sh",
    "hooks/hooks.json",
    "templates/CLAUDE.md",
]

# A leading path separator or word character means the token is a suffix of a
# longer path (".claude/hooks/x.sh") or a URL, not a repo-relative reference.
PATH_REF = re.compile(
    r"(?<![A-Za-z0-9._/-])(?:" + "|".join(SHIPPED_DIRS + ["evals", "docs", "test"]) + r")/"
    r"[A-Za-z0-9._/-]+\.(?:md|sh|py|js|json|tmpl|template|html|css)\b"
)

FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
# Claude Code truncates a skill or agent description past this length.
DESCRIPTION_CAP = 1024


def _frontmatter(path: Path) -> dict | None:
    m = FRONTMATTER.match(path.read_text(encoding="utf-8", errors="replace"))
    if not m:
        return None
    fields: dict = {}
    key = None
    for line in m.group(1).split("\n"):
        if re.match(r"^[A-Za-z0-9_-]+:", line):
            key, _, value = line.partition(":")
            fields[key.strip()] = value.strip().strip("'\"")
        elif key and line.startswith((" ", "\t")):
            fields[key] = (fields[key] + " " + line.strip()).strip()
    return fields


def check_manifests(rec: Recorder) -> str:
    plugin_path = REPO_ROOT / ".claude-plugin" / "plugin.json"
    version = ""
    try:
        plugin = json.loads(plugin_path.read_text())
        rec.add(SUITE, "plugin.json parses", True)
    except Exception as exc:
        rec.add(SUITE, "plugin.json parses", False, str(exc))
        plugin = {}
    for key in ("name", "version", "description", "author"):
        rec.add(SUITE, f"plugin.json declares {key}", bool(plugin.get(key)))
    version = str(plugin.get("version", ""))
    rec.add(SUITE, "plugin.json version is semver", bool(re.fullmatch(r"\d+\.\d+\.\d+", version)), version)

    market_path = REPO_ROOT / ".claude-plugin" / "marketplace.json"
    try:
        market = json.loads(market_path.read_text())
        rec.add(SUITE, "marketplace.json parses", True)
    except Exception as exc:
        rec.add(SUITE, "marketplace.json parses", False, str(exc))
        market = {}
    entries = market.get("plugins") or []
    rec.add(SUITE, "marketplace.json lists the plugin", bool(entries))
    rec.add(
        SUITE,
        "marketplace.json names the same plugin as plugin.json",
        any(e.get("name") == plugin.get("name") for e in entries),
    )
    for entry in entries:
        source = entry.get("source")
        if isinstance(source, str) and source.startswith("./"):
            rec.add(
                SUITE,
                f"marketplace source {source} exists",
                (REPO_ROOT / source).exists(),
            )

    changelog = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8", errors="replace")
    rec.add(
        SUITE,
        f"CHANGELOG.md documents the shipped version {version}",
        bool(version) and re.search(rf"^#+ .*{re.escape(version)}\b", changelog, re.M) is not None,
    )
    return version


def check_hooks_json(rec: Recorder) -> None:
    path = REPO_ROOT / "hooks" / "hooks.json"
    try:
        data = json.loads(path.read_text())
        rec.add(SUITE, "hooks.json parses", True)
    except Exception as exc:
        rec.add(SUITE, "hooks.json parses", False, str(exc))
        return
    refs = re.findall(r"\$\{?CLAUDE_PLUGIN_ROOT\}?\\?\"?/([A-Za-z0-9._/-]+)", json.dumps(data))
    rec.add(SUITE, "hooks.json references at least one hook script", bool(refs))
    for ref in sorted(set(refs)):
        rec.add(SUITE, f"hooks.json target {ref} exists", (REPO_ROOT / ref).is_file())


def check_scripts(rec: Recorder) -> None:
    for sh in sorted(REPO_ROOT.glob("hooks/**/*.sh")) + sorted(REPO_ROOT.glob("scripts/*.sh")):
        rel = sh.relative_to(REPO_ROOT)
        proc = subprocess.run(["bash", "-n", str(sh)], capture_output=True)
        rec.add(SUITE, f"{rel} parses as bash", proc.returncode == 0, proc.stderr.decode()[:200])
        rec.add(SUITE, f"{rel} is executable", sh.stat().st_mode & 0o111 != 0)

    py_files = (
        sorted(REPO_ROOT.glob("hooks/**/*.py"))
        + sorted(REPO_ROOT.glob("scripts/*.py"))
        + sorted(REPO_ROOT.glob("skills/**/*.py"))
        + sorted(REPO_ROOT.glob("skills/**/*.py.template"))
    )
    for py in py_files:
        rel = py.relative_to(REPO_ROOT)
        try:
            compile(py.read_text(encoding="utf-8"), str(rel), "exec")
            ok, detail = True, ""
        except SyntaxError as exc:
            ok, detail = False, f"line {exc.lineno}: {exc.msg}"
        rec.add(SUITE, f"{rel} compiles", ok, detail)

    for js in sorted(REPO_ROOT.glob("workflows/*.js")):
        rel = js.relative_to(REPO_ROOT)
        src = js.read_text(encoding="utf-8", errors="replace")
        rec.add(SUITE, f"{rel} has balanced braces", src.count("{") == src.count("}"))


def check_agents_and_skills(rec: Recorder) -> None:
    agents = sorted(REPO_ROOT.glob("agents/*.md"))
    rec.add(SUITE, "the plugin ships at least one agent", bool(agents))
    for agent in agents:
        rel = agent.relative_to(REPO_ROOT)
        fm = _frontmatter(agent)
        if not rec.add(SUITE, f"{rel} has YAML frontmatter", fm is not None):
            continue
        rec.add(SUITE, f"{rel} declares name and description", bool(fm.get("name") and fm.get("description")))
        rec.add(SUITE, f"{rel} name matches its filename", fm.get("name") == agent.stem, str(fm.get("name")))
        rec.add(
            SUITE,
            f"{rel} description fits the {DESCRIPTION_CAP}-char cap",
            len(fm.get("description", "")) <= DESCRIPTION_CAP,
            f"{len(fm.get('description', ''))} chars",
        )

    skills = sorted(REPO_ROOT.glob("skills/*/SKILL.md"))
    rec.add(SUITE, "the plugin ships at least one skill", bool(skills))
    for skill in skills:
        rel = skill.relative_to(REPO_ROOT)
        fm = _frontmatter(skill)
        if not rec.add(SUITE, f"{rel} has YAML frontmatter", fm is not None):
            continue
        rec.add(SUITE, f"{rel} declares name and description", bool(fm.get("name") and fm.get("description")))
        rec.add(SUITE, f"{rel} name matches its directory", fm.get("name") == skill.parent.name, str(fm.get("name")))
        rec.add(
            SUITE,
            f"{rel} description fits the {DESCRIPTION_CAP}-char cap",
            len(fm.get("description", "")) <= DESCRIPTION_CAP,
            f"{len(fm.get('description', ''))} chars",
        )


def _content_files() -> list[Path]:
    seen: list[Path] = []
    for pattern in CONTENT_GLOBS:
        seen.extend(sorted(REPO_ROOT.glob(pattern)))
    return seen


def check_references(rec: Recorder) -> None:
    """Every shipped-path reference in shipped content must resolve on disk."""
    for path in _content_files():
        rel = path.relative_to(REPO_ROOT)
        text = path.read_text(encoding="utf-8", errors="replace")
        dangling = sorted(
            {ref for ref in PATH_REF.findall(text) if not (REPO_ROOT / ref).exists()}
        )
        rec.add(SUITE, f"{rel} has no dangling file references", not dangling, ", ".join(dangling[:5]))


def check_reachability(rec: Recorder) -> None:
    """A rule or agent no shipped file names can never be retrieved by a session."""
    corpus = "\n".join(
        p.read_text(encoding="utf-8", errors="replace")
        for p in _content_files() + sorted(REPO_ROOT.glob("skills/*/*.md"))
    )
    for rule in sorted(REPO_ROOT.glob("rules/*.md")):
        rel = rule.relative_to(REPO_ROOT)
        rec.add(SUITE, f"{rel} is reachable from shipped content", str(rel) in corpus)
    for agent in sorted(REPO_ROOT.glob("agents/*.md")):
        name = agent.stem
        rec.add(
            SUITE,
            f"agents/{name}.md is named by a skill or rule",
            name in corpus,
        )


def check_orientation_contract(rec: Recorder) -> None:
    src = (REPO_ROOT / "hooks" / "session-start.sh").read_text(encoding="utf-8")
    # The non-injection guarantee: the telemetry directory name must never appear
    # in the hook that writes into model context.
    forbidden = "m" + "ld"
    rec.add(
        SUITE,
        "session-start.sh preserves the non-injection guarantee",
        f"/{forbidden}" not in src and f"{forbidden}/" not in src,
    )
    pointers = sorted(set(re.findall(r"rules/[A-Za-z0-9._-]+\.md", src)))
    rec.add(SUITE, "session-start.sh points at the rule set", len(pointers) >= 5, str(pointers))
    for ref in pointers:
        rec.add(SUITE, f"orientation pointer {ref} exists", (REPO_ROOT / ref).is_file())

    for schema in sorted(REPO_ROOT.glob("schemas/*.json")):
        rel = schema.relative_to(REPO_ROOT)
        try:
            json.loads(schema.read_text())
            ok, detail = True, ""
        except Exception as exc:
            ok, detail = False, str(exc)[:120]
        rec.add(SUITE, f"{rel} parses", ok, detail)


DOC_GLOBS = [
    "README.md",
    "INSTALL.md",
    "AGENTS.md",
    "CLAUDE.md",
    "docs/*.md",
    "analysis/*.md",
    "evals/*.md",
    "rules/*.md",
    "agents/*.md",
    "skills/*/*.md",
]
MD_LINK = re.compile(r"\]\(\s*(?!https?:|mailto:|#)([^)\s]+)")
HTML_ASSET = re.compile(r"(?:href|src)=\"(?!https?:|data:|mailto:|#)([^\"]+)\"")


def check_links(rec: Recorder) -> None:
    """A link a reader cannot follow is a documentation defect, not a typo."""
    docs: list[Path] = []
    for pattern in DOC_GLOBS:
        docs.extend(sorted(REPO_ROOT.glob(pattern)))
    for doc in docs:
        rel = doc.relative_to(REPO_ROOT)
        broken = []
        for target in MD_LINK.findall(doc.read_text(encoding="utf-8", errors="replace")):
            path = target.split("#", 1)[0]
            if not path or "<" in path or "$" in path or "{" in path:
                continue
            resolved = (doc.parent / path).resolve()
            if not resolved.exists():
                broken.append(target)
        rec.add(SUITE, f"{rel} has no broken links", not broken, ", ".join(sorted(set(broken))[:5]))

    for page in sorted(REPO_ROOT.glob("site/*.html")):
        rel = page.relative_to(REPO_ROOT)
        broken = []
        for target in HTML_ASSET.findall(page.read_text(encoding="utf-8", errors="replace")):
            path = target.split("#", 1)[0].split("?", 1)[0]
            if not path:
                continue
            if not (page.parent / path).resolve().exists():
                broken.append(target)
        rec.add(SUITE, f"{rel} resolves every local asset", not broken, ", ".join(sorted(set(broken))[:5]))


#: Documents that state the coverage gate as a number an agent is told to meet.
#: skills/harness-init/SKILL.md is deliberately excluded: it discusses threshold
#: POLICY and cites 95% and 99% side by side as examples of fixed thresholds to
#: reserve, so a single-value assertion there would be wrong, not protective.
COVERAGE_DOCS = [
    "rules/parallel-work.md",
    "skills/harness-continue/SKILL.md",
    "agents/feature-implementer.md",
    "agents/layer-implementer.md",
    "agents/reviewer.md",
    "templates/CLAUDE.md",
    "schemas/feature.schema.json",
]
COVERAGE_MENTION = re.compile(
    r"coverage[^.\n]{0,40}?(\d{2,3})\s?%|(\d{2,3})\s?%[^.\n]{0,20}?coverage", re.I
)

#: Documents that name the CLI version below which workflow mode is unavailable.
CLI_FLOOR_DOCS = [
    "skills/harness-continue/SKILL.md",
    "skills/harness-doctor/SKILL.md",
    "INSTALL.md",
]


def check_stated_constants(rec: Recorder) -> None:
    """Numbers the prose states must be the numbers the code enforces.

    A harness governs agents with instructions, so a threshold stated in a rule
    and a different one enforced in a gate is not a documentation nit: it is two
    contradictory instructions, and the agent has no way to tell which binds.
    Every expected value below is DERIVED from the enforcing code, so drift in
    either direction fails.
    """
    gate = (REPO_ROOT / "skills" / "harness-init" / "verify-task-quality.sh.template").read_text(
        encoding="utf-8"
    )
    match = re.search(r"^\s*target = (\d+)\s*$", gate, re.M)
    rec.add(SUITE, "the coverage gate's default is extractable from verify-task-quality", bool(match))
    if match:
        default = match.group(1)
        for rel in COVERAGE_DOCS:
            path = REPO_ROOT / rel
            if not rec.add(SUITE, f"{rel} exists to state the coverage gate", path.is_file()):
                continue
            stated = {
                m.group(1) or m.group(2)
                for m in COVERAGE_MENTION.finditer(path.read_text(encoding="utf-8", errors="replace"))
            }
            rec.add(
                SUITE,
                f"{rel} states the coverage gate the code enforces ({default}%)",
                stated == {default},
                f"stated={sorted(stated)} enforced={default}",
            )

    doctor_src = (REPO_ROOT / "skills" / "harness-doctor" / "doctor.py").read_text(encoding="utf-8")
    floor_match = re.search(r"WORKFLOW_MIN_CLI_VERSION = \((\d+), (\d+), (\d+)\)", doctor_src)
    rec.add(SUITE, "the workflow CLI floor is extractable from doctor.py", bool(floor_match))
    if floor_match:
        floor = ".".join(floor_match.groups())
        for rel in CLI_FLOOR_DOCS:
            path = REPO_ROOT / rel
            if not rec.add(SUITE, f"{rel} exists to state the CLI floor", path.is_file()):
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            rec.add(
                SUITE,
                f"{rel} names the workflow CLI floor doctor.py enforces ({floor})",
                floor in text,
                f"floor={floor}",
            )

    # The F106 skip protocol is a number agreed across three files: init.sh
    # emits it, verify-task-quality reads it as "not run", and doctor looks for
    # the marker text naming it. Any one of them drifting turns a skip into a
    # fake green or a real failure into an accepted skip.
    init_src = (REPO_ROOT / "skills" / "harness-init" / "init.sh.template").read_text(encoding="utf-8")
    emitted = set(re.findall(r"skipped \(exit (\d+)\)", init_src))
    consumed = set(re.findall(r"FOCUSED_RC\" -eq (\d+)", gate))
    marker = set(re.findall(r"skipped \(exit (\d+)\)", doctor_src))
    rec.add(SUITE, "init.sh emits exactly one skip exit code", len(emitted) == 1, str(sorted(emitted)))
    rec.add(SUITE, "verify-task-quality consumes exactly one skip exit code", len(consumed) == 1, str(sorted(consumed)))
    rec.add(
        SUITE,
        "the skip protocol's exit code agrees across init.sh, verify-task-quality, and doctor",
        bool(emitted) and emitted == consumed == marker,
        f"emitted={sorted(emitted)} consumed={sorted(consumed)} doctor={sorted(marker)}",
    )

    # session-start's own safety cap must stay under the platform cap its header
    # states, or the cap is decoration.
    start_src = (REPO_ROOT / "hooks" / "session-start.sh").read_text(encoding="utf-8")
    cap = re.search(r"ORIENTATION_CHAR_CAP=(\d+)", start_src)
    platform = re.search(r"capped at ([\d,]+) chars", start_src)
    rec.add(SUITE, "session-start declares an orientation cap", bool(cap))
    rec.add(SUITE, "session-start's header states the platform cap", bool(platform))
    if cap and platform:
        rec.add(
            SUITE,
            "session-start's safety cap stays under the platform cap it documents",
            int(cap.group(1)) < int(platform.group(1).replace(",", "")),
            f"cap={cap.group(1)} platform={platform.group(1)}",
        )

    # A README that denies the existence of something sitting next to it is a
    # navigational defect, not a nit: evals/README.md described the semi-manual
    # method and stated there was "no automated scoring pipeline" while this
    # suite ran in the same directory. Derived from the pipeline's own presence,
    # so deleting the suite and leaving the prose fails just as loudly.
    entrypoint = REPO_ROOT / "evals" / "hillclimb" / "run.py"
    readme_path = REPO_ROOT / "evals" / "README.md"
    if entrypoint.is_file() and rec.add(SUITE, "evals/README.md exists", readme_path.is_file()):
        readme = readme_path.read_text(encoding="utf-8", errors="replace")
        rec.add(SUITE, "evals/README.md names the automated suite", "evals/hillclimb/" in readme)
        rec.add(SUITE, "evals/README.md names how to run it", "autoresearch.sh" in readme)
        rec.add(
            SUITE,
            "evals/README.md does not deny the pipeline it ships beside",
            "no automated scoring pipeline" not in readme,
            "the README still claims no automated scoring pipeline exists",
        )


def run(rec: Recorder) -> None:
    check_manifests(rec)
    check_hooks_json(rec)
    check_scripts(rec)
    check_agents_and_skills(rec)
    check_references(rec)
    check_reachability(rec)
    check_orientation_contract(rec)
    check_links(rec)
    check_stated_constants(rec)
