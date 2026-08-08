#!/usr/bin/env python3
"""Dashboard SSE server (F090): dependency-free, stdlib-only (Python 3.6+),
serving a live Server-Sent Events stream of one harness session's dashboard
event log (F088's .harness/dashboard/<session_id>.jsonl), plus the static
assets (F091) that render it, plus a GET /sessions listing (F099) of every
session log currently under dashboard_dir so the frontend can let the user
pick which one to watch instead of the server guessing.

Binds 127.0.0.1 only, always -- no bind-address override, no authentication.
Loopback-only access is the sole, deliberately accepted control (matching
this environment's existing trust model for local dev tooling; see this
repo's .harness/features.json F090 entry). --port overrides the port only.

If the target port is already bound, this fails fast (stderr message, exit
1) rather than silently falling back to another port. If .harness/dashboard/
or the target log file does not exist yet, the /events handler waits/polls
for it instead of erroring -- the rest of the server (static files) is not
blocked by this wait, since each connection runs in its own thread.

Plain foreground script: SIGINT/SIGTERM terminate it via Python's default
signal disposition. No daemon mode, no shutdown endpoint.
"""
import argparse
import json
import mimetypes
import os
import re
import socketserver
import subprocess
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

DEFAULT_PORT = 8765
POLL_INTERVAL = 0.2
STATIC_ROOT = os.path.realpath(os.path.dirname(os.path.abspath(__file__)))
SESSION_ID_DISALLOWED = re.compile(r"[^A-Za-z0-9._-]")


def sanitize_session_id(session_id):
    """Same rule as hooks/session-start.sh and hooks/dashboard-log.sh's
    `tr -cd 'A-Za-z0-9._-' | cut -c1-64`: strip everything outside that
    character set (in particular '/', ruling out path traversal), then cap
    the length at 64. None stays None (the CLI arg is optional)."""
    if session_id is None:
        return None
    return SESSION_ID_DISALLOWED.sub("", session_id)[:64]


def find_project_root():
    """The directory containing .harness/, resolved the same way as
    hooks/dashboard-log.sh and every gate script's own PROJECT_ROOT:
    CLAUDE_PROJECT_DIR when set, else git toplevel, falling back to cwd.
    A nohup-launched server (this one always is -- see skills/harness-init's
    own launch command) inherits its parent's environment, so
    CLAUDE_PROJECT_DIR is reachable here the same way it is in a hook."""
    env_root = os.environ.get("CLAUDE_PROJECT_DIR")
    if env_root:
        return env_root
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.decode("utf-8").strip()
    except Exception:
        pass
    return os.getcwd()


def pick_most_recent_jsonl(dashboard_dir):
    """Most-recently-modified *.jsonl under dashboard_dir, tie-broken by the
    lexicographically largest filename. None if the dir or a match is
    missing (the caller treats that as "keep waiting")."""
    if not os.path.isdir(dashboard_dir):
        return None
    names = [n for n in os.listdir(dashboard_dir) if n.endswith(".jsonl")]
    if not names:
        return None

    def sort_key(name):
        try:
            mtime = os.path.getmtime(os.path.join(dashboard_dir, name))
        except OSError:
            mtime = -1
        return (mtime, name)

    names.sort(key=sort_key)
    return os.path.join(dashboard_dir, names[-1])


def list_sessions(dashboard_dir):
    """All *.jsonl session logs under dashboard_dir as {session_id, mtime,
    size} dicts, most-recently-modified first (ties broken by the
    lexicographically largest session_id, matching pick_most_recent_jsonl's
    own tie-break). [] if the directory doesn't exist or holds no logs yet --
    callers (the /sessions endpoint) treat that as a normal empty state, not
    an error, so the frontend can render "no sessions yet" instead of
    guessing which log to tail (F099)."""
    if not os.path.isdir(dashboard_dir):
        return []
    entries = []
    for name in os.listdir(dashboard_dir):
        if not name.endswith(".jsonl"):
            continue
        full = os.path.join(dashboard_dir, name)
        try:
            stat = os.stat(full)
        except OSError:
            continue
        entries.append(
            {
                "session_id": name[: -len(".jsonl")],
                "mtime": stat.st_mtime,
                "size": stat.st_size,
            }
        )
    entries.sort(key=lambda e: (e["mtime"], e["session_id"]), reverse=True)
    return entries


def resolve_target_path(dashboard_dir, session_id):
    """The absolute path to tail. An explicit session_id maps directly (the
    file itself may not exist yet -- stream_events()'s own loop waits for
    it). Omitted session_id polls until at least one *.jsonl exists, then
    picks the most-recently-modified one."""
    if session_id:
        return os.path.join(dashboard_dir, session_id + ".jsonl")
    while True:
        path = pick_most_recent_jsonl(dashboard_dir)
        if path is not None:
            return path
        time.sleep(POLL_INTERVAL)


