#!/usr/bin/env bash
# statusLine command: renders live harness feature progress for the current project.
# Reads session JSON on stdin; locates .harness/ via workspace.project_dir (fallback: cwd).
# Prints one line, or an empty line when there is no harness or the input is malformed.
python3 -c '
import json, os, sys


def render():
    data = json.load(sys.stdin)
    root = (data.get("workspace") or {}).get("project_dir") or data.get("cwd") or ""
    harness = os.path.join(root, ".harness")
    if not root or not os.path.isdir(harness):
        return ""
    feats = json.load(open(os.path.join(harness, "features.json"))).get("features", [])
    passing = sum(1 for f in feats if f.get("status") == "passing")
    line = f"⬡ {passing}/{len(feats)} passing"
    wip = [str(f.get("id", "?")) for f in feats if f.get("status") == "in-progress"]
    if wip:
        line += " · " + ",".join(wip) + " in-progress"
    if os.path.exists(os.path.join(harness, "SESSION_INCOMPLETE")):
        line += " · ⚠ last session incomplete"
    return line


try:
    print(render())
except Exception:
    print("")
' 2>/dev/null || true
exit 0
