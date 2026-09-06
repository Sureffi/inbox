"""inbox — send events to a Claude Code session from Python.

    from inbox import send
    send("latest", "task 3 done", tag="task")

An inbox is a file under $CLAUDE_INBOX_DIR (default /tmp/claude-inbox). Sending an
event is appending one line, so this has no dependency on the `inbox` CLI and never
blocks. A session receives events only while it is listening (`/inbox`); events sent
before that wait in the file.
"""
import os
import time

def inbox_dir():
    return os.environ.get("CLAUDE_INBOX_DIR", "/tmp/claude-inbox")

def path(session):
    """Absolute inbox path for a session name, `latest`, or a full path."""
    p = session if "/" in session else os.path.join(inbox_dir(), session)
    return os.path.realpath(p) if os.path.islink(p) else p

def send(session, event, tag=None, create=False):
    """Append one event to a session's inbox. Returns the inbox path.

    session  a session id/name, "latest", or a full path
    event    the line the session receives
    tag      optional label; arrives as "HH:MM [tag] event"
    create   make the inbox if it does not exist (default: error if missing)
    """
    p = path(session)
    if not os.path.exists(p):
        if not create:
            raise FileNotFoundError(f"no inbox at {p} (pass create=True, or ls {inbox_dir()})")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "a").close()
    stamp = time.strftime("%H:%M")
    line = f"{stamp} [{tag}] {event}\n" if tag else f"{stamp} {event}\n"
    with open(p, "a") as f:
        f.write(line)
    return p
