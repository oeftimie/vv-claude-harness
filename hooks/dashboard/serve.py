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
1) rather than silently falling back to another port. An /events connection
naming an explicit session whose log file does not exist yet waits/polls for
it; an /events connection with NO session named, when no *.jsonl exists
under .harness/dashboard/ at all, gets an immediate 404 instead of a
connection held open with no HTTP response (OVI-146). The rest of the server
(static files, /sessions) is never blocked by a waiting stream, since each
connection runs in its own thread.

Replay bound (OVI-146, documented rather than engineered around): each
/events (re)connect replays the selected session file in full -- there is no
SSE id:/Last-Event-ID resume. Acceptable up to roughly 10 MB per file
(sub-second on loopback); a session log is single-session and typically far
smaller.

Plain foreground script: SIGINT/SIGTERM terminate it via Python's default
signal disposition. No daemon mode, no shutdown endpoint. Idle-exit
(OVI-146): after --idle-exit-seconds (default 600) with no connected /events
client -- measured from process start when no client ever connects -- the
server shuts down and exits 0 on its own, so a detached (nohup'd) server
never squats its port indefinitely after its viewers are gone.
"""
import argparse
import json
import mimetypes
import os
import re
import socketserver
import subprocess
import sys
import threading
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
    it). Omitted session_id picks the most-recently-modified *.jsonl, or
    returns None when no log exists yet -- the caller answers None with an
    immediate 404 instead of holding the request open with no HTTP response
    (OVI-146)."""
    if session_id:
        return os.path.join(dashboard_dir, session_id + ".jsonl")
    return pick_most_recent_jsonl(dashboard_dir)


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
        self.server.note_client(1)
        try:
            if target is None:
                body = b"no session logs under .harness/dashboard/\n"
                self.send_response(404)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            stream_events(self.wfile, target)
        except (BrokenPipeError, ConnectionResetError, OSError):
            return
        finally:
            self.server.note_client(-1)

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

    def __init__(self, addr, handler, idle_exit_seconds):
        super().__init__(addr, handler)
        self.idle_exit_seconds = idle_exit_seconds
        self._clients_lock = threading.Lock()
        self._events_clients = 0
        self._last_client_activity = time.time()

    def note_client(self, delta):
        """Track connected /events clients; any connect/disconnect also
        restamps the idle clock, so the idle window always measures time
        since the LAST client left (or since process start, if none ever
        connected)."""
        with self._clients_lock:
            self._events_clients += delta
            self._last_client_activity = time.time()

    def idle_seconds(self):
        """0.0 while any /events client is connected; otherwise seconds
        since the idle clock was last stamped."""
        with self._clients_lock:
            if self._events_clients > 0:
                return 0.0
            return time.time() - self._last_client_activity


def start_idle_watchdog(server):
    """Daemon thread that shuts the server down (a clean serve_forever()
    unblock, so main() exits 0) once no /events client has been connected
    for idle_exit_seconds. Static/api requests deliberately don't count: a
    page left open without Watch clicked holds no stream, and the page
    itself re-fetches on demand."""
    def watch():
        while True:
            time.sleep(min(1.0, server.idle_exit_seconds / 4.0))
            if server.idle_seconds() >= server.idle_exit_seconds:
                server.shutdown()
                return

    threading.Thread(target=watch, daemon=True).start()


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
    parser.add_argument(
        "--idle-exit-seconds",
        type=float,
        default=600,
        help="exit 0 after this many seconds with no connected /events "
        "client, measured from process start when none ever connects "
        "(default: %(default)s)",
    )
    return parser


def main(argv=None):
    args = build_arg_parser().parse_args(argv)
    try:
        server = DashboardServer(("127.0.0.1", args.port), Handler, args.idle_exit_seconds)
    except OSError as exc:
        sys.stderr.write(
            f"ERROR: cannot bind 127.0.0.1:{args.port} ({exc}); "
            "is another dashboard server already running?\n"
        )
        sys.exit(1)
    server.project_root = find_project_root()
    server.dashboard_dir = os.path.join(server.project_root, ".harness", "dashboard")
    server.session_id = sanitize_session_id(args.session_id)
    start_idle_watchdog(server)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
