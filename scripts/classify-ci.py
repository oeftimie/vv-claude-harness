#!/usr/bin/env python3
"""Choose the smallest safe CI mode for a set of changed repository paths."""

import argparse
import subprocess
import sys


METADATA_FILES = {
    ".harness/HARNESS_BACKLOG.md",
    ".harness/claude-progress.txt",
    ".harness/context_summary.md",
}
METADATA_PREFIXES = (
    ".harness/evidence/",
    ".harness/mld/",
    "clips/",
)
STATE_FILES = {".harness/features.json"}


def normalize(path):
    while path.startswith("./"):
        path = path[2:]
    return path


def is_metadata(path):
    return path in METADATA_FILES or path.startswith(METADATA_PREFIXES)


def classify(paths):
    normalized = [normalize(path) for path in paths if path]
    if not normalized:
        return "full"
    if any(path.startswith("/") for path in normalized):
        return "full"
    if any(path not in STATE_FILES and not is_metadata(path) for path in normalized):
        return "full"
    if any(path in STATE_FILES for path in normalized):
        return "state"
    return "metadata"


def diff_paths(repo, base, head, merge_base=False):
    if not base or not head or set(base) == {"0"}:
        return None
    revision = f"{base}...{head}" if merge_base else f"{base}..{head}"
    try:
        result = subprocess.run(
            ["git", "-C", repo, "diff", "--name-status", "-z", revision],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"classify-ci: cannot inspect diff; selecting full suite: {exc}", file=sys.stderr)
        return None

    fields = [part for part in result.stdout.split(b"\0") if part]
    paths = []
    index = 0
    while index < len(fields):
        status = fields[index].decode("ascii", "replace")
        index += 1
        path_count = 2 if status.startswith(("R", "C")) else 1
        if index + path_count > len(fields):
            print("classify-ci: malformed git diff; selecting full suite", file=sys.stderr)
            return None
        changed_paths = fields[index : index + path_count]
        index += path_count
        if status not in {"A", "M"}:
            print(
                f"classify-ci: change status {status} requires the full suite",
                file=sys.stderr,
            )
            return None
        paths.append(changed_paths[0].decode("utf-8", "surrogateescape"))
    return paths


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", help="base commit for git diff")
    parser.add_argument("--head", help="head commit for git diff")
    parser.add_argument(
        "--merge-base",
        action="store_true",
        help="classify changes since the base/head merge base (for pull requests)",
    )
    parser.add_argument("--repo", default=".", help="repository for git diff")
    parser.add_argument(
        "--path",
        action="append",
        default=[],
        help="classify an explicit path instead of reading a git diff (repeatable)",
    )
    args = parser.parse_args()
    if bool(args.base) != bool(args.head):
        parser.error("--base and --head must be supplied together")
    if args.merge_base and not args.base:
        parser.error("--merge-base requires --base and --head")
    if args.path and args.base:
        parser.error("--path cannot be combined with --base/--head")
    return args


def main():
    args = parse_args()
    paths = args.path
    if args.base:
        paths = diff_paths(args.repo, args.base, args.head, args.merge_base)
        if paths is None:
            print("full")
            return 0
    print(classify(paths))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