def read_increment(path, offset):
    """Read path from offset to EOF, but only through the last newline --
    trailing not-yet-terminated bytes are left for the next call. Returns
    (new_offset, [complete_line_bytes...]). A missing file (deleted, or not
    created yet) returns (None, []), signalling the caller to reset to the
    empty/re-awaited state. A file that shrank below offset (truncated) is
    treated as starting over from 0 in the same call."""
    if not os.path.isfile(path):
        return None, []
    try:
        size = os.path.getsize(path)
    except OSError:
        return None, []
    if size < offset:
        offset = 0
    with open(path, "rb") as fh:
        fh.seek(offset)
        chunk = fh.read()
    if not chunk:
        return offset, []
    last_newline = chunk.rfind(b"\n")
    if last_newline == -1:
        return offset, []
    usable = chunk[: last_newline + 1]
    lines = [line for line in usable.split(b"\n") if line]
    return offset + len(usable), lines


def emit_sse_line(wfile, raw_line):
    """Validate raw_line as JSON (skipping, with a stderr warning, if it
    doesn't parse) and write it as one SSE block. Sends the line exactly as
    read from the log, not a re-serialization. Raises BrokenPipeError /
    ConnectionResetError on a dead client -- the caller catches that."""
    try:
        text = raw_line.decode("utf-8")
    except UnicodeDecodeError:
        sys.stderr.write("WARNING: skipping non-UTF-8 dashboard log line\n")
        return
    try:
        json.loads(text)
    except json.JSONDecodeError:
        preview = text if len(text) <= 200 else text[:200] + "..."
        sys.stderr.write(f"WARNING: skipping malformed JSON dashboard log line: {preview}\n")
        return
    wfile.write(f"data: {text}\n\n".encode("utf-8"))
    wfile.flush()


def stream_events(wfile, target_path):
    """Backlog-then-tail loop: the first pass (offset 0) naturally replays
    the full existing file as the backlog burst; every later pass is an
    incremental tail at the same 200ms cadence. Runs until the connection
    dies (BrokenPipeError propagates to the caller) or the process exits."""
    offset = 0
    while True:
        new_offset, lines = read_increment(target_path, offset)
        offset = 0 if new_offset is None else new_offset
        for raw_line in lines:
            emit_sse_line(wfile, raw_line)
        time.sleep(POLL_INTERVAL)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/events":
            self.handle_events(parsed.query)
        elif parsed.path == "/sessions":
            self.handle_sessions()
        else:
            self.handle_static(parsed.path)

    def handle_events(self, query):
        """session_id for this connection: an explicit ?session= query
        param (sanitized the same way as the CLI arg, F099 -- lets the
        frontend's session picker target any log without the CLI-level
        default ever changing) if present, else the server's own default
        (CLI arg, or auto-select when that was omitted too)."""
        override = urllib.parse.parse_qs(query).get("session", [None])[0]
        session_id = sanitize_session_id(override) if override else self.server.session_id
        target = resolve_target_path(self.server.dashboard_dir, session_id)
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            stream_events(self.wfile, target)
        except (BrokenPipeError, ConnectionResetError, OSError):
            return

    def handle_sessions(self):
        """GET /sessions: every session log currently under dashboard_dir,
        plus the project root the server is bound to (F099) -- lets the
        frontend show the user what they're actually watching instead of
        the server silently guessing, and makes a cross-project server
        reuse visible instead of indistinguishable from 'nothing happening'."""
        body = json.dumps(
            {
                "project": self.server.project_root,
                "sessions": list_sessions(self.server.dashboard_dir),
            }
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_static(self, url_path):
        rel_path = urllib.parse.unquote(url_path)
        if rel_path in ("", "/"):
            rel_path = "/index.html"
        target = os.path.realpath(os.path.join(STATIC_ROOT, rel_path.lstrip("/")))
        if target != STATIC_ROOT and not target.startswith(STATIC_ROOT + os.sep):
            self.send_error(403, "Forbidden")
            return
        if not os.path.isfile(target):
            self.send_error(404, "Not Found")
            return
        content_type = mimetypes.guess_type(target)[0] or "application/octet-stream"
        with open(target, "rb") as fh:
            body = fh.read()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):  # noqa: A002 -- matches base signature
        pass


class DashboardServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True


def build_arg_parser():
    parser = argparse.ArgumentParser(
        description="Dashboard SSE server (F090): streams one harness "
        "session's event log and serves the dashboard's static assets."
    )
    parser.add_argument(
        "session_id",
        nargs="?",
        default=None,
        help="Session to tail; defaults to the most recently modified "
        "*.jsonl under .harness/dashboard/",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help="TCP port to bind on 127.0.0.1 (default: %(default)s)",
    )
    return parser


def main(argv=None):
    args = build_arg_parser().parse_args(argv)
    try:
        server = DashboardServer(("127.0.0.1", args.port), Handler)
    except OSError as exc:
        sys.stderr.write(
            f"ERROR: cannot bind 127.0.0.1:{args.port} ({exc}); "
            "is another dashboard server already running?\n"
        )
        sys.exit(1)
    server.project_root = find_project_root()
    server.dashboard_dir = os.path.join(server.project_root, ".harness", "dashboard")
    server.session_id = sanitize_session_id(args.session_id)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
